"""Reference AXI4 traffic through the interposer into axi_ram.

The same stimulus runs for every mutant and every checker set, so a verdict
difference is the checker's, never the traffic's. The read-back compare here is
the real-path scoreboard: it must pass on every run, because the interposer never
corrupts the real path.
"""

import itertools
import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge
from cocotbext.axi import AxiBurstType, AxiBus, AxiLockType, AxiMaster

from obs_scoreboard import ObsScoreboard

SEED = 1


async def reset(dut):
    dut.rst.value = 1
    await ClockCycles(dut.clk, 5)
    dut.rst.value = 0
    await ClockCycles(dut.clk, 2)


def stimulus(rng):
    """(addr, length_bytes, burst). The fixed head is what catalog/mutants.toml
    triggers on by address, so its order and addresses are part of the catalog's
    contract; the random tail only adds background traffic."""
    ops = [
        (0x100, 4, AxiBurstType.INCR),     # 1 beat
        (0x110, 8, AxiBurstType.INCR),     # 2 beats
        (0x120, 16, AxiBurstType.INCR),    # 4 beats  (3rd transaction: *last-missing)
        (0x140, 64, AxiBurstType.INCR),    # 16 beats (ar-4kb-cross)
        (0x600, 12, AxiBurstType.INCR),    # 3 beats  (aw-wrap-len3, excl-bytes-not-pow2)
        (0x504, 16, AxiBurstType.INCR),    # 4 beats, not 16-aligned (excl-misaligned)
        (0x1000, 128, AxiBurstType.INCR),  # 32 beats, 128-aligned (ar-fixed-len32, excl-len32)
        (0x400, 16, AxiBurstType.WRAP),    # 4-beat wrap, aligned
        (0x508, 32, AxiBurstType.WRAP),    # 8-beat wrap, starts mid-container
    ]
    for _ in range(8):
        ops.append((0x2000 + (rng.randrange(0, 0x800) & ~3), 4 * rng.randint(1, 16),
                    AxiBurstType.INCR))
    return ops


@cocotb.test()
async def reference_traffic(dut):
    rng = random.Random(SEED)
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    dut.m_axi_awqos.value = 0
    dut.m_axi_awregion.value = 0
    dut.m_axi_awuser.value = 0
    dut.m_axi_wuser.value = 0
    dut.m_axi_arqos.value = 0
    dut.m_axi_arregion.value = 0
    dut.m_axi_aruser.value = 0
    axi = AxiMaster(AxiBus.from_prefix(dut, "m_axi"), dut.clk, dut.rst)
    cocotb.start_soon(ObsScoreboard(dut, len(dut.obs_wdata) // 8).run())
    await reset(dut)

    mismatches = 0
    # Explicit IDs: cocotbext-axi otherwise hands them out round-robin, and the catalog's
    # ID triggers rely on IDs 3 and up being used only where this file says.
    for i, (addr, length, burst) in enumerate(stimulus(rng)):
        data = bytes(rng.randrange(256) for _ in range(length))
        await axi.write(addr, data, awid=i % 3, burst=burst)
        got = (await axi.read(addr, length, arid=i % 3, burst=burst)).data
        if burst != AxiBurstType.WRAP and got != data:
            mismatches += 1
            dut._log.error("DATA_MISMATCH addr=0x%x len=%d", addr, length)

    # Two back-to-back reads with the same ID, outstanding together: the shape the
    # same-ID ordering mutants need.
    await axi.write(0x3000, bytes(range(16)), awid=0)
    await axi.write(0x3100, bytes(range(16, 32)), awid=0)
    r0 = axi.init_read(0x3000, 16, arid=3)
    r1 = axi.init_read(0x3100, 16, arid=3)
    await r0.wait()
    await r1.wait()
    if r0.data.data != bytes(range(16)) or r1.data.data != bytes(range(16, 32)):
        mismatches += 1
        dut._log.error("DATA_MISMATCH same-ID pair")

    await exclusive_tail(axi)
    mismatches += await variety_tail(dut, axi)

    await ClockCycles(dut.clk, 10)
    assert mismatches == 0, f"{mismatches} real-path data mismatches"


async def variety_tail(dut, axi):
    """Legal traffic shapes a checker must not flag: narrow and unaligned transfers
    (SSA3.2.3 p.55, SSA3.2.5 p.58), several IDs outstanding at once (SSA5.3 p.93), and
    Manager back-pressure on R and B (SSA2.3.2 p.31). Kept after every catalog trigger
    so the nth-beat triggers above are unaffected."""
    bad = 0
    axi.read_if.r_channel.set_pause_generator(itertools.cycle([0, 1, 1, 0, 0, 1, 0]))
    axi.write_if.b_channel.set_pause_generator(itertools.cycle([1, 1, 0]))
    for addr, data, size in ((0x900, bytes(range(8)), 0),        # byte-wide beats
                             (0x921, bytes(range(40, 47)), 1),   # halfword, unaligned
                             (0x946, bytes(range(80, 100)), 2)):  # full width, unaligned
        await axi.write(addr, data, awid=1, size=size)
        got = (await axi.read(addr, len(data), arid=1, size=size)).data
        if got != data:
            bad += 1
            dut._log.error("DATA_MISMATCH narrow/unaligned addr=0x%x", addr)
    blobs = {0xA00 + 0x40 * i: bytes((i * 16 + k) & 0xFF for k in range(16)) for i in range(4)}
    writes = [axi.init_write(a, d, awid=13 + i) for i, (a, d) in enumerate(blobs.items())]
    for w in writes:
        await w.wait()
    reads = [axi.init_read(a, 16, arid=13 + i) for i, a in enumerate(blobs)]
    for r, (a, d) in zip(reads, blobs.items()):
        await r.wait()
        if r.data.data != d:
            bad += 1
            dut._log.error("DATA_MISMATCH concurrent read addr=0x%x", a)
    # Not set_pause_generator(None): cocotbext-axi kills the pause task without clearing
    # its pause flag, so a kill mid-pause would hold READY low for ever.
    axi.read_if.r_channel.set_pause_generator(itertools.repeat(0))
    axi.write_if.b_channel.set_pause_generator(itertools.repeat(0))
    # An INCR read issued while the last write request was a WRAP: the same read rules must
    # hold whatever the other channel last carried (catalog: ar-4kb-cross-after-wrap).
    await axi.write(0xB00, bytes(range(16)), awid=2, burst=AxiBurstType.WRAP)
    got = (await axi.read(0xB40, 64, arid=2)).data
    return bad


async def exclusive_tail(axi):
    """Exclusive sequences, all legal as issued. axi_ram has no exclusive monitor, so it
    answers OKAY throughout (IHI 0022 L SSA6.3.2 p.111). IDs 5-12 appear only here;
    3 is the same-ID pair above and 13-16 the concurrent reads in variety_tail."""
    ex = AxiLockType.EXCLUSIVE
    # Read answered OKAY, so 0x700 is not monitored; the exclusive write must then fail.
    await axi.read(0x700, 4, arid=5, lock=ex)
    await axi.write(0x700, b"\x01\x02\x03\x04", awid=5, lock=ex)
    # Exclusive read, an intervening normal write to the same location, exclusive write.
    await axi.read(0x780, 4, arid=6, lock=ex)
    await axi.write(0x780, b"\x05\x06\x07\x08", awid=0)
    await axi.write(0x780, b"\x09\x0a\x0b\x0c", awid=6, lock=ex)
    # 4-beat exclusive read, 16-byte aligned.
    await axi.read(0x7C0, 16, arid=8, lock=ex)
    # Exclusive write issued as soon as its exclusive read completes.
    await axi.read(0x7E0, 4, arid=9, lock=ex)
    await axi.write(0x7E0, b"\x0d\x0e\x0f\x10", awid=9, lock=ex)
    # Legal corners a strict checker may flag: SSA6.3.3 p.111 Table A6.5 says the pair
    # *should* match, so a mismatched ID only makes the write fail; and an exclusive write
    # with no exclusive read before it is legal and must simply fail.
    await axi.read(0x800, 4, arid=10, lock=ex)
    await axi.write(0x800, b"\x11\x12\x13\x14", awid=11, lock=ex)
    await axi.write(0x840, b"\x15\x16\x17\x18", awid=12, lock=ex)
