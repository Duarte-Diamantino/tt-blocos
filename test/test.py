# SPDX-License-Identifier: Apache-2.0
#
# cocotb tests for tt_um_duarte_diamantino_blocos (8x8 falling-block game on VGA),
# run by the Tiny Tapeout CI on the RTL and on the gate-level netlist (make GATES=yes).
# Only the top-level pins are used: the VGA output is read the way a monitor would.
# The detailed game rules (line clears, walls, game over) are tested much faster in
# sim/tb.v, which forces a short frame period on the RTL.

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge, Timer

CLK_NS = 40                     # 25 MHz in simulation (25.175 MHz on the board)
H_TOTAL, V_TOTAL = 800, 525     # 640x480 @ 60 Hz timing
V_SYNC_START = 490
FRAME = H_TOTAL * V_TOTAL       # 420 000 clocks

LEFT, RIGHT, ROTATE, DOWN = 0, 1, 2, 3

# colours as (R, G, B), 2 bits each
BACKGROUND = (0, 0, 1)
WALL = (1, 1, 2)
EMPTY = (0, 0, 0)
SQUARE = (1, 3, 2)              # colour of piece type 1, the first piece after reset
SCORE_OFF = (0, 0, 2)


def val(sig):
    v = sig.value
    return v.to_unsigned() if hasattr(v, "to_unsigned") else int(v)


def cell(col, row):
    """Screen coordinates of the centre of a board cell (32x32 px, board at 192,96)."""
    return 192 + 32 * col + 16, 96 + 32 * row + 16


def score_square(bit):
    """Centre of the score square for one bit (MSB at the top)."""
    return 528, 96 + 32 * (7 - bit) + 16


async def start(dut):
    clock = Clock(dut.clk, CLK_NS, unit="ns")
    clock.start()
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1


async def sample_frame(dut, points):
    """Waits for VSync and reads the colour of each (x, y) pixel of the next frame."""
    await FallingEdge(dut.vsync)            # (h, v) = (0, 490) has just been output
    t_prev = 0
    colours = {}
    for x, y in sorted(points, key=lambda p: p[1] * H_TOTAL + p[0]):
        clocks = (V_TOTAL - V_SYNC_START) * H_TOTAL + y * H_TOTAL + x
        t = clocks * CLK_NS + CLK_NS // 2   # half a clock after that pixel is output
        await Timer(t - t_prev, unit="ns")
        t_prev = t
        colours[(x, y)] = (val(dut.red), val(dut.green), val(dut.blue))
    return colours


async def press(dut, button):
    """Holds a button for one frame and releases it for one frame."""
    dut.ui_in.value = 1 << button
    await FallingEdge(dut.vsync)            # the game reads the buttons at line 480
    dut.ui_in.value = 0
    await FallingEdge(dut.vsync)


@cocotb.test()
async def test_vga_timing(dut):
    """HSync and VSync have the 640x480 @ 60 Hz widths and periods."""
    await start(dut)
    assert val(dut.uio_oe) == 0xFF, "uio pins must all be outputs (score)"
    assert val(dut.uio_out) == 0, "score must be 0 after reset"

    await FallingEdge(dut.hsync)
    await Timer(CLK_NS // 2 + 95 * CLK_NS, unit="ns")
    assert val(dut.hsync) == 0, "HSync shorter than 96 clocks"
    await Timer(CLK_NS, unit="ns")
    assert val(dut.hsync) == 1, "HSync longer than 96 clocks"
    await Timer((H_TOTAL - 97) * CLK_NS, unit="ns")
    assert val(dut.hsync) == 1, "line shorter than 800 clocks"
    await Timer(CLK_NS, unit="ns")
    assert val(dut.hsync) == 0, "line longer than 800 clocks"

    await FallingEdge(dut.vsync)
    await Timer(CLK_NS // 2 + (2 * H_TOTAL - 1) * CLK_NS, unit="ns")
    assert val(dut.vsync) == 0, "VSync shorter than 2 lines"
    await Timer(CLK_NS, unit="ns")
    assert val(dut.vsync) == 1, "VSync longer than 2 lines"
    await Timer((FRAME - 2 * H_TOTAL - 1) * CLK_NS, unit="ns")
    assert val(dut.vsync) == 1, "frame shorter than 525 lines"
    await Timer(CLK_NS, unit="ns")
    assert val(dut.vsync) == 0, "frame longer than 525 lines"


@cocotb.test()
async def test_screen_after_reset(dut):
    """The first frame shows the walls, an empty well, the first piece and a zero score."""
    await start(dut)
    expected = {
        (40, 40): BACKGROUND,
        (176, 200): WALL,                   # left wall
        (464, 200): WALL,                   # right wall
        (320, 368): WALL,                   # floor
        cell(0, 0): EMPTY,
        cell(7, 7): EMPTY,
        cell(4, 0): EMPTY,
        cell(2, 0): SQUARE,                 # first piece: square at columns 2-3, rows 0-1
        cell(3, 0): SQUARE,
        cell(2, 1): SQUARE,
        cell(3, 1): SQUARE,
        cell(2, 2): EMPTY,
        score_square(0): SCORE_OFF,
        score_square(7): SCORE_OFF,
    }
    got = await sample_frame(dut, list(expected))
    for point, colour in expected.items():
        assert got[point] == colour, f"pixel {point}: colour {got[point]}, expected {colour}"


@cocotb.test()
async def test_move(dut):
    """LEFT and RIGHT move the piece one column per press; the left wall stops it."""
    await start(dut)

    await press(dut, LEFT)
    got = await sample_frame(dut, [cell(1, 0), cell(2, 0), cell(3, 0)])
    assert got[cell(1, 0)] == SQUARE and got[cell(2, 0)] == SQUARE, "piece did not move left"
    assert got[cell(3, 0)] == EMPTY, "piece left a trail"

    await press(dut, LEFT)
    await press(dut, LEFT)                  # against the wall: must be ignored
    got = await sample_frame(dut, [cell(0, 0), cell(1, 0), cell(2, 0)])
    assert got[cell(0, 0)] == SQUARE and got[cell(1, 0)] == SQUARE, "piece not at the left wall"
    assert got[cell(2, 0)] == EMPTY, "piece went through the wall"

    await press(dut, RIGHT)
    got = await sample_frame(dut, [cell(0, 0), cell(1, 0), cell(2, 0)])
    assert got[cell(0, 0)] == EMPTY, "piece did not move right"
    assert got[cell(1, 0)] == SQUARE and got[cell(2, 0)] == SQUARE, "piece did not move right"
