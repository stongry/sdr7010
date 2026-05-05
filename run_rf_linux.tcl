# =============================================================================
# run_rf_linux.tcl — RF OFDM+LDPC for PlutoSDR (Linux build)
# Run: source /mnt/backup/Xilinx/Vivado/2024.2/settings64.sh
#      vivado -mode batch -source /home/eea/fpga_hdl/run_rf_linux.tcl
# =============================================================================

set src_dir  /home/eea/fpga_hdl
set proj_dir /home/eea/zynq_build_rf_linux
set bit_out  /home/eea/pluto_rf_wrapper.bit

# ── Fresh project ─────────────────────────────────────────────────────────────
if {[file exists $proj_dir]} {
    file delete -force $proj_dir
}
create_project ofdm_ldpc_rf $proj_dir -part xc7z010clg225-1
set_property target_language Verilog [current_project]
puts "Project created: $proj_dir (xc7z010clg225-1)"

# ── Add HDL sources (ALL 15 modules) ─────────────────────────────────────────
foreach src_file {
    ad9363_cmos_if.v
    ofdm_ldpc_rf_top.v
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
} {
    add_files -norecurse "${src_dir}/${src_file}"
    puts "Added: $src_file"
}
update_compile_order -fileset sources_1

# ── Block Design (with catch workaround for Vivado 2024.2 xdma/xxv quirk) ────
set bd_name "pluto_rf_bd"
set bd_src_dir "${proj_dir}/ofdm_ldpc_rf.srcs/sources_1/bd"
catch {create_bd_design $bd_name} create_err

if {[llength [get_bd_designs -quiet $bd_name]] == 0} {
    set bd_written "${bd_src_dir}/${bd_name}/${bd_name}.bd"
    if {[file exists $bd_written]} {
        add_files -norecurse $bd_written
        open_bd_design [get_files -filter "NAME =~ *${bd_name}.bd"]
        puts "BD opened from written file."
    } else {
        puts "FATAL: BD creation failed. Error: $create_err"; return
    }
}
current_bd_design $bd_name
delete_bd_objs -quiet [get_bd_cells *]
puts "BD ready: $bd_name"

# ── PS7 with EMIO GPIO ───────────────────────────────────────────────────────
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 processing_system7_0
set_property -dict [list \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ  {100} \
    CONFIG.PCW_USE_FABRIC_INTERRUPT      {0}   \
    CONFIG.PCW_USE_M_AXI_GP0             {0}   \
    CONFIG.PCW_USE_S_AXI_HP0             {0}   \
    CONFIG.PCW_GPIO_EMIO_GPIO_ENABLE     {1}   \
    CONFIG.PCW_GPIO_EMIO_GPIO_IO         {14}  \
    CONFIG.PCW_SPI0_PERIPHERAL_ENABLE    {1}   \
    CONFIG.PCW_SPI0_SPI0_IO              {EMIO} \
    CONFIG.PCW_SPI0_GRP_SS0_ENABLE       {1}   \
    CONFIG.PCW_SPI0_GRP_SS0_IO           {EMIO} \
    CONFIG.PCW_SPI_PERIPHERAL_FREQMHZ    {166.666667} \
] [get_bd_cells processing_system7_0]

apply_bd_automation \
    -rule xilinx.com:bd_rule:processing_system7 \
    -config {make_external "FIXED_IO, DDR" apply_board_preset "0"} \
    [get_bd_cells processing_system7_0]
puts "PS7 configured."

# ── xlslice for FCLK_RESET0_N → rst_n ────────────────────────────────────────
create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:1.0 xlslice_0
set_property -dict [list \
    CONFIG.DIN_WIDTH  {4} \
    CONFIG.DIN_FROM   {0} \
    CONFIG.DIN_TO     {0} \
    CONFIG.DOUT_WIDTH {1} \
] [get_bd_cells xlslice_0]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_RESET0_N] [get_bd_pins xlslice_0/Din]

# ── ofdm_ldpc_rf_top module ref + external pins ──────────────────────────────
create_bd_cell -type module -reference ofdm_ldpc_rf_top ofdm_ldpc_rf_top_0
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins ofdm_ldpc_rf_top_0/fclk]
connect_bd_net [get_bd_pins xlslice_0/Dout] [get_bd_pins ofdm_ldpc_rf_top_0/rst_n]

foreach pin {rx_clk_in rx_frame_in rx_data_in tx_clk_out tx_frame_out tx_data_out
             enable txnrx} {
    make_bd_pins_external [get_bd_pins ofdm_ldpc_rf_top_0/$pin]
}
puts "AD9363 data pins made external (resetb/en_agc come from PS GPIO_O)."

# ── Slice PS7 GPIO_O[13:12] for AD9363 reset/en_agc control ─────────────────
# Linux ad9361 driver expects EMIO GPIO 12 = en_agc, 13 = reset
create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:1.0 xlslice_resetb
set_property -dict [list \
    CONFIG.DIN_WIDTH  {14} \
    CONFIG.DIN_FROM   {13} \
    CONFIG.DIN_TO     {13} \
    CONFIG.DOUT_WIDTH {1} \
] [get_bd_cells xlslice_resetb]
connect_bd_net [get_bd_pins processing_system7_0/GPIO_O] [get_bd_pins xlslice_resetb/Din]

create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:1.0 xlslice_enagc
set_property -dict [list \
    CONFIG.DIN_WIDTH  {14} \
    CONFIG.DIN_FROM   {12} \
    CONFIG.DIN_TO     {12} \
    CONFIG.DOUT_WIDTH {1} \
] [get_bd_cells xlslice_enagc]
connect_bd_net [get_bd_pins processing_system7_0/GPIO_O] [get_bd_pins xlslice_enagc/Din]

make_bd_pins_external -name gpio_resetb_0 [get_bd_pins xlslice_resetb/Dout]
make_bd_pins_external -name gpio_en_agc_0 [get_bd_pins xlslice_enagc/Dout]
puts "GPIO_O[13]->gpio_resetb, GPIO_O[12]->gpio_en_agc"

# ── xlconcat: pass_flag/rx_done → PS GPIO_I ──────────────────────────────────
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 xlconcat_0
set_property -dict [list \
    CONFIG.NUM_PORTS {3} \
    CONFIG.IN0_WIDTH {1} \
    CONFIG.IN1_WIDTH {1} \
    CONFIG.IN2_WIDTH {12} \
] [get_bd_cells xlconcat_0]
connect_bd_net [get_bd_pins ofdm_ldpc_rf_top_0/pass_flag] [get_bd_pins xlconcat_0/In0]
connect_bd_net [get_bd_pins ofdm_ldpc_rf_top_0/rx_done]   [get_bd_pins xlconcat_0/In1]
# Tie GPIO_I[13:2] to 0 (driver doesn't need to read these as inputs)
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 xlconst_0
set_property -dict [list CONFIG.CONST_WIDTH {12} CONFIG.CONST_VAL {0}] [get_bd_cells xlconst_0]
connect_bd_net [get_bd_pins xlconst_0/dout] [get_bd_pins xlconcat_0/In2]
connect_bd_net [get_bd_pins xlconcat_0/dout] [get_bd_pins processing_system7_0/GPIO_I]
puts "EMIO GPIO_I[0]=pass_flag GPIO_I[1]=rx_done GPIO_I[13:2]=0"

# ── PS7 SPI0 EMIO → external (passthrough to AD9363) ─────────────────────────
# PS7 EMIO SPI0 master mode pins
make_bd_pins_external -name spi_clk_0  [get_bd_pins processing_system7_0/SPI0_SCLK_O]
make_bd_pins_external -name spi_mosi_0 [get_bd_pins processing_system7_0/SPI0_MOSI_O]
make_bd_pins_external -name spi_csn_0  [get_bd_pins processing_system7_0/SPI0_SS_O]
make_bd_pins_external -name spi_miso_0 [get_bd_pins processing_system7_0/SPI0_MISO_I]
# CRITICAL: SPI0_SS_I (slave SS input) must be tied HIGH in master mode.
# If left at default 0, PS7 SPI controller thinks it's being selected as slave
# and SPI master mode fails (returns 0xFF on MISO).
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 xlconst_ssi
set_property -dict [list CONFIG.CONST_WIDTH {1} CONFIG.CONST_VAL {1}] [get_bd_cells xlconst_ssi]
connect_bd_net [get_bd_pins xlconst_ssi/dout] [get_bd_pins processing_system7_0/SPI0_SS_I]
puts "PS7 SPI0 EMIO routed (clk/mosi/miso/csn external; SS_I tied HIGH for master mode)"

validate_bd_design
save_bd_design
puts "BD validated and saved."

# ── Wrapper ──────────────────────────────────────────────────────────────────
set wrapper_src [make_wrapper -files [get_files ${bd_name}.bd] -top]
add_files -norecurse $wrapper_src
update_compile_order -fileset sources_1
set_property top ${bd_name}_wrapper [current_fileset]
update_compile_order -fileset sources_1
puts "Top: [get_property top [current_fileset]]"

# ── XDC ──────────────────────────────────────────────────────────────────────
add_files -fileset constrs_1 -norecurse ${src_dir}/pluto_rf.xdc
puts "RF XDC added."

# Allow non-fatal IOSTANDARD/LOC warnings (we set them, this is paranoia)
set_property SEVERITY {Warning} [get_drc_checks NSTD-1]
set_property SEVERITY {Warning} [get_drc_checks UCIO-1]

# Enable bitstream compression via constraint file (target: fit in 1MB qspi-fsbl-uboot partition)
set bitstream_xdc "${proj_dir}/bitstream_compress.xdc"
set fp [open $bitstream_xdc w]
puts $fp "set_property BITSTREAM.GENERAL.COMPRESS TRUE \[current_design\]"
puts $fp "set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 \[current_design\]"
close $fp
add_files -fileset constrs_1 -norecurse $bitstream_xdc
puts "Bitstream compression XDC added"

# ── Synthesis ────────────────────────────────────────────────────────────────
launch_runs synth_1 -jobs 4
wait_on_run synth_1
puts "SYNTH STATUS: [get_property STATUS [get_runs synth_1]]"
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
    puts "SYNTH FAILED"; return
}

# ── Implementation + Bitstream ───────────────────────────────────────────────
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
puts "IMPL STATUS: [get_property STATUS [get_runs impl_1]]"
if {[get_property PROGRESS [get_runs impl_1]] eq "100%"} {
    set bit_file "[get_property DIRECTORY [get_runs impl_1]]/${bd_name}_wrapper.bit"
    file copy -force $bit_file $bit_out
    puts "================================================================"
    puts "BITSTREAM DONE: $bit_out"
    puts "================================================================"
} else {
    puts "IMPL FAILED"
}
