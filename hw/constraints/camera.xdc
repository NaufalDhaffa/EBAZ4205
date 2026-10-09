# OV7670 camera header pin constraints (DATA1/DATA2 headers, EBAZ4205).
# Pin numbers supplied by board owner. All camera header signals are
# LVCMOS33, matching the rest of this header (see hw/constraints/ethernet.xdc
# for the LED pins on the same DATA-header bank).

set_property -dict {PACKAGE_PIN A20 IOSTANDARD LVCMOS33} [get_ports {cam_sioc}]
set_property -dict {PACKAGE_PIN H16 IOSTANDARD LVCMOS33} [get_ports {cam_pclk}]
set_property -dict {PACKAGE_PIN B19 IOSTANDARD LVCMOS33} [get_ports {cam_siod}]
set_property -dict {PACKAGE_PIN B20 IOSTANDARD LVCMOS33} [get_ports {cam_vsync}]
set_property -dict {PACKAGE_PIN C20 IOSTANDARD LVCMOS33} [get_ports {cam_href}]
set_property -dict {PACKAGE_PIN H17 IOSTANDARD LVCMOS33} [get_ports {cam_xclk}]

set_property -dict {PACKAGE_PIN D20 IOSTANDARD LVCMOS33} [get_ports {cam_pdata[7]}]
set_property -dict {PACKAGE_PIN D18 IOSTANDARD LVCMOS33} [get_ports {cam_pdata[6]}]
set_property -dict {PACKAGE_PIN H18 IOSTANDARD LVCMOS33} [get_ports {cam_pdata[5]}]
set_property -dict {PACKAGE_PIN D19 IOSTANDARD LVCMOS33} [get_ports {cam_pdata[4]}]
set_property -dict {PACKAGE_PIN F20 IOSTANDARD LVCMOS33} [get_ports {cam_pdata[3]}]
set_property -dict {PACKAGE_PIN E19 IOSTANDARD LVCMOS33} [get_ports {cam_pdata[2]}]
set_property -dict {PACKAGE_PIN F19 IOSTANDARD LVCMOS33} [get_ports {cam_pdata[1]}]
set_property -dict {PACKAGE_PIN K17 IOSTANDARD LVCMOS33} [get_ports {cam_pdata[0]}]

set_property -dict {PACKAGE_PIN G20 IOSTANDARD LVCMOS33} [get_ports {cam_reset_n}]
set_property -dict {PACKAGE_PIN J18 IOSTANDARD LVCMOS33} [get_ports {cam_pwdn}]

# PCLK arrives on H16 (IO_L13P_T2_MRCC_35, clock-capable). It still has to
# be declared explicitly so timing analysis treats it as a real clock domain.
#
# Period below (41.667ns = 24MHz) is a conservative WORST-CASE upper bound,
# not a measured value: PCLK is derived from XCLK (24MHz, driven by this
# design) through OV7670's internal prescaler (CLKRC) and scaling divider
# (COM14/SCALING_PCLK_DIV), which only ever divide down from XCLK in this
# register configuration (no PLL multiply is enabled) -- so real PCLK will
# be at or below 24MHz, never above it. Constraining to the faster bound is
# the safe direction (real design will have more slack than analyzed, never
# less). Tighten this to the actual measured PCLK once available on
# hardware (e.g. via ILA or frequency counter during bring-up).
#
create_clock -name cam_pclk -period 41.667 -waveform {0 20.8} [get_ports {cam_pclk}]

# litescope_top_0's internal CDC (cam_pclk capture domain <-> sys/FCLK0
# control domain, via Migen's MultiReg/AsyncFIFO) and csr_gpio_bridge_0's
# GPIO_O toggle synchronizers are both real 2-flop synchronizers, so a
# failing/unconstrained cam_pclk<->clk_fpga_0 timing report here is
# expected, same as the cam_cdc_fifo crossing below -- not a real
# violation.

# No explicit set_clock_groups/false-path declaration between cam_pclk and
# clk_fpga_0 (PS7 FCLK0) here: the actual CDC safety comes from
# cam_cdc_fifo (xilinx.com:ip:axis_data_fifo, CONFIG.IS_ACLK_ASYNC=1 in
# hw/scripts/build_bd.tcl), which generates its own internal synchronizer
# logic and timing constraints for exactly this crossing. A static XDC
# declaration was tried here but `if` (needed to guard it, since
# clk_fpga_0 -- confirmed correct via the routed design's clock utilization
# report -- isn't resolvable at every stage this file is evaluated) is not
# supported inside a static XDC file ("Command 'if' is not supported in the
# xdc constraint file", confirmed by trial). Expect the timing report to
# show cam_pclk<->clk_fpga_0 as an unconstrained/failing inter-clock path --
# that is expected for a domain crossing that goes only through the FIFO's
# own synchronizers, not a real violation.

# --- Camera 2 (DATA3 header, bank 34; reset_n/pwdn on DATA2_7/DATA2_8) ---
# Uncomment together with the cam2_* ports in build_bd.tcl. Left commented
# because get_ports on a missing port fails the whole XDC. cam2_pclk (N20) is
# SRCC; period matches camera 1.
#set_property -dict {PACKAGE_PIN M19 IOSTANDARD LVCMOS33} [get_ports {cam2_sioc}]
#set_property -dict {PACKAGE_PIN N20 IOSTANDARD LVCMOS33} [get_ports {cam2_pclk}]
#set_property -dict {PACKAGE_PIN P18 IOSTANDARD LVCMOS33} [get_ports {cam2_siod}]
#set_property -dict {PACKAGE_PIN M17 IOSTANDARD LVCMOS33} [get_ports {cam2_vsync}]
#set_property -dict {PACKAGE_PIN N17 IOSTANDARD LVCMOS33} [get_ports {cam2_href}]
#set_property -dict {PACKAGE_PIN P20 IOSTANDARD LVCMOS33} [get_ports {cam2_xclk}]
#set_property -dict {PACKAGE_PIN R18 IOSTANDARD LVCMOS33} [get_ports {cam2_pdata[7]}]
#set_property -dict {PACKAGE_PIN R19 IOSTANDARD LVCMOS33} [get_ports {cam2_pdata[6]}]
#set_property -dict {PACKAGE_PIN P19 IOSTANDARD LVCMOS33} [get_ports {cam2_pdata[5]}]
#set_property -dict {PACKAGE_PIN T20 IOSTANDARD LVCMOS33} [get_ports {cam2_pdata[4]}]
#set_property -dict {PACKAGE_PIN U20 IOSTANDARD LVCMOS33} [get_ports {cam2_pdata[3]}]
#set_property -dict {PACKAGE_PIN T19 IOSTANDARD LVCMOS33} [get_ports {cam2_pdata[2]}]
#set_property -dict {PACKAGE_PIN V20 IOSTANDARD LVCMOS33} [get_ports {cam2_pdata[1]}]
#set_property -dict {PACKAGE_PIN U19 IOSTANDARD LVCMOS33} [get_ports {cam2_pdata[0]}]
#set_property -dict {PACKAGE_PIN G19 IOSTANDARD LVCMOS33} [get_ports {cam2_reset_n}]
#set_property -dict {PACKAGE_PIN H20 IOSTANDARD LVCMOS33} [get_ports {cam2_pwdn}]
#create_clock -name cam2_pclk -period 41.667 -waveform {0 20.8} [get_ports {cam2_pclk}]
