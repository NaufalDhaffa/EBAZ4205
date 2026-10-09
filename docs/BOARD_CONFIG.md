# EBAZ4205 (Zynq XC7Z010CLG400) board config — stereo_cam project

Sources used to derive this (kept here so this research is never redone):
- PS7 `CONFIG.PCW_*` values: `nightseas/ebit_z7010`,
  `ebit_z7010.srcs/sources_1/bd/ebit_z7010_top/ebit_z7010_top.bd` (Vivado
  2018.3 block-design Tcl). That repo's `constrs_1` is empty — no `.xdc`
  shipped.
- LED pins + DATA1/2/3 header pin table: `xjtuecho/EBAZ4205`,
  `Development/EBAZ4205.xdc` (a commented-out template; no Ethernet/SD pins
  in it either).
- IP101GA PHY signal names: board schematic PDF,
  `nightseas/ebit_z7010/documents/ebaz4205_sch.pdf`. Flat PDF-to-text
  extraction preserved signal names (TXD0-3, RXD0-3, TXCLK, RXCLK, MDC,
  MDIO, COL, CRS, RXER, TXER, RESET.N) but lost which FPGA package ball each
  wire lands on — **do not re-derive Ethernet pins from that PDF alone**.
- Ethernet PL pin numbers below: supplied directly by the board owner
  (verified against physical board / prior measurement), not re-derived
  independently. Cross-checked as schematically plausible: U14/U15 are
  MRCC-capable pins (fits being external MII clock inputs); the other pins
  fall in the same I/O bank block as other confirmed board signals.

## PS7 configuration

| Peripheral | IO | Config |
|---|---|---|
| UART1 | MIO 24 (TX) / 25 (RX) | no modem control lines |
| SD0 | MIO 40-45 (clk/cmd/data0-3) | no CD/WP/POW pins |
| ENET0 | EMIO (MDIO also EMIO) | 100 Mbps MII |
| GPIO | MIO (misc) + EMIO x2 | EMIO[0]/[1] -> board LEDs |
| DDR3 | dedicated PS_DDR package pins, no user XDC | part `MT41K128M16 JT-125`, 16-bit bus, ECC disabled, `PCW_DDR_RAM_HIGHADDR=0x0FFFFFFF` (256 MB) |
| FCLK0 | 50 MHz | matches reference design default |

Only Ethernet and the two LEDs need a project `.xdc` (`hw/constraints/ethernet.xdc`) —
everything else (UART1, SD0, DDR3) is on dedicated/MIO pins configured
entirely inside the PS7 IP, no top-level port constraints needed.

## Ethernet (IP101GA MII, via EMIO) pin map

| Signal | Zynq package pin | Note |
|---|---|---|
| eth_rx_clk | U14 | MRCC-capable, PHY-supplied 25 MHz |
| eth_rxd[0] | Y16 | |
| eth_rxd[1] | V16 | |
| eth_rxd[2] | V17 | |
| eth_rxd[3] | Y17 | |
| eth_rx_dv | W16 | |
| eth_tx_clk | U15 | MRCC-capable, PHY-supplied 25 MHz |
| eth_tx_en | W19 | |
| eth_txd[0] | W18 | |
| eth_txd[1] | Y18 | |
| eth_txd[2] | V18 | |
| eth_txd[3] | Y19 | |
| eth_mdio_mdc (MDC) | W15 | supplied by board owner |
| eth_mdio_mdio_io (MDIO) | Y14 | supplied by board owner |

## Board LEDs

| Signal | Pin | Color |
|---|---|---|
| led_green | W13 | green |
| led_red | W14 | red |

## Ethernet bring-up: confirmed working config

Board IP `192.168.2.10` / `255.255.255.0` / gw `192.168.2.1`, matching the
laptop's dedicated wired link (`eno1` statically configured at
`192.168.2.1/24`, no DHCP server on that link, kept separate from the
laptop's normal `wlo1`/internet connection). Verified end-to-end: link up at
100 Mbps, `ping` 0% loss ~0.1ms RTT, TCP echo (port 7) round-trips data
correctly.

Two lwIP BSP config fixes were required beyond the template default
(`sw/apps/eth_test`, lib `lwip220`), both set via
`empyro config_bsp -d sw/workspace -st lwip220 "<key>:<value>"`:
- `lwip220_temac_phy_link_speed:CONFIG_LINKSPEED100` — template default is
  `CONFIG_LINKSPEED_AUTODETECT`, which negotiated down to 10 Mbps on this
  board's PHY instead of the expected 100. Forcing 100 fixed it.
- `lwip220_dhcp:false` + `lwip220_lwip_dhcp_does_acd_check:false` — template
  default is DHCP-on with a "fall back to static IP after timeout" path, but
  on this point-to-point link (no DHCP server) that fallback never actually
  triggered in practice (the app hung waiting on `dhcp_timoutcntr`, which
  depends on a periodic DHCP timer callback this simple polling app doesn't
  service). Disabling DHCP entirely takes the immediate static-IP code path
  instead. Note: `LWIP_DHCP_DOES_ACD_CHECK`/`LWIP_ACD` must be turned off
  together with `LWIP_DHCP` — lwIP's own `init.c` has a `#error` guard if
  ACD-check is left on while DHCP is off.
- Static IP itself is set in `sw/apps/eth_test/src/main.c` (`IP4_ADDR` calls),
  not a BSP property — edit that directly if the IP/subnet ever needs to
  change.

## SD card bring-up: resolved (was physical card seating, not software)

`f_mount()` intermittently failed with `FR_NOT_READY` (`XSdPs_CardInitialize`
status 1). A driver-timing fix was tried first (a controlled two-path test
seemed to show a bare monolithic call failing while the same steps with a
delay between each succeeded), but a *bare, unpatched, unmodified* retry
also failed 3/3 times right after — disproving the timing theory. What
actually correlated with success/failure was the physical SD card being
removed and reinserted: after firmly reseating the card, the bare vendor
driver (no modifications at all) passed `f_mount`/`f_write`/read-back
3 attempts in a row, every time, with zero timing changes.

**Root cause: marginal physical contact in the SD slot, not a logic or
timing bug.** No driver patch is needed or present — `sw/workspace/libsrc/sdps/`
is the unmodified vendor driver. If `FR_NOT_READY` recurs, reseat the card
first before suspecting software; UART1/DDR3/Ethernet were all confirmed
solid throughout this investigation, and the SD MIO pins need no custom
constraints per the PS7 config table above, so pin mapping was never in
question either.

`sw/apps/sd_diag` is kept as a standalone low-level diagnostic (calls
`XSdPs_CfgInitialize`/`XSdPs_CardInitialize` directly, bypassing FatFs) for
any future SD issue — it isolates "did the raw driver call succeed" from
whatever FatFs/`disk_initialize()` layers on top.

## Boot target

SD-card boot is baremetal/standalone: FSBL + bitstream + app ELF packaged
into `BOOT.bin` via `bootgen`. Not a full U-Boot+Linux image (that's a
separate, much larger undertaking — cross-building U-Boot, kernel, rootfs —
out of scope here unless requested later).

## Camera (OV7670) — Y8 QVGA capture -> UDP streaming

Appended, not a rewrite — every section above is unchanged (see the plan
file this was built from: `EnterPlanMode`/`ExitPlanMode` transcript, "OV7670
Y8 QVGA Camera Pipeline" — Rule 2 in that plan explicitly protected
UART1/SD0/ENET0/DDR3/Clocking, and every value in those existing sections
above is still exactly what's in `hw/scripts/build_bd.tcl`).

### PS7 additions for this feature

| Addition | Value | Why |
|---|---|---|
| `PCW_USE_M_AXI_GP0` | `0` → `1` | VDMA register/control access (AXI-Lite) |
| `PCW_USE_S_AXI_HP0` | (absent) → `1` | VDMA's high-bandwidth path to DDR3 |
| `PCW_I2C0_PERIPHERAL_ENABLE` + `PCW_I2C0_I2C0_IO=EMIO` | new | SCCB (I2C-compatible) to OV7670 |
| `PCW_FPGA_FCLK1_ENABLE` + `PCW_FPGA1_PERIPHERAL_FREQMHZ=24` + `PCW_EN_CLK1_PORT` | new | camera XCLK (24MHz) — **all three** properties are required to actually expose the `FCLK_CLK1` pin; confirmed by direct probe, `PCW_FPGA_FCLK1_ENABLE` alone is not sufficient |
| FCLK0 | unchanged, 50MHz | reused as the new AXI/VDMA bus clock — ~2.3MB/s needed vs ~200MB/s available, no reason to touch it |

I2C0 EMIO pin names (`I2C0_SCL_I/O/T`, `I2C0_SDA_I/O/T`) and the `axi_vdma:6.3`
IP's `s_axis_s2mm_tuser` pin + `c_s2mm_sof_enable` config (defaults to `1`,
"Enable Start Of Frame on tuser(0)") were confirmed by direct probe against
the installed IP before being wired in `build_bd.tcl`, not assumed.

### Camera header pin map (DATA1/DATA2 headers)

| Signal | Pin | Note |
|---|---|---|
| cam_sioc (SCCB clock) | A20 | |
| cam_pclk | H16 | declared as a real clock in `camera.xdc` (general I/O pin, not MRCC) |
| cam_siod (SCCB data) | B19 | |
| cam_vsync | B20 | |
| cam_href | C20 | |
| cam_xclk | H17 | FCLK1 (24MHz), driven from FPGA to camera |
| cam_pdata[7:0] | D20,D18,H18,D19,F20,E19,F19,K17 | |
| cam_reset_n | G20 | tied static high (see below) |
| cam_pwdn | J18 | tied static low (see below) |

### OV7670 register set — one correction from the original spec

`COM3 (0x0C)`: original spec said `0x08` (Scale-enable bit only). Per the
official OmniVision datasheet (Table 5), bit[3]=Scale-enable and bit[2]=DCW-
enable are separate bits, and this design's `COM7=0x00` (no pre-defined-
format bits set) means scaling is manual (`COM14` bit[3]=1) via the
`SCALING_*` registers, not COM7's pre-defined-format path — in that mode the
universally-replicated working OV7670 QVGA register set uses **`COM3=0x04`**
(DCW-enable), which is what `sw/apps/cam_stream/src/ov7670.c` uses. Every
other register value from the original spec (`CLKRC=0x01`, `COM15=0xC0`,
`COM14=0x19`, `SCALING_XSC=0x3A`, `SCALING_YSC=0x35`,
`SCALING_DCW_CTR=0x11`, `SCALING_PCLK_DIV=0xF1`, `COM8=0xE7`) is unchanged.

### VDMA buffer addresses — one correction from the original spec

Original spec suggested `0x10000000`/`0x10040000` as example ping-pong
buffer addresses. **Both are outside the valid DDR3 range** on this board
(`PCW_DDR_RAM_HIGHADDR=0x0FFFFFFF`, i.e. 256MB — `0x10000000` is exactly one
byte past the end of physical DDR3) and would have caused a bus error /
memory corruption on real hardware. Corrected to `0x03000000`/`0x03100000`
(`sw/apps/cam_stream/src/vdma.h`), safely inside the 256MB range with ample
margin from a baremetal app's own code/stack/heap.

### UDP packet format — one correction from the original spec

Header: `frame_id` (u32, big-endian/`htonl`), `packet_index` (u16),
`total_packets` (u16, both `htons`) = 8 bytes, followed by up to 1016 bytes
of payload. 76800 bytes / 1016 is **not** an integer (75.59), so while the
original spec's "76 packets/frame" figure is correct
(`ceil(76800/1016)=76`), that only works if the **last packet carries the
600-byte remainder**, not a full 1016 bytes like the first 75
(`sw/apps/cam_stream/src/udp_stream.c` computes this generically rather than
assuming uniform packet size; `scripts/receiver/udp_receiver.py` matches).

### Known simplifications in this first working version

- **`cam_reset_n`/`cam_pwdn` are tied static** (reset_n=1 "not in reset",
  pwdn=0 "not powered down") rather than software-controlled via GPIO —
  relies on the OV7670's own internal POR. Add GPIO control (same EMIO GPIO
  pattern already used for the board LEDs) if bring-up shows the camera
  needs an explicit reset pulse from software.
- **Frame-completion detection is polling** (`XAxiVdma_CurrFrameStore`
  compared each loop iteration), not interrupt-driven, even though
  `axi_vdma` supports S2MM frame-count interrupts — avoids driving
  `udp_sendto()` from inside an ISR (lwIP raw API is meant to run from a
  single main-loop context) for no real benefit at 30fps.
- **`usleep()`/`sleep()`/`msleep()` require `XilSleepTimer_Init(&TimerInst)`**
  to work at all in a bare `empty_application`-based app (confirmed by
  reading `xiltimer.c`: they're silent no-ops otherwise, since `TimerInst`'s
  function pointer starts NULL) — `sw/apps/cam_stream/src/main.c` calls this
  directly rather than pulling in the full `lwip_echo_server` template's
  `platform.c`/`init_timer()` machinery (that mechanism is for periodic
  TCP/DHCP timers this UDP-only app doesn't need).
- Custom RTL modules (`ov7670_to_axis_y8`, `axis_byte_packer32`) are added to
  the block design via `create_bd_cell -type module -reference`, not
  packaged as formal IP-XACT components — Vivado emits one benign, expected
  `CRITICAL WARNING: [BD 41-967] AXI interface pin ... is not associated to
  any clock pin` for this because it can't verify a manually-wired pin group
  against its own naming-convention heuristics. All pins (including clocks)
  are wired explicitly via `connect_bd_net`, so this doesn't affect actual
  netlist correctness — confirmed by clean synthesis/implementation and
  positive timing slack (WNS well positive).

## Camera (OV7670) — Y8 QVGA capture pipeline

Pins (DATA1/DATA2 headers), all LVCMOS33:

| Signal | Pin | Signal | Pin |
|---|---|---|---|
| cam_sioc | A20 | cam_pdata[3] | F20 |
| cam_pclk | H16 | cam_pdata[2] | E19 |
| cam_siod | B19 | cam_pdata[1] | F19 |
| cam_vsync | B20 | cam_pdata[0] | K17 |
| cam_href | C20 | cam_reset_n | G20 |
| cam_xclk | H17 | cam_pwdn | J18 |
| cam_pdata[7:4] | D20/D18/H18/D19 | | |

`cam_reset_n`/`cam_pwdn` tied static (1/0) for now — relies on the sensor's
internal POR; add GPIO control if bring-up shows it needs a real reset pulse.

PS7 additions (append-only, `hw/scripts/build_bd.tcl`): GP0 + HP0 enabled
(were off), I2C0 via EMIO, FCLK1=24MHz for XCLK (needs `PCW_EN_CLK1_PORT`,
not just `PCW_FPGA_FCLK1_ENABLE` — the port stays hidden without it).
UART1/SD0/ENET0/DDR3/Clocking(FCLK0) untouched.

Pipeline: `ov7670_to_axis_y8` → `axis_byte_packer32` (32-bit pack) →
`axis_data_fifo` (async CDC, cam_pclk→FCLK0) → `axi_vdma` (S2MM only,
`c_s2mm_sof_enable=1` default — TUSER-qualified SOF, confirmed via probe of
the installed `axi_vdma:6.3`, not assumed) → DDR3.

DDR3 ping-pong buffers: `0x03000000` / `0x03100000` (an earlier draft used
`0x10000000`/`0x10040000`, which is outside the valid 256MB DDR3 range —
corrected).

OV7670 register set (SCCB, 7-bit addr `0x21`): `COM7=0x80`→100ms delay→
`CLKRC=0x01`, `COM7=0x00`, `COM15=0xC0`, `COM3=0x04` (datasheet: bit3=Scale
enable, bit2=DCW enable — this design uses manual/DCW scaling, not COM7's
pre-defined-format path, so `0x04` not `0x08`), `COM14=0x19`,
`SCALING_XSC=0x3A`, `SCALING_YSC=0x35`, `SCALING_DCWCTR=0x11`,
`SCALING_PCLK_DIV=0xF1`, `COM8=0xE7`.

`usleep()`/`sleep()` need `XilSleepTimer_Init(&TimerInst)` called once at
startup — without it they're silent no-ops (same root cause as the earlier
SD card investigation: bare `empty_application` apps never call
`platform_init()`, which is what normally sets this up).

UDP: board `192.168.2.10` → PC `192.168.2.1:12345`, DHCP off (same static-IP
setup as `eth_test`). 76800-byte frame split into 76 packets of up to 1016
bytes payload each — 75 full packets + one 600-byte final packet (76800 is
not evenly divisible by 1016; an earlier draft assumed all 76 were uniform).

Frame-completion detection is polling (`XAxiVdma_CurrFrameStore`), not
interrupt-driven — avoids running lwIP's raw API from inside a VDMA ISR.
