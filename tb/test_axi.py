"""Reference AXI4 traffic through the interposer into axi_ram.

The same stimulus runs for every mutant and every checker set, so a verdict
difference is the checker's, never the traffic's. The read-back compare here is
the real-path scoreboard: it must pass on every run, because the interposer never
corrupts the real path.
"""

import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge
from cocotbext.axi import AxiBurstType, AxiBus, AxiMaster

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
    await reset(dut)

    mismatches = 0
    for addr, length, burst in stimulus(rng):
        data = bytes(rng.randrange(256) for _ in range(length))
        await axi.write(addr, data, burst=burst)
        got = (await axi.read(addr, length, burst=burst)).data
        if burst != AxiBurstType.WRAP and got != data:
            mismatches += 1
            dut._log.error("DATA_MISMATCH addr=0x%x len=%d", addr, length)

    # Two back-to-back reads with the same ID, outstanding together: the shape the
    # same-ID ordering mutants need.
    await axi.write(0x3000, bytes(range(16)))
    await axi.write(0x3100, bytes(range(16, 32)))
    r0 = axi.init_read(0x3000, 16, arid=3)
    r1 = axi.init_read(0x3100, 16, arid=3)
    await r0.wait()
    await r1.wait()
    if r0.data.data != bytes(range(16)) or r1.data.data != bytes(range(16, 32)):
        mismatches += 1
        dut._log.error("DATA_MISMATCH same-ID pair")

    await ClockCycles(dut.clk, 10)
    assert mismatches == 0, f"{mismatches} real-path data mismatches"
