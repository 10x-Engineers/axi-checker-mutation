"""Passive data scoreboard on the interposer's observed bus.

It rebuilds memory from the write traffic it sees on obs_* and predicts every read
beat. It stands in for whatever consumes the data downstream, so a mutant it flags but
no checker flags is "caught late by a downstream mismatch". It never fails the test (the
real-path compare in test_axi.py does that); it logs OBS_MISMATCH lines for the harness.
"""

from collections import defaultdict, deque

from cocotb.triggers import RisingEdge
from cocotb.utils import get_sim_time

FIXED, INCR, WRAP = 0, 1, 2


def beat_addrs(addr, length, size, burst):
    """Start address of each beat, per IHI 0022 L SSA3.1.7 p.51 (pseudocode)."""
    n = 1 << size
    beats = length + 1
    if burst == FIXED:
        return [addr] * beats
    aligned = addr & ~(n - 1)
    if burst == INCR:
        return [addr] + [aligned + i * n for i in range(1, beats)]
    total = n * beats
    lower = (addr // total) * total
    out, a = [addr], aligned
    for _ in range(beats - 1):
        a += n
        if a >= lower + total:
            a = lower
        out.append(a)
    return out


class ObsScoreboard:
    def __init__(self, dut, data_bytes):
        self.dut = dut
        self.nb = data_bytes
        self.mem = {}                    # byte address -> value, only bytes seen written
        self.aw = deque()                # write requests awaiting data
        self.wbeats = deque()            # write beats that arrived before their request
        self.cur_w = None                # [addrs, size, beat index, exclusive]
        self.ar = defaultdict(deque)     # per-ID read requests, in issue order
        self.cur_r = {}                  # per-ID [addrs, size, beat index]
        self.mismatches = 0

    def _sig(self, name):
        return int(getattr(self.dut, f"obs_{name}").value)

    def _err(self, msg):
        self.mismatches += 1
        self.dut._log.error("OBS_MISMATCH t=%d %s", get_sim_time("ps"), msg)

    def _write_beat(self, data, strb):
        if self.cur_w is None:
            if not self.aw:
                self.wbeats.append((data, strb))
                return
            self.cur_w = [*self.aw.popleft(), 0]
        addrs, size, excl, i = self.cur_w
        if i < len(addrs):
            base = addrs[i] & ~(self.nb - 1)
            lo = addrs[i] & (self.nb - 1) & ~((1 << size) - 1)
            for lane in range(self.nb):
                if (strb >> lane) & 1 and lo <= lane < lo + (1 << size):
                    if excl:
                        # SSA6.3.4 p.112: a failed exclusive write must not update memory,
                        # and success is only known later, so the bytes become unknown.
                        self.mem.pop(base + lane, None)
                    else:
                        self.mem[base + lane] = (data >> (8 * lane)) & 0xFF
        self.cur_w[3] += 1
        if self.cur_w[3] == len(addrs):
            self.cur_w = None

    def _aw(self):
        addrs = beat_addrs(self._sig("awaddr"), self._sig("awlen"), self._sig("awsize"),
                           self._sig("awburst"))
        self.aw.append((addrs, self._sig("awsize"), bool(self._sig("awlock"))))
        while self.wbeats and (self.cur_w is not None or self.aw):
            self._write_beat(*self.wbeats.popleft())

    def _r(self):
        rid = self._sig("rid")
        cur = self.cur_r.get(rid)
        if cur is None:
            if not self.ar[rid]:
                self._err(f"read data for ID {rid:#x} with no outstanding request")
                return
            cur = self.cur_r[rid] = [*self.ar[rid].popleft(), 0]
        addrs, size, i = cur
        data = self._sig("rdata")
        if i < len(addrs):
            base = addrs[i] & ~(self.nb - 1)
            lo = addrs[i] & (self.nb - 1) & ~((1 << size) - 1)
            for lane in range(lo, lo + (1 << size)):
                want = self.mem.get(base + lane)
                got = (data >> (8 * lane)) & 0xFF
                if want is not None and want != got:
                    self._err(f"rid={rid:#x} addr={base + lane:#x} got {got:#04x} want {want:#04x}")
                    break
        cur[2] += 1
        if cur[2] == len(addrs):
            del self.cur_r[rid]

    async def run(self):
        clk = self.dut.clk
        while True:
            await RisingEdge(clk)
            if int(self.dut.rst.value):
                continue
            if self._sig("awvalid") and self._sig("awready"):
                self._aw()
            if self._sig("wvalid") and self._sig("wready"):
                self._write_beat(self._sig("wdata"), self._sig("wstrb"))
            if self._sig("arvalid") and self._sig("arready"):
                self.ar[self._sig("arid")].append(
                    (beat_addrs(self._sig("araddr"), self._sig("arlen"), self._sig("arsize"),
                                self._sig("arburst")), self._sig("arsize")))
            if self._sig("rvalid") and self._sig("rready"):
                self._r()
