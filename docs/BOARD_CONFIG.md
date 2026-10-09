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
