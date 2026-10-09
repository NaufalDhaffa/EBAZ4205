# EBAZ4205 IP101GA Ethernet PHY <-> Zynq PL (EMIO MII) pin constraints.
# Pin numbers supplied by board owner; cross-checked as plausible against
# the board schematic (U14/U15 are MRCC-capable pins, consistent with being
# used as external MII clock inputs). See ../../docs/BOARD_CONFIG.md.

set_property IOSTANDARD LVCMOS33 [get_ports {eth_rx_clk}]
set_property IOSTANDARD LVCMOS33 [get_ports {eth_rxd[*]}]
set_property IOSTANDARD LVCMOS33 [get_ports {eth_rx_dv}]
set_property IOSTANDARD LVCMOS33 [get_ports {eth_tx_clk}]
set_property IOSTANDARD LVCMOS33 [get_ports {eth_tx_en}]
set_property IOSTANDARD LVCMOS33 [get_ports {eth_txd[*]}]

set_property PACKAGE_PIN U14 [get_ports {eth_rx_clk}]
set_property PACKAGE_PIN Y16 [get_ports {eth_rxd[0]}]
set_property PACKAGE_PIN V16 [get_ports {eth_rxd[1]}]
set_property PACKAGE_PIN V17 [get_ports {eth_rxd[2]}]
set_property PACKAGE_PIN Y17 [get_ports {eth_rxd[3]}]
set_property PACKAGE_PIN W16 [get_ports {eth_rx_dv}]

set_property PACKAGE_PIN U15 [get_ports {eth_tx_clk}]
set_property PACKAGE_PIN W19 [get_ports {eth_tx_en}]
set_property PACKAGE_PIN W18 [get_ports {eth_txd[0]}]
set_property PACKAGE_PIN Y18 [get_ports {eth_txd[1]}]
set_property PACKAGE_PIN V18 [get_ports {eth_txd[2]}]
set_property PACKAGE_PIN Y19 [get_ports {eth_txd[3]}]

# MDIO management interface (IP101GA register access, needed to bring up
# link speed/negotiation). Externalized interface port is "eth_mdio",
# which Vivado splits into eth_mdio_mdc / eth_mdio_mdio_io.
set_property -dict {PACKAGE_PIN W15 IOSTANDARD LVCMOS33} [get_ports {eth_mdio_mdc}]
set_property -dict {PACKAGE_PIN Y14 IOSTANDARD LVCMOS33} [get_ports {eth_mdio_mdio_io}]

create_clock -name eth_rx_clk -period 40.0 -waveform {0 20.0} [get_ports {eth_rx_clk}]
create_clock -name eth_tx_clk -period 40.0 -waveform {0 20.0} [get_ports {eth_tx_clk}]
set_clock_groups -asynchronous -group [get_clocks eth_rx_clk] -group [get_clocks eth_tx_clk]

# Board LEDs (PS7 EMIO GPIO[1:0], bus port "led[1:0]" in the block design),
# from xjtuecho/EBAZ4205 template .xdc. led[0]=green(W13), led[1]=red(W14).
set_property -dict {PACKAGE_PIN W13 IOSTANDARD LVCMOS33} [get_ports {led[0]}]
set_property -dict {PACKAGE_PIN W14 IOSTANDARD LVCMOS33} [get_ports {led[1]}]
