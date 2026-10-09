# EBAZ4205 Vivado board files

Board definition `miner.ebang.com.cn:ebaz4205:part0:1.0` (xc7z010clg400-1) with a PS7 preset:
UART1 on MIO 24/25, SD0 on MIO 40-45, ENET0 via EMIO (MII, 100 Mbps), DDR3 MT41K128M16 JT-125 (16-bit),
and the two user LEDs as a GPIO interface.

Source: https://github.com/XyleMora/EBAZ4205/tree/main/Documents/Board%20files (MIT, see `LICENSE-XyleMora`).
Files are unmodified.

## Use in Vivado (2025.x and newer)

Vivado 2025.x keeps boards in the xhub board store under the install root (not under `Vivado/`).
For an install at `~/Xilinx/2025.2`:

    cp -r hw/board_files/ebaz4205 ~/Xilinx/2025.2/data/xhub/boards/XilinxBoardStore/boards/Xilinx/

Tested on Vivado 2025.2: `get_board_parts *ebaz4205*` finds it with no extra setup, no restart needed
for batch runs (restart the GUI). Replace `2025.2` with your version; find the root with `which vivado`
(`<root>/<version>/Vivado/bin/vivado`). A later update of the Xilinx board store may remove the copy;
re-copy it, or use the no-install option below.

No-install option (tested on Vivado 2025.2), in the Tcl console or at the top of a batch script:

    set_param board.repoPaths [list <repo>/hw/board_files]

Then, in either case:

    set_property board_part miner.ebang.com.cn:ebaz4205:part0:1.0 [current_project]

In a block design, `apply_board_preset "1"` on the PS7 automation loads the preset.
`hw/scripts/build_bd.tcl` does not use the board file; it sets the same PS7 values explicitly.

Note: the board file maps `leds_2bits_tri_o[0]` to W14 and `[1]` to W13, the reverse of the
`led[0]`=W13 / `led[1]`=W14 order used in `hw/constraints/ethernet.xdc`.
