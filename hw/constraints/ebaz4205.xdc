## General .xdc for the EBAZ4205 (XC7Z010CLG400). Reference only: not added
## to the Vivado project by hw/scripts/build_bd.tcl.
## To use a pin: uncomment its line and rename the port (after get_ports) to
## the top-level signal name. Ethernet pins are already active in ethernet.xdc;
## do not enable them twice.

##Clock signal
#set_property -dict { PACKAGE_PIN N18   IOSTANDARD LVCMOS33 } [get_ports { clk }]; # Use if you have X5 Oscillator soldered on
#create_clock -add -name clk_pin -period 10.00 -waveform {0 5} [get_ports { clk }];


##Ethernet (IP101GA PHY, EMIO MII; already active in ethernet.xdc)
#set_property IOSTANDARD LVCMOS33 [get_ports {eth_rx_clk}]
#set_property IOSTANDARD LVCMOS33 [get_ports {eth_rxd[*]}]
#set_property IOSTANDARD LVCMOS33 [get_ports {eth_rx_dv}]
#set_property IOSTANDARD LVCMOS33 [get_ports {eth_tx_clk}]
#set_property IOSTANDARD LVCMOS33 [get_ports {eth_tx_en}]
#set_property IOSTANDARD LVCMOS33 [get_ports {eth_txd[*]}]

#set_property PACKAGE_PIN U14 [get_ports {eth_rx_clk}]
#set_property PACKAGE_PIN Y16 [get_ports {eth_rxd[0]}]
#set_property PACKAGE_PIN V16 [get_ports {eth_rxd[1]}]
#set_property PACKAGE_PIN V17 [get_ports {eth_rxd[2]}]
#set_property PACKAGE_PIN Y17 [get_ports {eth_rxd[3]}]
#set_property PACKAGE_PIN W16 [get_ports {eth_rx_dv}]

#set_property PACKAGE_PIN U15 [get_ports {eth_tx_clk}]
#set_property PACKAGE_PIN W19 [get_ports {eth_tx_en}]
#set_property PACKAGE_PIN W18 [get_ports {eth_txd[0]}]
#set_property PACKAGE_PIN Y18 [get_ports {eth_txd[1]}]
#set_property PACKAGE_PIN V18 [get_ports {eth_txd[2]}]
#set_property PACKAGE_PIN Y19 [get_ports {eth_txd[3]}]

# MDIO (Vivado splits the eth_mdio interface into eth_mdio_mdc / eth_mdio_mdio_io)
#set_property -dict {PACKAGE_PIN W15 IOSTANDARD LVCMOS33} [get_ports {eth_mdio_mdc}]
#set_property -dict {PACKAGE_PIN Y14 IOSTANDARD LVCMOS33} [get_ports {eth_mdio_mdio_io}]

# U14/U15 are MRCC-capable (external MII clock inputs, 25MHz at 100Mbps)
#create_clock -name eth_rx_clk -period 40.0 -waveform {0 20.0} [get_ports {eth_rx_clk}]
#create_clock -name eth_tx_clk -period 40.0 -waveform {0 20.0} [get_ports {eth_tx_clk}]
#set_clock_groups -asynchronous -group [get_clocks eth_rx_clk] -group [get_clocks eth_tx_clk]


##DATA1
#set_property -dict { PACKAGE_PIN A20   IOSTANDARD LVCMOS33 } [get_ports { DATA1_5 }];
#set_property -dict { PACKAGE_PIN H16   IOSTANDARD LVCMOS33 } [get_ports { DATA1_6 }];
#set_property -dict { PACKAGE_PIN B19   IOSTANDARD LVCMOS33 } [get_ports { DATA1_7 }];
#set_property -dict { PACKAGE_PIN B20   IOSTANDARD LVCMOS33 } [get_ports { DATA1_8 }];
#set_property -dict { PACKAGE_PIN C20   IOSTANDARD LVCMOS33 } [get_ports { DATA1_9 }];
#set_property -dict { PACKAGE_PIN H17   IOSTANDARD LVCMOS33 } [get_ports { DATA1_11 }];
#set_property -dict { PACKAGE_PIN D20   IOSTANDARD LVCMOS33 } [get_ports { DATA1_13 }];
#set_property -dict { PACKAGE_PIN D18   IOSTANDARD LVCMOS33 } [get_ports { DATA1_14 }];
#set_property -dict { PACKAGE_PIN H18   IOSTANDARD LVCMOS33 } [get_ports { DATA1_15 }];
#set_property -dict { PACKAGE_PIN D19   IOSTANDARD LVCMOS33 } [get_ports { DATA1_16 }];
#set_property -dict { PACKAGE_PIN F20   IOSTANDARD LVCMOS33 } [get_ports { DATA1_17 }];
#set_property -dict { PACKAGE_PIN E19   IOSTANDARD LVCMOS33 } [get_ports { DATA1_18 }];
#set_property -dict { PACKAGE_PIN F19   IOSTANDARD LVCMOS33 } [get_ports { DATA1_19 }];
#set_property -dict { PACKAGE_PIN K17   IOSTANDARD LVCMOS33 } [get_ports { DATA1_20 }];


##DATA2
#set_property -dict { PACKAGE_PIN G20   IOSTANDARD LVCMOS33 } [get_ports { DATA2_5 }];
#set_property -dict { PACKAGE_PIN J18   IOSTANDARD LVCMOS33 } [get_ports { DATA2_6 }];
#set_property -dict { PACKAGE_PIN G19   IOSTANDARD LVCMOS33 } [get_ports { DATA2_7 }];
#set_property -dict { PACKAGE_PIN H20   IOSTANDARD LVCMOS33 } [get_ports { DATA2_8 }];
#set_property -dict { PACKAGE_PIN J19   IOSTANDARD LVCMOS33 } [get_ports { DATA2_9 }];
#set_property -dict { PACKAGE_PIN K18   IOSTANDARD LVCMOS33 } [get_ports { DATA2_11 }];
#set_property -dict { PACKAGE_PIN K19   IOSTANDARD LVCMOS33 } [get_ports { DATA2_13 }];
#set_property -dict { PACKAGE_PIN J20   IOSTANDARD LVCMOS33 } [get_ports { DATA2_14 }];
#set_property -dict { PACKAGE_PIN L16   IOSTANDARD LVCMOS33 } [get_ports { DATA2_15 }];
#set_property -dict { PACKAGE_PIN L19   IOSTANDARD LVCMOS33 } [get_ports { DATA2_16 }];
#set_property -dict { PACKAGE_PIN M18   IOSTANDARD LVCMOS33 } [get_ports { DATA2_17 }];
#set_property -dict { PACKAGE_PIN L20   IOSTANDARD LVCMOS33 } [get_ports { DATA2_18 }];
#set_property -dict { PACKAGE_PIN M20   IOSTANDARD LVCMOS33 } [get_ports { DATA2_19 }];
#set_property -dict { PACKAGE_PIN L17   IOSTANDARD LVCMOS33 } [get_ports { DATA2_20 }];


##DATA3
#set_property -dict { PACKAGE_PIN M19   IOSTANDARD LVCMOS33 } [get_ports { DATA3_5 }];
#set_property -dict { PACKAGE_PIN N20   IOSTANDARD LVCMOS33 } [get_ports { DATA3_6 }];
#set_property -dict { PACKAGE_PIN P18   IOSTANDARD LVCMOS33 } [get_ports { DATA3_7 }];
#set_property -dict { PACKAGE_PIN M17   IOSTANDARD LVCMOS33 } [get_ports { DATA3_8 }];
#set_property -dict { PACKAGE_PIN N17   IOSTANDARD LVCMOS33 } [get_ports { DATA3_9 }];
#set_property -dict { PACKAGE_PIN P20   IOSTANDARD LVCMOS33 } [get_ports { DATA3_11 }];
#set_property -dict { PACKAGE_PIN R18   IOSTANDARD LVCMOS33 } [get_ports { DATA3_13 }];
#set_property -dict { PACKAGE_PIN R19   IOSTANDARD LVCMOS33 } [get_ports { DATA3_14 }];
#set_property -dict { PACKAGE_PIN P19   IOSTANDARD LVCMOS33 } [get_ports { DATA3_15 }];
#set_property -dict { PACKAGE_PIN T20   IOSTANDARD LVCMOS33 } [get_ports { DATA3_16 }];
#set_property -dict { PACKAGE_PIN U20   IOSTANDARD LVCMOS33 } [get_ports { DATA3_17 }];
#set_property -dict { PACKAGE_PIN T19   IOSTANDARD LVCMOS33 } [get_ports { DATA3_18 }];
#set_property -dict { PACKAGE_PIN V20   IOSTANDARD LVCMOS33 } [get_ports { DATA3_19 }];
#set_property -dict { PACKAGE_PIN U19   IOSTANDARD LVCMOS33 } [get_ports { DATA3_20 }];


##LEDS
#set_property -dict { PACKAGE_PIN W13   IOSTANDARD LVCMOS33 } [get_ports { greenLED }];
#set_property -dict { PACKAGE_PIN W14   IOSTANDARD LVCMOS33 } [get_ports { redLED }];


##J5&J3
#set_property -dict { PACKAGE_PIN V15   IOSTANDARD LVCMOS33 } [get_ports { J5_SPEED }];
#set_property -dict { PACKAGE_PIN V12   IOSTANDARD LVCMOS33 } [get_ports { J5_PWM }];
#set_property -dict { PACKAGE_PIN V13   IOSTANDARD LVCMOS33 } [get_ports { J3_SPEED }];
#set_property -dict { PACKAGE_PIN U12   IOSTANDARD LVCMOS33 } [get_ports { J3_PWM }];
