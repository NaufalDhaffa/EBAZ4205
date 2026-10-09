# EBAZ4205 PS/PL setup

Bring-up of the EBAZ4205 board (Zynq-7010, `xc7z010clg400-1`, ex-Ebit E9+ miner control board)
from scratch: a scripted Vivado block design for the PS7, plus small baremetal test apps.

Verified over JTAG (tag `stabil-1`):

| Peripheral | Config | Test app |
|---|---|---|
| UART1 | MIO 24/25, 115200 8N1 | `uart_test` |
| DDR3 | MT41K128M16 JT-125, 16-bit, 256 MB | `ddr_test` |
| SD0 | MIO 40-45, FatFs | `sd_diag`, `sd_fatfs_test` |
| ENET0 | EMIO MII to IP101GA, 100 Mbps, lwIP echo on port 7 | `eth_test` |

## Layout

| Path | Content |
|---|---|
| `hw/scripts/build_bd.tcl` | Builds the project, PS7 block design, bitstream, and `.xsa` in batch mode |
| `hw/constraints/ethernet.xdc` | Ethernet MII/MDIO pins and clocks, LEDs (the only PL pins the design needs) |
| `hw/constraints/ebaz4205.xdc` | Full board header pin map (clock, Ethernet, DATA1-3, LEDs, J5/J3), all commented, reference only |
| `hw/board_files/` | Vivado board definition for the EBAZ4205 (see its README) |
| `sw/apps/*/src` | Baremetal test apps (sources only; BSP and build output are generated) |
| `docs/BOARD_CONFIG.md` | PS7 settings, pin tables, sources, bring-up notes and fixes |

Generated and git-ignored: `hw/build/`, `sw/workspace/` (BSP), `sw/dts/` (device tree and `ps7_init`), `sw/apps/*/build/`.

## Build the hardware

From the repo root:

    vivado -mode batch -source hw/scripts/build_bd.tcl -nolog -nojournal

Produces `hw/build/stereo_cam.xsa` and the bitstream under `hw/build/stereo_cam_hw.runs/impl_1/`.
The script was written and run on Vivado 2026.1; it has not been re-run on the Vivado 2025.2
currently installed on the author's machine.

## Build and run an app

The Vitis 2026.1 flow (`sdtgen` + `empyro`, no `xsct`):

    sdtgen -xsa hw/build/stereo_cam.xsa -dir sw/dts
    empyro create_bsp -w sw/workspace -s sw/dts/system-top.dts -p ps7_cortexa9_0 -o standalone
    empyro config_bsp -d sw/workspace -al lwip220 xilffs
    empyro build_app -s sw/apps/uart_test/src -b sw/apps/uart_test/build

Notes:
- Re-running `create_bsp` drops added libraries; run `config_bsp -al lwip220 xilffs` again before `build_app`.
- For `eth_test`, force 100 Mbps (auto-detect negotiated 10 Mbps on this board):
  `empyro config_bsp -d sw/workspace -st lwip220 "lwip220_temac_phy_link_speed:CONFIG_LINKSPEED100"`.
  The test IP is 192.168.2.10/24, set in `sw/apps/eth_test/src/main.c`.
- Details and the reasons behind each fix are in `docs/BOARD_CONFIG.md`.

## Program over JTAG

No FSBL: program the PL, then initialize the PS and run the ELF, in two separate `xsdb` processes.
`hw_server` must be running (start it in an interactive terminal).

    xsdb -eval "connect -url TCP:127.0.0.1:3121; fpga -file hw/build/stereo_cam_hw.runs/impl_1/system_wrapper.bit"

    xsdb -eval '
    connect -url TCP:127.0.0.1:3121
    targets -set -filter {name =~ "ARM*#0"}
    rst -processor
    source sw/dts/ps7_init.tcl
    ps7_init
    ps7_post_config
    dow sw/apps/uart_test/build/uart_test.elf
    con
    '

Start the UART capture before programming so the first lines are not lost. On Linux the JTAG probe
(FT232H) may need `ftdi_sio` unbound first, e.g. `echo -n "7-1:1.0" | sudo tee /sys/bus/usb/drivers/ftdi_sio/unbind`
(the bus id varies; check `lsusb`). If `xsdb -eval` prints nothing without a TTY, run it through
`<Vitis>/bin/loader -exec xsdb -eval ...`, which skips the `rlwrap` wrapper.

## Vivado board files

To pick the EBAZ4205 as a board in Vivado, copy `hw/board_files/ebaz4205` into the xhub board store
(`<Xilinx root>/<version>/data/xhub/boards/XilinxBoardStore/boards/Xilinx/`). See
`hw/board_files/README.md`. The block design script does not need it.

## License

MIT, see `LICENSE`. The files in `hw/board_files/` come from
[XyleMora/EBAZ4205](https://github.com/XyleMora/EBAZ4205) (MIT, `hw/board_files/LICENSE-XyleMora`).
