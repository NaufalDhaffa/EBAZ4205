# EBAZ4205 Vivado board files

Board definition `miner.ebang.com.cn:ebaz4205:part0:1.0` (xc7z010clg400-1) with a PS7 preset:
UART1 on MIO 24/25, SD0 on MIO 40-45, ENET0 via EMIO (MII, 100 Mbps), DDR3 MT41K128M16 JT-125 (16-bit),
and the two user LEDs as a GPIO interface.

Source: https://github.com/XyleMora/EBAZ4205/tree/main/Documents/Board%20files (MIT, see `LICENSE-XyleMora`).
Files are unmodified.

## Use in Vivado

Option 1, install: copy the `ebaz4205` folder to `<Vivado install>/data/boards/board_files/` and restart Vivado.

Option 2, no install (Tcl console or batch script):

    set_param board.repoPaths [list <repo>/hw/board_files]
    set_property board_part miner.ebang.com.cn:ebaz4205:part0:1.0 [current_project]

In a block design, `apply_board_preset "1"` on the PS7 automation loads the preset.
`hw/scripts/build_bd.tcl` does not use the board file; it sets the same PS7 values explicitly.

Note: the board file maps `leds_2bits_tri_o[0]` to W14 and `[1]` to W13, the reverse of the
`led[0]`=W13 / `led[1]`=W14 order used in `hw/constraints/ethernet.xdc`.
