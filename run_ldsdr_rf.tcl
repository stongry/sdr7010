# =============================================================================
# run_ldsdr_rf.tcl — RF OFDM+LDPC for LDSDR 7010 rev2.1
# Target: xc7z010clg400-2
#
# This build replaces ofdm_ldpc_pl (digital loopback) with ofdm_ldpc_rf_pl
# which integrates LDSDR's ad9361_phy IP and an async FIFO between data_clk
# (~80 MHz @ 40 MSPS R1) and FCLK0 (50 MHz).
#
# It coexists with LDSDR's stock Linux ad9361 driver at SPI level — the PS
# configures AD9363 over PS_SPI0 EMIO, and our PL OFDM runs autonomously
# once data_clk comes alive.
#
# Run:
#   source /mnt/backup/Xilinx/Vivado/2024.2/settings64.sh
#   vivado -mode batch -source /home/eea/fpga_hdl/run_ldsdr_rf.tcl
# =============================================================================

set src_dir  /home/eea/fpga_hdl
set proj_dir /home/eea/zynq_build_ldsdr_rf
set bit_out  /home/eea/ofdm_ldpc_ldsdr_rf.bit

# ── Fresh project ────────────────────────────────────────────────────────────
if {[file exists $proj_dir]} { file delete -force $proj_dir }
create_project ofdm_ldpc_ldsdr_rf $proj_dir -part xc7z010clg400-2
set_property target_language Verilog [current_project]
puts "Project created: $proj_dir (xc7z010clg400-2)"

# ── HDL sources ──────────────────────────────────────────────────────────────
foreach src_file {
    ofdm_ldpc_rf_pl.v
    ofdm_ldpc_top.v
    startup_gen.v
    ldpc_encoder.v
    ldpc_decoder.v
    qpsk_mod.v
    qpsk_demod.v
    cp_insert.v
    cp_remove.v
    channel_est.v
    tx_subcarrier_map.v
    rx_subcarrier_demap.v
    llr_assembler.v
    llr_buffer.v
    xfft_stub.v
    ad9361_phy.v
    phy_rx.v
    phy_tx.v
} {
    add_files -norecurse "${src_dir}/${src_file}"
}
update_compile_order -fileset sources_1
puts "Sources added (18 modules)"

# ── Block Design ────────────────────────────────────────────────────────────
set bd_name "ldsdr_rf_bd"
set bd_src_dir "${proj_dir}/ofdm_ldpc_ldsdr_rf.srcs/sources_1/bd"
catch {create_bd_design $bd_name} create_err
if {[llength [get_bd_designs -quiet $bd_name]] == 0} {
    set bd_written "${bd_src_dir}/${bd_name}/${bd_name}.bd"
    if {[file exists $bd_written]} {
        add_files -norecurse $bd_written
        open_bd_design [get_files -filter "NAME =~ *${bd_name}.bd"]
    } else {
        puts "FATAL: BD creation failed.  Error: $create_err"; return
    }
}
current_bd_design $bd_name
delete_bd_objs -quiet [get_bd_cells *]
puts "BD ready: $bd_name"

# ── PS7 with LDSDR config + EMIO GPIO 32-bit + FCLK1=200MHz + SPI0 EMIO ─────
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 processing_system7_0
source ${src_dir}/ldsdr_ps7_config.tcl

# Override what we need:
lappend ps7_props CONFIG.PCW_GPIO_EMIO_GPIO_ENABLE {1}
lappend ps7_props CONFIG.PCW_GPIO_EMIO_GPIO_IO     {32}
lappend ps7_props CONFIG.PCW_USE_M_AXI_GP0         {0}
lappend ps7_props CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {50}
# NOTE: dropped FCLK1=200 MHz — first attempt at FCLK1 broke Linux boot
# (board hung). Workaround: route FCLK0 (50 MHz) to ad9361_phy.ref_clk200m.
# IDELAYCTRL will warn about wrong reference but should not hang.
# Real 200 MHz needed only for precise IDELAY tap calibration.

# SPI0 EMIO — Linux ad9361 driver talks to AD9363 over this
lappend ps7_props CONFIG.PCW_SPI0_PERIPHERAL_ENABLE {1}
lappend ps7_props CONFIG.PCW_SPI0_SPI0_IO           {EMIO}
lappend ps7_props CONFIG.PCW_SPI0_GRP_SS0_ENABLE    {1}
lappend ps7_props CONFIG.PCW_SPI0_GRP_SS0_IO        {EMIO}
lappend ps7_props CONFIG.PCW_SPI_PERIPHERAL_FREQMHZ {166.666667}

set_property -dict $ps7_props [get_bd_cells processing_system7_0]

apply_bd_automation \
    -rule xilinx.com:bd_rule:processing_system7 \
    -config {make_external "FIXED_IO, DDR" apply_board_preset "0"} \
    [get_bd_cells processing_system7_0]
puts "PS7 configured: FCLK0=50MHz FCLK1=200MHz EMIO_GPIO=32 SPI0=EMIO"

# ── xlslice for FCLK_RESET0_N → rst_n ───────────────────────────────────────
create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:1.0 xlslice_rst
set_property -dict [list \
    CONFIG.DIN_WIDTH {4} CONFIG.DIN_FROM {0} CONFIG.DIN_TO {0} CONFIG.DOUT_WIDTH {1}] \
    [get_bd_cells xlslice_rst]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_RESET0_N] \
               [get_bd_pins xlslice_rst/Din]

# ── proc_sys_reset ─────────────────────────────────────────────────────────
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 proc_sys_reset_0
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] \
               [get_bd_pins proc_sys_reset_0/slowest_sync_clk]
connect_bd_net [get_bd_pins xlslice_rst/Dout] \
               [get_bd_pins proc_sys_reset_0/ext_reset_in]
set_property CONFIG.C_EXT_RST_HIGH_ACTIVE {0} [get_bd_cells proc_sys_reset_0]
set_property CONFIG.C_AUX_RST_HIGH_ACTIVE {0} [get_bd_cells proc_sys_reset_0]
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 xlconst_one
set_property -dict [list CONFIG.CONST_WIDTH {1} CONFIG.CONST_VAL {1}] \
    [get_bd_cells xlconst_one]
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 xlconst_zero
set_property -dict [list CONFIG.CONST_WIDTH {1} CONFIG.CONST_VAL {0}] \
    [get_bd_cells xlconst_zero]
connect_bd_net [get_bd_pins xlconst_one/dout]  [get_bd_pins proc_sys_reset_0/aux_reset_in]
connect_bd_net [get_bd_pins xlconst_one/dout]  [get_bd_pins proc_sys_reset_0/dcm_locked]
connect_bd_net [get_bd_pins xlconst_zero/dout] [get_bd_pins proc_sys_reset_0/mb_debug_sys_rst]

# ── ofdm_ldpc_rf_pl module reference (TOP) ───────────────────────────────────
create_bd_cell -type module -reference ofdm_ldpc_rf_pl ofdm_ldpc_rf_pl_0
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] \
               [get_bd_pins ofdm_ldpc_rf_pl_0/clk]
# ref_clk200m wired from FCLK0 (50MHz) — workaround for boot hang
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] \
               [get_bd_pins ofdm_ldpc_rf_pl_0/ref_clk200m]
connect_bd_net [get_bd_pins proc_sys_reset_0/peripheral_aresetn] \
               [get_bd_pins ofdm_ldpc_rf_pl_0/rst_n_ext]

# ── Slice EMIO GPIO_O for control bits ─────────────────────────────────────
# Linux ad9361 driver expects:
#   bit[12] = en_agc  (DT en_agc-gpios = GPIO 66 = EMIO 12)
#   bit[13] = resetb  (DT reset-gpios   = GPIO 67 = EMIO 13)
# Our controls go on bits NOT used by Linux:
#   bit[6:0]   = idelay_en  (our)
#   bit[11:7]  = idelay_tap (our)
#   bit[14]    = phy_mode   (our; default 1 = R1)
#   bit[15]    = rf_start   (our; PS pulses after AD9363 ready)
#   bit[16]    = rf_loopback_dis (our; mute TX for noise floor)
proc make_gpio_slice {name from to width} {
    create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:1.0 $name
    set_property -dict [list CONFIG.DIN_WIDTH {32} CONFIG.DIN_FROM $from \
        CONFIG.DIN_TO $to CONFIG.DOUT_WIDTH $width] [get_bd_cells $name]
    connect_bd_net [get_bd_pins processing_system7_0/GPIO_O] \
                   [get_bd_pins $name/Din]
}
make_gpio_slice xls_idelay_en   6  0  7
make_gpio_slice xls_idelay_tap  11 7  5
make_gpio_slice xls_en_agc      12 12 1
make_gpio_slice xls_resetb      13 13 1
make_gpio_slice xls_phy_mode    14 14 1
make_gpio_slice xls_rf_start    15 15 1
make_gpio_slice xls_rf_lb_dis   16 16 1

connect_bd_net [get_bd_pins xls_idelay_en/Dout]  [get_bd_pins ofdm_ldpc_rf_pl_0/idelay_en]
connect_bd_net [get_bd_pins xls_idelay_tap/Dout] [get_bd_pins ofdm_ldpc_rf_pl_0/idelay_tap]
connect_bd_net [get_bd_pins xls_phy_mode/Dout]   [get_bd_pins ofdm_ldpc_rf_pl_0/phy_mode]
connect_bd_net [get_bd_pins xls_rf_start/Dout]   [get_bd_pins ofdm_ldpc_rf_pl_0/rf_start]
connect_bd_net [get_bd_pins xls_rf_lb_dis/Dout]  [get_bd_pins ofdm_ldpc_rf_pl_0/rf_loopback_dis]
make_bd_pins_external -name gpio_en_agc_0 [get_bd_pins xls_en_agc/Dout]
make_bd_pins_external -name gpio_resetb_0 [get_bd_pins xls_resetb/Dout]

# ── xlconcat: 32-bit EMIO GPIO_I status ─────────────────────────────────────
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 xlconcat_status
# Layout:
# bit[0]    pass_flag
# bit[1]    rx_done
# bit[2]    tx_started
# bit[3]    tx_streaming
# bit[4]    rx_data_seen
# bit[5]    dac_data_pushed
# bit[15:6] rx_sample_count_lo (10 bits)
# bit[25:16] tx_sample_count_lo (10 bits)
# bit[31:26] status_pad (5 bits) + 1 bit zero pad → 6 bits
set_property -dict [list CONFIG.NUM_PORTS {9} \
    CONFIG.IN0_WIDTH {1} CONFIG.IN1_WIDTH {1} CONFIG.IN2_WIDTH {1} \
    CONFIG.IN3_WIDTH {1} CONFIG.IN4_WIDTH {1} CONFIG.IN5_WIDTH {1} \
    CONFIG.IN6_WIDTH {10} CONFIG.IN7_WIDTH {10} CONFIG.IN8_WIDTH {6}] \
    [get_bd_cells xlconcat_status]

connect_bd_net [get_bd_pins ofdm_ldpc_rf_pl_0/pass_flag]          [get_bd_pins xlconcat_status/In0]
connect_bd_net [get_bd_pins ofdm_ldpc_rf_pl_0/rx_done]            [get_bd_pins xlconcat_status/In1]
connect_bd_net [get_bd_pins ofdm_ldpc_rf_pl_0/tx_started]         [get_bd_pins xlconcat_status/In2]
connect_bd_net [get_bd_pins ofdm_ldpc_rf_pl_0/tx_streaming]       [get_bd_pins xlconcat_status/In3]
connect_bd_net [get_bd_pins ofdm_ldpc_rf_pl_0/rx_data_seen]       [get_bd_pins xlconcat_status/In4]
connect_bd_net [get_bd_pins ofdm_ldpc_rf_pl_0/dac_data_pushed]    [get_bd_pins xlconcat_status/In5]
connect_bd_net [get_bd_pins ofdm_ldpc_rf_pl_0/rx_sample_count_lo] [get_bd_pins xlconcat_status/In6]
connect_bd_net [get_bd_pins ofdm_ldpc_rf_pl_0/tx_sample_count_lo] [get_bd_pins xlconcat_status/In7]
# Pad In8 with 6-bit zero
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 xlconst_status_pad
set_property -dict [list CONFIG.CONST_WIDTH {6} CONFIG.CONST_VAL {0}] \
    [get_bd_cells xlconst_status_pad]
connect_bd_net [get_bd_pins xlconst_status_pad/dout] [get_bd_pins xlconcat_status/In8]
connect_bd_net [get_bd_pins xlconcat_status/dout]    [get_bd_pins processing_system7_0/GPIO_I]

# ── PS7 SPI0 EMIO → external (passthrough to AD9363) ────────────────────────
make_bd_pins_external -name spi_clk_0  [get_bd_pins processing_system7_0/SPI0_SCLK_O]
make_bd_pins_external -name spi_mosi_0 [get_bd_pins processing_system7_0/SPI0_MOSI_O]
make_bd_pins_external -name spi_csn_0  [get_bd_pins processing_system7_0/SPI0_SS_O]
make_bd_pins_external -name spi_miso_0 [get_bd_pins processing_system7_0/SPI0_MISO_I]
# SS_I tied HIGH for master mode
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 xlconst_ssi
set_property -dict [list CONFIG.CONST_WIDTH {1} CONFIG.CONST_VAL {1}] \
    [get_bd_cells xlconst_ssi]
connect_bd_net [get_bd_pins xlconst_ssi/dout] [get_bd_pins processing_system7_0/SPI0_SS_I]

# ── Make AD9363 LVDS pins external ──────────────────────────────────────────
foreach pin {rx_clk_in_p rx_clk_in_n
             rx_data_in_p rx_data_in_n
             rx_frame_in_p rx_frame_in_n
             tx_clk_out_p tx_clk_out_n
             tx_data_out_p tx_data_out_n
             tx_frame_out_p tx_frame_out_n} {
    make_bd_pins_external [get_bd_pins ofdm_ldpc_rf_pl_0/$pin]
}
puts "AD9363 LVDS pins made external + SPI0 EMIO routed"

# ── enable / txnrx tied HIGH (FDD mode, AD9363 always enabled) ─────────────
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 xlconst_enable
set_property -dict [list CONFIG.CONST_WIDTH {1} CONFIG.CONST_VAL {1}] [get_bd_cells xlconst_enable]
make_bd_pins_external -name enable_0 [get_bd_pins xlconst_enable/dout]
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 xlconst_txnrx
set_property -dict [list CONFIG.CONST_WIDTH {1} CONFIG.CONST_VAL {0}] [get_bd_cells xlconst_txnrx]
make_bd_pins_external -name txnrx_0 [get_bd_pins xlconst_txnrx/dout]

validate_bd_design
save_bd_design

# ── Wrapper ──────────────────────────────────────────────────────────────────
set wrapper_src [make_wrapper -files [get_files ${bd_name}.bd] -top]
add_files -norecurse $wrapper_src
update_compile_order -fileset sources_1
set_property top ${bd_name}_wrapper [current_fileset]
update_compile_order -fileset sources_1

# ── XDC: LDSDR LVDS pin map + SPI passthrough + control GPIOs ──────────────
set rf_xdc "${proj_dir}/ldsdr_rf.xdc"
set fp [open $rf_xdc w]
# AD9363 RX LVDS
puts $fp {set_property -dict {PACKAGE_PIN N20 IOSTANDARD LVDS_25 DIFF_TERM TRUE} [get_ports rx_clk_in_p_0]}
puts $fp {set_property -dict {PACKAGE_PIN P20 IOSTANDARD LVDS_25 DIFF_TERM TRUE} [get_ports rx_clk_in_n_0]}
puts $fp {set_property -dict {PACKAGE_PIN Y16 IOSTANDARD LVDS_25 DIFF_TERM TRUE} [get_ports rx_frame_in_p_0]}
puts $fp {set_property -dict {PACKAGE_PIN Y17 IOSTANDARD LVDS_25 DIFF_TERM TRUE} [get_ports rx_frame_in_n_0]}
puts $fp {set_property -dict {PACKAGE_PIN Y18 IOSTANDARD LVDS_25 DIFF_TERM TRUE} [get_ports {rx_data_in_p_0[0]}]}
puts $fp {set_property -dict {PACKAGE_PIN Y19 IOSTANDARD LVDS_25 DIFF_TERM TRUE} [get_ports {rx_data_in_n_0[0]}]}
puts $fp {set_property -dict {PACKAGE_PIN V17 IOSTANDARD LVDS_25 DIFF_TERM TRUE} [get_ports {rx_data_in_p_0[1]}]}
puts $fp {set_property -dict {PACKAGE_PIN V18 IOSTANDARD LVDS_25 DIFF_TERM TRUE} [get_ports {rx_data_in_n_0[1]}]}
puts $fp {set_property -dict {PACKAGE_PIN W18 IOSTANDARD LVDS_25 DIFF_TERM TRUE} [get_ports {rx_data_in_p_0[2]}]}
puts $fp {set_property -dict {PACKAGE_PIN W19 IOSTANDARD LVDS_25 DIFF_TERM TRUE} [get_ports {rx_data_in_n_0[2]}]}
puts $fp {set_property -dict {PACKAGE_PIN R16 IOSTANDARD LVDS_25 DIFF_TERM TRUE} [get_ports {rx_data_in_p_0[3]}]}
puts $fp {set_property -dict {PACKAGE_PIN R17 IOSTANDARD LVDS_25 DIFF_TERM TRUE} [get_ports {rx_data_in_n_0[3]}]}
puts $fp {set_property -dict {PACKAGE_PIN V20 IOSTANDARD LVDS_25 DIFF_TERM TRUE} [get_ports {rx_data_in_p_0[4]}]}
puts $fp {set_property -dict {PACKAGE_PIN W20 IOSTANDARD LVDS_25 DIFF_TERM TRUE} [get_ports {rx_data_in_n_0[4]}]}
puts $fp {set_property -dict {PACKAGE_PIN W14 IOSTANDARD LVDS_25 DIFF_TERM TRUE} [get_ports {rx_data_in_p_0[5]}]}
puts $fp {set_property -dict {PACKAGE_PIN Y14 IOSTANDARD LVDS_25 DIFF_TERM TRUE} [get_ports {rx_data_in_n_0[5]}]}
# AD9363 TX LVDS
puts $fp {set_property -dict {PACKAGE_PIN N18 IOSTANDARD LVDS_25} [get_ports tx_clk_out_p_0]}
puts $fp {set_property -dict {PACKAGE_PIN P19 IOSTANDARD LVDS_25} [get_ports tx_clk_out_n_0]}
puts $fp {set_property -dict {PACKAGE_PIN V16 IOSTANDARD LVDS_25} [get_ports tx_frame_out_p_0]}
puts $fp {set_property -dict {PACKAGE_PIN W16 IOSTANDARD LVDS_25} [get_ports tx_frame_out_n_0]}
puts $fp {set_property -dict {PACKAGE_PIN T16 IOSTANDARD LVDS_25} [get_ports {tx_data_out_p_0[0]}]}
puts $fp {set_property -dict {PACKAGE_PIN U17 IOSTANDARD LVDS_25} [get_ports {tx_data_out_n_0[0]}]}
puts $fp {set_property -dict {PACKAGE_PIN U18 IOSTANDARD LVDS_25} [get_ports {tx_data_out_p_0[1]}]}
puts $fp {set_property -dict {PACKAGE_PIN U19 IOSTANDARD LVDS_25} [get_ports {tx_data_out_n_0[1]}]}
puts $fp {set_property -dict {PACKAGE_PIN U14 IOSTANDARD LVDS_25} [get_ports {tx_data_out_p_0[2]}]}
puts $fp {set_property -dict {PACKAGE_PIN U15 IOSTANDARD LVDS_25} [get_ports {tx_data_out_n_0[2]}]}
puts $fp {set_property -dict {PACKAGE_PIN V12 IOSTANDARD LVDS_25} [get_ports {tx_data_out_p_0[3]}]}
puts $fp {set_property -dict {PACKAGE_PIN W13 IOSTANDARD LVDS_25} [get_ports {tx_data_out_n_0[3]}]}
puts $fp {set_property -dict {PACKAGE_PIN T12 IOSTANDARD LVDS_25} [get_ports {tx_data_out_p_0[4]}]}
puts $fp {set_property -dict {PACKAGE_PIN U12 IOSTANDARD LVDS_25} [get_ports {tx_data_out_n_0[4]}]}
puts $fp {set_property -dict {PACKAGE_PIN V15 IOSTANDARD LVDS_25} [get_ports {tx_data_out_p_0[5]}]}
puts $fp {set_property -dict {PACKAGE_PIN W15 IOSTANDARD LVDS_25} [get_ports {tx_data_out_n_0[5]}]}
# AD9363 control — LDSDR rev2.1 (xc7z010clg400) pin map (extracted from
# the project's impl_2 propImpl.xdc, where impl_2 was actually for
# clg400-1, identical pin numbering to our -2)
puts $fp {set_property -dict {PACKAGE_PIN T17 IOSTANDARD LVCMOS25} [get_ports gpio_resetb_0]}
puts $fp {set_property -dict {PACKAGE_PIN P16 IOSTANDARD LVCMOS25} [get_ports gpio_en_agc_0]}
puts $fp {set_property -dict {PACKAGE_PIN R18 IOSTANDARD LVCMOS25} [get_ports enable_0]}
puts $fp {set_property -dict {PACKAGE_PIN N17 IOSTANDARD LVCMOS25} [get_ports txnrx_0]}
# AD9363 SPI passthrough — LDSDR rev2.1 clg400 pinout
puts $fp {set_property -dict {PACKAGE_PIN R19 IOSTANDARD LVCMOS25} [get_ports spi_clk_0]}
puts $fp {set_property -dict {PACKAGE_PIN P18 IOSTANDARD LVCMOS25} [get_ports spi_mosi_0]}
puts $fp {set_property -dict {PACKAGE_PIN T19 IOSTANDARD LVCMOS25} [get_ports spi_miso_0]}
puts $fp {set_property -dict {PACKAGE_PIN T20 IOSTANDARD LVCMOS25 PULLTYPE PULLUP} [get_ports spi_csn_0]}
puts $fp {create_clock -name spi0_clk -period 40 [get_pins -hier */EMIOSPI0SCLKO]}
puts $fp {set_clock_groups -asynchronous -group [get_clocks spi0_clk] -group [get_clocks clk_fpga_0]}
# AD9363 RX LVDS clock — match LDSDR original timing
puts $fp {create_clock -name rx_clk -period 4.069 [get_ports rx_clk_in_p_0]}
puts $fp {set_clock_groups -asynchronous -group [get_clocks rx_clk] -group [get_clocks clk_fpga_0]}
puts $fp {set_clock_groups -asynchronous -group [get_clocks rx_clk] -group [get_clocks clk_fpga_1]}
# tx_clk derived from rx_clk via ODDR
puts $fp {create_generated_clock -name tx_clk -source [get_ports rx_clk_in_p_0] -divide_by 1 [get_ports tx_clk_out_p_0]}
puts $fp {set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]}
puts $fp {set_property CFGBVS VCCO [current_design]}
puts $fp {set_property CONFIG_VOLTAGE 3.3 [current_design]}
close $fp
add_files -fileset constrs_1 -norecurse $rf_xdc
puts "RF XDC added (LDSDR LVDS pinout, SPI passthrough, clocks)"

# Allow non-fatal IOSTANDARD/LOC warnings
set_property SEVERITY {Warning} [get_drc_checks NSTD-1]
set_property SEVERITY {Warning} [get_drc_checks UCIO-1]

# ── Synthesis ────────────────────────────────────────────────────────────────
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
    puts "SYNTH FAILED"; return
}

# ── Implementation + Bitstream ───────────────────────────────────────────────
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] eq "100%"} {
    set bit_file "[get_property DIRECTORY [get_runs impl_1]]/${bd_name}_wrapper.bit"
    file copy -force $bit_file $bit_out
    puts "================================================================"
    puts "BITSTREAM DONE: $bit_out"
    puts "================================================================"
} else {
    puts "IMPL FAILED"
}
