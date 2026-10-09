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
  CONFIG.PCW_GPIO_EMIO_GPIO_WIDTH          {64} \
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

# =============================================================================
# --- OV7670 Y8 QVGA camera capture pipeline (append-only; see
# docs/BOARD_CONFIG.md "Camera (OV7670)" section for full derivation) ---
# =============================================================================
# PS7 additions for this feature only. Every UART1/SD0/ENET0/DDR3/Clocking
# key from the set_property call above is untouched; FCLK0 stays at 50MHz
# and becomes this pipeline's AXI bus clock (~2.3MB/s needed vs ~200MB/s
# available at 50MHz/32-bit -- ample headroom, no reason to change it).
set_property -dict [list \
  CONFIG.PCW_USE_M_AXI_GP0                 {1} \
  CONFIG.PCW_USE_S_AXI_HP0                 {1} \
  CONFIG.PCW_I2C0_PERIPHERAL_ENABLE        {1} \
  CONFIG.PCW_I2C0_I2C0_IO                  {EMIO} \
  CONFIG.PCW_FPGA_FCLK1_ENABLE             {1} \
  CONFIG.PCW_FPGA1_PERIPHERAL_FREQMHZ      {24} \
  CONFIG.PCW_EN_CLK1_PORT                  {1} \
] $ps7

# --- Custom RTL modules ---
set rtl_dir [file join $repo_root hw rtl]
add_files -norecurse [list \
  [file join $rtl_dir ov7670_to_axis_y8.v] \
  [file join $rtl_dir axis_byte_packer32.v] \
  [file join $rtl_dir iic_emio_iobuf.v] \
]
update_compile_order -fileset sources_1

set cam_front [create_bd_cell -type module -reference ov7670_to_axis_y8 cam_front_0]
set cam_pack  [create_bd_cell -type module -reference axis_byte_packer32 cam_pack_0]
set cam_iobuf [create_bd_cell -type module -reference iic_emio_iobuf cam_iic_iobuf_0]

# --- Camera external ports (pins constrained in hw/constraints/camera.xdc) ---
create_bd_port -dir I cam_pclk
create_bd_port -dir I cam_vsync
create_bd_port -dir I cam_href
create_bd_port -dir I -from 7 -to 0 cam_pdata
create_bd_port -dir O cam_reset_n
create_bd_port -dir O cam_pwdn
create_bd_port -dir O cam_xclk
create_bd_port -dir IO cam_sioc
create_bd_port -dir IO cam_siod

# cam_front_0 (PCLK domain): OV7670 pixel interface -> 8-bit Y8 AXI-Stream
connect_bd_net [get_bd_ports cam_pclk]  [get_bd_pins cam_front_0/pclk]
connect_bd_net [get_bd_ports cam_vsync] [get_bd_pins cam_front_0/vsync]
connect_bd_net [get_bd_ports cam_href]  [get_bd_pins cam_front_0/href]
connect_bd_net [get_bd_ports cam_pdata] [get_bd_pins cam_front_0/d]

# cam_pack_0 (still PCLK domain): 8-bit Y8 beats -> 32-bit packed words
connect_bd_net [get_bd_pins cam_front_0/pclk]         [get_bd_pins cam_pack_0/clk]
connect_bd_net [get_bd_pins cam_front_0/m_axis_tdata]  [get_bd_pins cam_pack_0/s_axis_tdata]
connect_bd_net [get_bd_pins cam_front_0/m_axis_tvalid] [get_bd_pins cam_pack_0/s_axis_tvalid]
connect_bd_net [get_bd_pins cam_front_0/m_axis_tlast]  [get_bd_pins cam_pack_0/s_axis_tlast]
connect_bd_net [get_bd_pins cam_front_0/m_axis_tuser]  [get_bd_pins cam_pack_0/s_axis_tuser]
connect_bd_net [get_bd_pins cam_pack_0/s_axis_tready]  [get_bd_pins cam_front_0/m_axis_tready]

# --- XCLK generation: FCLK1 (24MHz) -> camera XCLK pin ---
# No explicit buffer IP needed/available (there is no "util_buf" IP in this
# Vivado install -- confirmed by probe) -- this is a plain output port, and
# Vivado auto-inserts the correct output buffer at synthesis, same as this
# file's existing eth_rx_clk/eth_tx_clk ports (also plain ports, no buffer
# primitive instantiated).
connect_bd_net [get_bd_pins ps7_0/FCLK_CLK1] [get_bd_ports cam_xclk]

# --- SCCB (I2C0 EMIO) via IOBUF wrapper ---
connect_bd_net [get_bd_pins ps7_0/I2C0_SCL_O] [get_bd_pins cam_iic_iobuf_0/scl_i_from_ps]
connect_bd_net [get_bd_pins ps7_0/I2C0_SCL_T] [get_bd_pins cam_iic_iobuf_0/scl_t_from_ps]
connect_bd_net [get_bd_pins cam_iic_iobuf_0/scl_o_to_ps] [get_bd_pins ps7_0/I2C0_SCL_I]
connect_bd_net [get_bd_pins ps7_0/I2C0_SDA_O] [get_bd_pins cam_iic_iobuf_0/sda_i_from_ps]
connect_bd_net [get_bd_pins ps7_0/I2C0_SDA_T] [get_bd_pins cam_iic_iobuf_0/sda_t_from_ps]
connect_bd_net [get_bd_pins cam_iic_iobuf_0/sda_o_to_ps] [get_bd_pins ps7_0/I2C0_SDA_I]
connect_bd_net [get_bd_ports cam_sioc] [get_bd_pins cam_iic_iobuf_0/cam_sioc]
connect_bd_net [get_bd_ports cam_siod] [get_bd_pins cam_iic_iobuf_0/cam_siod]

# --- cam_reset_n / cam_pwdn: tied static for this first bring-up pass ---
# (RESET_N=1 "not in reset", PWDN=0 "not powered down" -- relies on the
# sensor's own internal POR rather than a software-controlled pulse; add
# GPIO-driven control later if bring-up shows the camera needs an explicit
# reset pulse from software.)
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant xlconst_cam_reset_n
set_property -dict [list CONFIG.CONST_WIDTH {1} CONFIG.CONST_VAL {1}] [get_bd_cells xlconst_cam_reset_n]
connect_bd_net [get_bd_pins xlconst_cam_reset_n/dout] [get_bd_ports cam_reset_n]
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant xlconst_cam_pwdn
set_property -dict [list CONFIG.CONST_WIDTH {1} CONFIG.CONST_VAL {0}] [get_bd_cells xlconst_cam_pwdn]
connect_bd_net [get_bd_pins xlconst_cam_pwdn/dout] [get_bd_ports cam_pwdn]

# --- Clock-domain crossing: cam_pclk domain -> FCLK0 (AXI bus clock) domain ---
create_bd_cell -type ip -vlnv xilinx.com:ip:axis_data_fifo cam_cdc_fifo
set_property -dict [list \
  CONFIG.IS_ACLK_ASYNC     {1} \
  CONFIG.TDATA_NUM_BYTES   {4} \
  CONFIG.HAS_TLAST         {1} \
  CONFIG.TUSER_WIDTH       {1} \
] [get_bd_cells cam_cdc_fifo]
connect_bd_net [get_bd_pins cam_front_0/pclk]        [get_bd_pins cam_cdc_fifo/s_axis_aclk]
connect_bd_net [get_bd_pins ps7_0/FCLK_CLK0]         [get_bd_pins cam_cdc_fifo/m_axis_aclk]
connect_bd_net [get_bd_pins cam_pack_0/m_axis_tdata]  [get_bd_pins cam_cdc_fifo/s_axis_tdata]
connect_bd_net [get_bd_pins cam_pack_0/m_axis_tvalid] [get_bd_pins cam_cdc_fifo/s_axis_tvalid]
connect_bd_net [get_bd_pins cam_pack_0/m_axis_tlast]  [get_bd_pins cam_cdc_fifo/s_axis_tlast]
connect_bd_net [get_bd_pins cam_pack_0/m_axis_tuser]  [get_bd_pins cam_cdc_fifo/s_axis_tuser]
connect_bd_net [get_bd_pins cam_cdc_fifo/s_axis_tready] [get_bd_pins cam_pack_0/m_axis_tready]

# --- AXI VDMA: S2MM capture only, TUSER-qualified Start-of-Frame sync ---
# c_s2mm_sof_enable defaults to 1 ("Enable Start Of Frame on tuser(0)") on
# this installed IP (xilinx.com:ip:axi_vdma:6.3) -- confirmed by direct
# probe, not assumed, before writing this. c_include_mm2s is explicitly
# disabled since this design only ever captures (S2MM), never plays back.
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_vdma cam_vdma
set_property -dict [list \
  CONFIG.c_include_mm2s        {0} \
  CONFIG.c_include_s2mm        {1} \
  CONFIG.c_s2mm_sof_enable     {1} \
  CONFIG.c_m_axi_s2mm_data_width {32} \
  CONFIG.c_m_axis_mm2s_tdata_width {32} \
  CONFIG.c_num_fstores         {2} \
] [get_bd_cells cam_vdma]
connect_bd_net [get_bd_pins ps7_0/FCLK_CLK0] [get_bd_pins cam_vdma/s_axis_s2mm_aclk]
connect_bd_net [get_bd_pins cam_cdc_fifo/m_axis_tdata]  [get_bd_pins cam_vdma/s_axis_s2mm_tdata]
connect_bd_net [get_bd_pins cam_cdc_fifo/m_axis_tvalid] [get_bd_pins cam_vdma/s_axis_s2mm_tvalid]
connect_bd_net [get_bd_pins cam_cdc_fifo/m_axis_tlast]  [get_bd_pins cam_vdma/s_axis_s2mm_tlast]
connect_bd_net [get_bd_pins cam_cdc_fifo/m_axis_tuser]  [get_bd_pins cam_vdma/s_axis_s2mm_tuser]
connect_bd_net [get_bd_pins cam_vdma/s_axis_s2mm_tready] [get_bd_pins cam_cdc_fifo/m_axis_tready]

# GP0 -> VDMA AXI-Lite control, VDMA M_AXI_S2MM -> HP0 data path. Left to
# Vivado's own connection automation (inserts whatever AXI Interconnect /
# SmartConnect / clock-domain handling is actually needed) rather than
# hand-built, since GP0/HP0 are being freshly enabled in this same script
# and their exact default clock/reset net names are safer to resolve via
# automation than to assume.
apply_bd_automation -rule xilinx.com:bd_rule:axi4 \
  -config {Master "/ps7_0/M_AXI_GP0" Clk "Auto"} \
  [get_bd_intf_pins cam_vdma/S_AXI_LITE]
apply_bd_automation -rule xilinx.com:bd_rule:axi4 \
  -config {Master "/cam_vdma/M_AXI_S2MM" Clk "Auto"} \
  [get_bd_intf_pins ps7_0/S_AXI_HP0]

# --- cam_cdc_fifo reset -- ROOT CAUSE of curframe never advancing, found
# via direct hardware probe: cam_cdc_fifo/s_axis_aresetn (active-low) was
# never connected to anything anywhere in this script. An unconnected
# active-low reset on this IP synthesizes to a permanently-asserted reset,
# which silently swallows everything written to the FIFO forever -- input
# side (from cam_pack_0) looked completely normal in every probe, but
# m_axis_tvalid on the OUTPUT side never went high even once across an
# entire multi-second capture, while cam_pack_0 immediately upstream was
# actively emitting hundreds of real beats. Every downstream symptom
# (VDMA never seeing a frame, regardless of how correct the upstream
# TLAST/TUSER framing was) traces back to this one missing wire.
# rst_ps7_0_50M is the proc_sys_reset the AXI4 automation above already
# auto-created for the FCLK_CLK0 domain (confirmed present in the built
# design's .hwh, already driving peripheral_aresetn for other FCLK0
# peripherals) -- reused here rather than instantiating a second one.
connect_bd_net [get_bd_pins rst_ps7_0_50M/peripheral_aresetn] [get_bd_pins cam_cdc_fifo/s_axis_aresetn]

# --- LiteScope logic analyzer (replaces both the unusable Vivado ILA and
# the earlier GPIO activity-counter probe). Core is Migen-generated
# (hw/scripts/gen_litescope.py) into hw/rtl/generated/litescope_top.v --
# regenerated fresh on every build (not committed) to avoid the stale-IP
# staleness class of bug hit with the earlier ILA attempt. It exposes a
# CSR bus that csr_gpio_bridge.v relays over the same PS7 GPIO_I/GPIO_O
# EMIO path the old probe used, since the ARM firmware bridges litex's
# UART wire protocol onto it (no spare physical UART pin on this board --
# see docs/SESSION_HANDOFF.md).
set litescope_gen_py [file join $repo_root hw scripts gen_litescope.py]
set litescope_venv_py [file join $repo_root tools litex_venv bin python]
# Vivado's own PYTHONHOME/PYTHONPATH would otherwise leak into this child
# process and break the venv's Python (wrong stdlib version).
if {[info exists ::env(PYTHONHOME)]} { unset ::env(PYTHONHOME) }
if {[info exists ::env(PYTHONPATH)]} { unset ::env(PYTHONPATH) }
set gen_result [exec $litescope_venv_py $litescope_gen_py]
puts $gen_result

add_files -norecurse [list \
  [file join $rtl_dir generated litescope_top.v] \
  [file join $rtl_dir csr_gpio_bridge.v] \
]
update_compile_order -fileset sources_1

set litescope_top [create_bd_cell -type module -reference litescope_top litescope_top_0]
set csr_bridge     [create_bd_cell -type module -reference csr_gpio_bridge csr_gpio_bridge_0]

connect_bd_net [get_bd_pins ps7_0/FCLK_CLK0] [get_bd_pins litescope_top_0/sys_clk]
connect_bd_net [get_bd_ports cam_pclk]       [get_bd_pins litescope_top_0/cam_pclk_raw]
connect_bd_net [get_bd_ports cam_vsync]      [get_bd_pins litescope_top_0/cam_vsync]
connect_bd_net [get_bd_ports cam_href]       [get_bd_pins litescope_top_0/cam_href]
connect_bd_net [get_bd_ports cam_pdata]      [get_bd_pins litescope_top_0/cam_pdata]
connect_bd_net [get_bd_pins cam_front_0/m_axis_tvalid] [get_bd_pins litescope_top_0/axis_tvalid]
connect_bd_net [get_bd_pins cam_front_0/m_axis_tlast]  [get_bd_pins litescope_top_0/axis_tlast]
connect_bd_net [get_bd_pins cam_front_0/m_axis_tuser]  [get_bd_pins litescope_top_0/axis_tuser]
connect_bd_net [get_bd_pins cam_front_0/m_axis_tdata]  [get_bd_pins litescope_top_0/axis_tdata]

connect_bd_net [get_bd_pins ps7_0/FCLK_CLK0] [get_bd_pins csr_gpio_bridge_0/clk]
connect_bd_net [get_bd_pins ps7_0/GPIO_O]    [get_bd_pins csr_gpio_bridge_0/gpio_o]
connect_bd_net [get_bd_pins csr_gpio_bridge_0/gpio_i] [get_bd_pins ps7_0/GPIO_I]

connect_bd_net [get_bd_pins litescope_top_0/csr_bus_adr]   [get_bd_pins csr_gpio_bridge_0/csr_adr]
connect_bd_net [get_bd_pins litescope_top_0/csr_bus_we]    [get_bd_pins csr_gpio_bridge_0/csr_we]
connect_bd_net [get_bd_pins litescope_top_0/csr_bus_re]    [get_bd_pins csr_gpio_bridge_0/csr_re]
connect_bd_net [get_bd_pins litescope_top_0/csr_bus_dat_w] [get_bd_pins csr_gpio_bridge_0/csr_dat_w]
connect_bd_net [get_bd_pins csr_gpio_bridge_0/csr_dat_r]   [get_bd_pins litescope_top_0/csr_bus_dat_r]

validate_bd_design
save_bd_design

make_wrapper -files [get_files system.bd] -top
add_files -norecurse [file join $proj_dir stereo_cam_hw.gen sources_1 bd system hdl system_wrapper.v]
set_property top system_wrapper [current_fileset]

add_files -fileset constrs_1 -norecurse [file join $repo_root hw constraints ethernet.xdc]
add_files -fileset constrs_1 -norecurse [file join $repo_root hw constraints camera.xdc]

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
