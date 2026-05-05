###############################################################################
## pluto_rf.xdc — PlutoSDR RF OFDM+LDPC design constraints
## Device: xc7z010clg225-1
## Source: ADI system_constr.xdc + PS7 DDR/MIO from ADI reference
###############################################################################

# ── AD9363 RX interface ───────────────────────────────────────────────────────
set_property -dict {PACKAGE_PIN L12 IOSTANDARD LVCMOS18} [get_ports rx_clk_in_0]
set_property -dict {PACKAGE_PIN N13 IOSTANDARD LVCMOS18} [get_ports rx_frame_in_0]
set_property -dict {PACKAGE_PIN H14 IOSTANDARD LVCMOS18} [get_ports {rx_data_in_0[0]}]
set_property -dict {PACKAGE_PIN J13 IOSTANDARD LVCMOS18} [get_ports {rx_data_in_0[1]}]
set_property -dict {PACKAGE_PIN G14 IOSTANDARD LVCMOS18} [get_ports {rx_data_in_0[2]}]
set_property -dict {PACKAGE_PIN H13 IOSTANDARD LVCMOS18} [get_ports {rx_data_in_0[3]}]
set_property -dict {PACKAGE_PIN G12 IOSTANDARD LVCMOS18} [get_ports {rx_data_in_0[4]}]
set_property -dict {PACKAGE_PIN H12 IOSTANDARD LVCMOS18} [get_ports {rx_data_in_0[5]}]
set_property -dict {PACKAGE_PIN G11 IOSTANDARD LVCMOS18} [get_ports {rx_data_in_0[6]}]
set_property -dict {PACKAGE_PIN J14 IOSTANDARD LVCMOS18} [get_ports {rx_data_in_0[7]}]
set_property -dict {PACKAGE_PIN J15 IOSTANDARD LVCMOS18} [get_ports {rx_data_in_0[8]}]
set_property -dict {PACKAGE_PIN K15 IOSTANDARD LVCMOS18} [get_ports {rx_data_in_0[9]}]
set_property -dict {PACKAGE_PIN H11 IOSTANDARD LVCMOS18} [get_ports {rx_data_in_0[10]}]
set_property -dict {PACKAGE_PIN J11 IOSTANDARD LVCMOS18} [get_ports {rx_data_in_0[11]}]

# ── AD9363 TX interface ───────────────────────────────────────────────────────
set_property -dict {PACKAGE_PIN P10 IOSTANDARD LVCMOS18} [get_ports tx_clk_out_0]
set_property -dict {PACKAGE_PIN L14 IOSTANDARD LVCMOS18} [get_ports tx_frame_out_0]
set_property -dict {PACKAGE_PIN P15 IOSTANDARD LVCMOS18} [get_ports {tx_data_out_0[0]}]
set_property -dict {PACKAGE_PIN R13 IOSTANDARD LVCMOS18} [get_ports {tx_data_out_0[1]}]
set_property -dict {PACKAGE_PIN R15 IOSTANDARD LVCMOS18} [get_ports {tx_data_out_0[2]}]
set_property -dict {PACKAGE_PIN P11 IOSTANDARD LVCMOS18} [get_ports {tx_data_out_0[3]}]
set_property -dict {PACKAGE_PIN R11 IOSTANDARD LVCMOS18} [get_ports {tx_data_out_0[4]}]
set_property -dict {PACKAGE_PIN R12 IOSTANDARD LVCMOS18} [get_ports {tx_data_out_0[5]}]
set_property -dict {PACKAGE_PIN P14 IOSTANDARD LVCMOS18} [get_ports {tx_data_out_0[6]}]
set_property -dict {PACKAGE_PIN P13 IOSTANDARD LVCMOS18} [get_ports {tx_data_out_0[7]}]
set_property -dict {PACKAGE_PIN N9  IOSTANDARD LVCMOS18} [get_ports {tx_data_out_0[8]}]
set_property -dict {PACKAGE_PIN M9  IOSTANDARD LVCMOS18} [get_ports {tx_data_out_0[9]}]
set_property -dict {PACKAGE_PIN R8  IOSTANDARD LVCMOS18} [get_ports {tx_data_out_0[10]}]
set_property -dict {PACKAGE_PIN R7  IOSTANDARD LVCMOS18} [get_ports {tx_data_out_0[11]}]

# ── AD9363 control ────────────────────────────────────────────────────────────
set_property -dict {PACKAGE_PIN P9  IOSTANDARD LVCMOS18} [get_ports gpio_resetb_0]
set_property -dict {PACKAGE_PIN K12 IOSTANDARD LVCMOS18} [get_ports enable_0]
set_property -dict {PACKAGE_PIN K11 IOSTANDARD LVCMOS18} [get_ports txnrx_0]
set_property -dict {PACKAGE_PIN L13 IOSTANDARD LVCMOS18} [get_ports gpio_en_agc_0]

# ── AD9363 SPI passthrough (PS7 SPI0 → EMIO → AD9363) ───────────────────────
set_property -dict {PACKAGE_PIN E11 IOSTANDARD LVCMOS18} [get_ports spi_clk_0]
set_property -dict {PACKAGE_PIN E13 IOSTANDARD LVCMOS18} [get_ports spi_mosi_0]
set_property -dict {PACKAGE_PIN F12 IOSTANDARD LVCMOS18} [get_ports spi_miso_0]
set_property -dict {PACKAGE_PIN E12 IOSTANDARD LVCMOS18 PULLTYPE PULLUP} [get_ports spi_csn_0]
create_clock -name spi0_clk -period 40 [get_pins -hier */EMIOSPI0SCLKO]
set_clock_groups -asynchronous \
    -group [get_clocks spi0_clk] \
    -group [get_clocks clk_fpga_0]

# ── Clocking constraints ──────────────────────────────────────────────────────
# AD9363 data clock (async to FCLK)
create_clock -name rx_clk -period 16.276 [get_ports rx_clk_in_0]

# PS7 FCLK_CLK0 (100 MHz) — defined by PS7 block
create_clock -name clk_fpga_0 -period 10.000 \
    [get_pins {pluto_rf_bd_i/processing_system7_0/inst/PS7_i/FCLKCLK[0]}]

# AD9363 data clock and FCLK are asynchronous — handled by xpm_fifo_async
set_clock_groups -asynchronous \
    -group [get_clocks rx_clk] \
    -group [get_clocks clk_fpga_0]

# tx_clk_out is derived from rx_clk via ODDR
create_generated_clock -name tx_clk \
    -source [get_ports rx_clk_in_0] \
    -divide_by 1 \
    [get_ports tx_clk_out_0]

# False path for AD9363 control outputs (static signals)
set_false_path -to [get_ports {enable_0 txnrx_0 gpio_resetb_0 gpio_en_agc_0}]

# ── Global config ─────────────────────────────────────────────────────────────
set_property CFGBVS        VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3  [current_design]
