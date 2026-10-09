# Build the stereo_cam PS7 block design for EBAZ4205 (XC7Z010CLG400) from
# scratch in Vivado 2026.1 batch mode.
#
# Recreated (not imported) from nightseas/ebit_z7010's 2018.3 project, since
# that repo can't be cloned from this environment and cross-version .xpr
# import carries its own risk. PS7 CONFIG.PCW_* values below were extracted
# from that repo's block-design Tcl; pin/direction/width facts for the raw
# EMIO Ethernet signals were queried directly from the installed 2026.1 PS7
# IP (xilinx.com:ip:processing_system7:5.5) rather than assumed. See
# ../../docs/BOARD_CONFIG.md for the full derivation and sources.

set proj_dir  [file normalize [file join [file dirname [info script]] .. build]]
set repo_root [file normalize [file join [file dirname [info script]] .. ..]]

create_project stereo_cam_hw $proj_dir -part xc7z010clg400-1 -force
set_property target_language Verilog [current_project]

create_bd_design "system"

# --- PS7 ---
set ps7 [create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 ps7_0]

apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
  -config {make_external "FIXED_IO, DDR" apply_board_preset "0" Master "Disable" Slave "Disable"} \
  $ps7

set_property -dict [list \
  CONFIG.PCW_USE_M_AXI_GP0                 {0} \
  CONFIG.PCW_UART1_PERIPHERAL_ENABLE       {1} \
  CONFIG.PCW_UART1_UART1_IO                {MIO 24 .. 25} \
  CONFIG.PCW_SD0_PERIPHERAL_ENABLE         {1} \
  CONFIG.PCW_SD0_SD0_IO                    {MIO 40 .. 45} \
  CONFIG.PCW_SD0_GRP_CD_ENABLE             {0} \
  CONFIG.PCW_SD0_GRP_POW_ENABLE            {0} \
  CONFIG.PCW_SD0_GRP_WP_ENABLE             {0} \
  CONFIG.PCW_SDIO_PERIPHERAL_FREQMHZ       {100} \
  CONFIG.PCW_ENET0_PERIPHERAL_ENABLE       {1} \
  CONFIG.PCW_ENET0_ENET0_IO                {EMIO} \
  CONFIG.PCW_ENET0_GRP_MDIO_ENABLE         {1} \
  CONFIG.PCW_ENET0_GRP_MDIO_IO             {EMIO} \
  CONFIG.PCW_ENET0_PERIPHERAL_FREQMHZ      {100 Mbps} \
  CONFIG.PCW_GPIO_EMIO_GPIO_ENABLE         {1} \
  CONFIG.PCW_GPIO_EMIO_GPIO_IO             {EMIO} \
  CONFIG.PCW_GPIO_EMIO_GPIO_WIDTH          {2} \
  CONFIG.PCW_UIPARAM_DDR_PARTNO            {MT41K128M16 JT-125} \
  CONFIG.PCW_UIPARAM_DDR_BUS_WIDTH         {16 Bit} \
  CONFIG.PCW_UIPARAM_DDR_ECC               {Disabled} \
  CONFIG.PCW_UIPARAM_ACT_DDR_FREQ_MHZ      {533.333374} \
  CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ      {50} \
  CONFIG.PCW_TTC0_PERIPHERAL_ENABLE        {1} \
] $ps7

# --- Ethernet: raw MII pins (not the bundled 8-bit GMII interface) ---
# Board only wires 4-bit MII (10/100). get_bd_pins does not support bit-range
# addressing on a bus pin (confirmed by trial: "No pins matched ...[3:0]"),
# so bit splitting/joining goes through xlslice/xlconcat cells instead,
# connected via whole-pin nets.
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant xlconst_rxd_hi
set_property -dict [list CONFIG.CONST_WIDTH {4} CONFIG.CONST_VAL {0}] [get_bd_cells xlconst_rxd_hi]

create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat xlconcat_rxd
set_property -dict [list CONFIG.NUM_PORTS {2} CONFIG.IN0_WIDTH {4} CONFIG.IN1_WIDTH {4}] [get_bd_cells xlconcat_rxd]

create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice xlslice_txd
set_property -dict [list CONFIG.DIN_WIDTH {8} CONFIG.DIN_FROM {3} CONFIG.DIN_TO {0} CONFIG.DOUT_WIDTH {4}] [get_bd_cells xlslice_txd]

create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant xlconst_eth_misc
set_property -dict [list CONFIG.CONST_WIDTH {1} CONFIG.CONST_VAL {0}] [get_bd_cells xlconst_eth_misc]

create_bd_port -dir I eth_rx_clk
create_bd_port -dir I -from 3 -to 0 eth_rxd
create_bd_port -dir I eth_rx_dv
create_bd_port -dir I eth_tx_clk
create_bd_port -dir O eth_tx_en
create_bd_port -dir O -from 3 -to 0 eth_txd

connect_bd_net [get_bd_ports eth_rx_clk]              [get_bd_pins ps7_0/ENET0_GMII_RX_CLK]
connect_bd_net [get_bd_ports eth_rxd]                 [get_bd_pins xlconcat_rxd/In0]
connect_bd_net [get_bd_pins xlconst_rxd_hi/dout]      [get_bd_pins xlconcat_rxd/In1]
connect_bd_net [get_bd_pins xlconcat_rxd/dout]        [get_bd_pins ps7_0/ENET0_GMII_RXD]
connect_bd_net [get_bd_ports eth_rx_dv]               [get_bd_pins ps7_0/ENET0_GMII_RX_DV]
connect_bd_net [get_bd_ports eth_tx_clk]              [get_bd_pins ps7_0/ENET0_GMII_TX_CLK]
connect_bd_net [get_bd_ports eth_tx_en]               [get_bd_pins ps7_0/ENET0_GMII_TX_EN]
connect_bd_net [get_bd_pins ps7_0/ENET0_GMII_TXD]     [get_bd_pins xlslice_txd/Din]
connect_bd_net [get_bd_pins xlslice_txd/Dout]         [get_bd_ports eth_txd]
connect_bd_net [get_bd_pins xlconst_eth_misc/dout] [list \
  [get_bd_pins ps7_0/ENET0_GMII_COL] \
  [get_bd_pins ps7_0/ENET0_GMII_CRS] \
  [get_bd_pins ps7_0/ENET0_GMII_RX_ER] \
]
# ENET0_GMII_TX_ER is a PS7 output with nothing to drive on this board —
# left unconnected, which is valid for BD outputs.

# MDIO is a proper tri-state interface pin on the PS7 IP (I/O/T bundle) —
# use the bundled interface so Vivado inserts the IOBUF, instead of wiring
# ENET0_MDIO_I/O/T by hand.
# Match on the pin's own string form (confirmed by direct probe to be
# "/ps7_0/MDIO_ETHERNET_0") rather than get_property/return-value chaining,
# both of which produced "Invalid option value ''" when tried.
set mdio_pin {}
foreach ip [get_bd_intf_pins -of_objects [get_bd_cells ps7_0]] {
  if {[string match "*MDIO_ETHERNET_0" $ip]} { set mdio_pin $ip }
}
if {$mdio_pin eq {}} { error "MDIO_ETHERNET_0 interface pin not found on ps7_0" }
make_bd_intf_pins_external $mdio_pin

set mdio_port {}
foreach p [get_bd_intf_ports] {
  if {[string match "*MDIO_ETHERNET_0*" $p]} { set mdio_port $p }
}
if {$mdio_port eq {}} { error "externalized MDIO port not found" }
set_property name eth_mdio $mdio_port

# --- Board LEDs on EMIO GPIO[1:0] (output only) ---
create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice xlslice_led_o
set_property -dict [list CONFIG.DIN_WIDTH {64} CONFIG.DIN_FROM {1} CONFIG.DIN_TO {0} CONFIG.DOUT_WIDTH {2}] [get_bd_cells xlslice_led_o]
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant xlconst_gpio_i
set_property -dict [list CONFIG.CONST_WIDTH {64} CONFIG.CONST_VAL {0}] [get_bd_cells xlconst_gpio_i]
create_bd_port -dir O -from 1 -to 0 led
connect_bd_net [get_bd_pins ps7_0/GPIO_O]         [get_bd_pins xlslice_led_o/Din]
connect_bd_net [get_bd_pins xlslice_led_o/Dout]   [get_bd_ports led]
connect_bd_net [get_bd_pins xlconst_gpio_i/dout]  [get_bd_pins ps7_0/GPIO_I]
# GPIO_T (tri-state control PS7 would drive to an IOBUF) is left
# unconnected — LEDs here are wired as plain push-pull outputs, no IOBUF.

validate_bd_design
save_bd_design

make_wrapper -files [get_files system.bd] -top
add_files -norecurse [file join $proj_dir stereo_cam_hw.gen sources_1 bd system hdl system_wrapper.v]
set_property top system_wrapper [current_fileset]

add_files -fileset constrs_1 -norecurse [file join $repo_root hw constraints ethernet.xdc]

update_compile_order -fileset sources_1

launch_runs synth_1 -jobs [expr {[exec nproc] < 4 ? [exec nproc] : 4}]
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
  error "synth_1 did not complete successfully"
}

launch_runs impl_1 -to_step write_bitstream -jobs [expr {[exec nproc] < 4 ? [exec nproc] : 4}]
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
  error "impl_1 did not complete successfully"
}

open_run impl_1
write_hw_platform -fixed -include_bit -force [file join $proj_dir stereo_cam.xsa]

puts "BUILD_OK: bitstream + xsa written to $proj_dir"
