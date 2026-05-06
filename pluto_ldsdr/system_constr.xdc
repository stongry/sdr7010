###############################################################################
## system_constr.xdc — pluto_ldsdr LVDS pinout
## All AD9363 IQ pins are LVDS_25 (LDSDR rev2.1 hardware)
###############################################################################

# ── AD9363 LVDS RX ──────────────────────────────────────────────────────────
set_property -dict {PACKAGE_PIN N20 IOSTANDARD LVDS_25 DIFF_TERM TRUE} [get_ports rx_clk_in_p]
set_property -dict {PACKAGE_PIN P20 IOSTANDARD LVDS_25 DIFF_TERM TRUE} [get_ports rx_clk_in_n]
set_property -dict {PACKAGE_PIN Y16 IOSTANDARD LVDS_25 DIFF_TERM TRUE} [get_ports rx_frame_in_p]
set_property -dict {PACKAGE_PIN Y17 IOSTANDARD LVDS_25 DIFF_TERM TRUE} [get_ports rx_frame_in_n]
set_property -dict {PACKAGE_PIN Y18 IOSTANDARD LVDS_25 DIFF_TERM TRUE} [get_ports rx_data_in_p[0]]
set_property -dict {PACKAGE_PIN Y19 IOSTANDARD LVDS_25 DIFF_TERM TRUE} [get_ports rx_data_in_n[0]]
set_property -dict {PACKAGE_PIN V17 IOSTANDARD LVDS_25 DIFF_TERM TRUE} [get_ports rx_data_in_p[1]]
set_property -dict {PACKAGE_PIN V18 IOSTANDARD LVDS_25 DIFF_TERM TRUE} [get_ports rx_data_in_n[1]]
set_property -dict {PACKAGE_PIN W18 IOSTANDARD LVDS_25 DIFF_TERM TRUE} [get_ports rx_data_in_p[2]]
set_property -dict {PACKAGE_PIN W19 IOSTANDARD LVDS_25 DIFF_TERM TRUE} [get_ports rx_data_in_n[2]]
set_property -dict {PACKAGE_PIN R16 IOSTANDARD LVDS_25 DIFF_TERM TRUE} [get_ports rx_data_in_p[3]]
set_property -dict {PACKAGE_PIN R17 IOSTANDARD LVDS_25 DIFF_TERM TRUE} [get_ports rx_data_in_n[3]]
set_property -dict {PACKAGE_PIN V20 IOSTANDARD LVDS_25 DIFF_TERM TRUE} [get_ports rx_data_in_p[4]]
set_property -dict {PACKAGE_PIN W20 IOSTANDARD LVDS_25 DIFF_TERM TRUE} [get_ports rx_data_in_n[4]]
set_property -dict {PACKAGE_PIN W14 IOSTANDARD LVDS_25 DIFF_TERM TRUE} [get_ports rx_data_in_p[5]]
set_property -dict {PACKAGE_PIN Y14 IOSTANDARD LVDS_25 DIFF_TERM TRUE} [get_ports rx_data_in_n[5]]

# ── AD9363 LVDS TX ──────────────────────────────────────────────────────────
set_property -dict {PACKAGE_PIN N18 IOSTANDARD LVDS_25} [get_ports tx_clk_out_p]
set_property -dict {PACKAGE_PIN P19 IOSTANDARD LVDS_25} [get_ports tx_clk_out_n]
set_property -dict {PACKAGE_PIN V16 IOSTANDARD LVDS_25} [get_ports tx_frame_out_p]
set_property -dict {PACKAGE_PIN W16 IOSTANDARD LVDS_25} [get_ports tx_frame_out_n]
set_property -dict {PACKAGE_PIN T16 IOSTANDARD LVDS_25} [get_ports tx_data_out_p[0]]
set_property -dict {PACKAGE_PIN U17 IOSTANDARD LVDS_25} [get_ports tx_data_out_n[0]]
set_property -dict {PACKAGE_PIN U18 IOSTANDARD LVDS_25} [get_ports tx_data_out_p[1]]
set_property -dict {PACKAGE_PIN U19 IOSTANDARD LVDS_25} [get_ports tx_data_out_n[1]]
set_property -dict {PACKAGE_PIN U14 IOSTANDARD LVDS_25} [get_ports tx_data_out_p[2]]
set_property -dict {PACKAGE_PIN U15 IOSTANDARD LVDS_25} [get_ports tx_data_out_n[2]]
set_property -dict {PACKAGE_PIN V12 IOSTANDARD LVDS_25} [get_ports tx_data_out_p[3]]
set_property -dict {PACKAGE_PIN W13 IOSTANDARD LVDS_25} [get_ports tx_data_out_n[3]]
set_property -dict {PACKAGE_PIN T12 IOSTANDARD LVDS_25} [get_ports tx_data_out_p[4]]
set_property -dict {PACKAGE_PIN U12 IOSTANDARD LVDS_25} [get_ports tx_data_out_n[4]]
set_property -dict {PACKAGE_PIN V15 IOSTANDARD LVDS_25} [get_ports tx_data_out_p[5]]
set_property -dict {PACKAGE_PIN W15 IOSTANDARD LVDS_25} [get_ports tx_data_out_n[5]]

# ── AD9363 control (LVCMOS25) ──────────────────────────────────────────────
set_property -dict {PACKAGE_PIN P16 IOSTANDARD LVCMOS25} [get_ports en_agc]
set_property -dict {PACKAGE_PIN T17 IOSTANDARD LVCMOS25} [get_ports resetb]
set_property -dict {PACKAGE_PIN R18 IOSTANDARD LVCMOS25} [get_ports enable]
set_property -dict {PACKAGE_PIN N17 IOSTANDARD LVCMOS25} [get_ports txnrx]

# ── SPI ────────────────────────────────────────────────────────────────────
set_property -dict {PACKAGE_PIN T20 IOSTANDARD LVCMOS25 PULLTYPE PULLUP} [get_ports spi_csn]
set_property -dict {PACKAGE_PIN R19 IOSTANDARD LVCMOS25} [get_ports spi_clk]
set_property -dict {PACKAGE_PIN P18 IOSTANDARD LVCMOS25} [get_ports spi_mosi]
set_property -dict {PACKAGE_PIN T19 IOSTANDARD LVCMOS25} [get_ports spi_miso]

# ── Clocks ─────────────────────────────────────────────────────────────────
# LVDS RX clock from AD9363: ~245.76 MHz nominal (4.069 ns)
create_clock -name rx_clk -period 4.069 [get_ports rx_clk_in_p]

create_clock -name clk_fpga_0 -period 10 [get_pins "i_system_wrapper/system_i/sys_ps7/inst/PS7_i/FCLKCLK[0]"]
create_clock -name clk_fpga_1 -period  5 [get_pins "i_system_wrapper/system_i/sys_ps7/inst/PS7_i/FCLKCLK[1]"]
create_clock -name spi0_clk   -period 40 [get_pins -hier */EMIOSPI0SCLKO]

set_input_jitter clk_fpga_0 0.3
set_input_jitter clk_fpga_1 0.15

set_false_path -from [get_pins {i_system_wrapper/system_i/axi_ad9361/inst/i_rx/i_up_adc_common/up_adc_gpio_out_int_reg[0]/C}]
set_false_path -from [get_pins {i_system_wrapper/system_i/axi_ad9361/inst/i_tx/i_up_dac_common/up_dac_gpio_out_int_reg[0]/C}]
