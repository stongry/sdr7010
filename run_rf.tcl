# =============================================================================
# run_rf.tcl — Full RF OFDM+LDPC design for PlutoSDR (fresh project)
# Run: vivado -mode batch -source C:\run_rf.tcl
# =============================================================================

# ── Create fresh project (delete old if exists) ───────────────────────────────
set proj_dir {C:/zynq_build_rf}
if {[file exists $proj_dir]} {
    file delete -force $proj_dir
    puts "Deleted old project dir."
}
create_project ofdm_ldpc_rf $proj_dir -part xc7z010clg225-1
set_property target_language Verilog [current_project]
puts "Project created: $proj_dir"

# ── Copy HDL sources from C:\ (no-space path) and add ────────────────────────
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
} {
    set src "C:/ofdm_hdl_${src_file}"
    set dst "${proj_dir}/${src_file}"
    file copy -force $src $dst
    add_files -norecurse $dst
    puts "Added: $src_file"
}
update_compile_order -fileset sources_1
puts "Sources added."

# ── Create Block Design ───────────────────────────────────────────────────────
set bd_name "pluto_rf_bd"
create_bd_design $bd_name
current_bd_design $bd_name
puts "BD created: $bd_name"

# ── PS7 ──────────────────────────────────────────────────────────────────────
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 processing_system7_0

set_property -dict [list \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ  {100} \
    CONFIG.PCW_USE_FABRIC_INTERRUPT      {0}   \
    CONFIG.PCW_USE_M_AXI_GP0             {0}   \
    CONFIG.PCW_USE_S_AXI_HP0             {0}   \
    CONFIG.PCW_GPIO_EMIO_GPIO_ENABLE     {1}   \
    CONFIG.PCW_GPIO_EMIO_GPIO_IO         {2}   \
] [get_bd_cells processing_system7_0]

apply_bd_automation \
    -rule xilinx.com:bd_rule:processing_system7 \
    -config {make_external "FIXED_IO, DDR" apply_board_preset "0"} \
    [get_bd_cells processing_system7_0]
puts "PS7 configured."

# ── xlslice: extract FCLK_RESET0_N bit[0] ────────────────────────────────────
create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:1.0 xlslice_0
set_property -dict [list \
    CONFIG.DIN_WIDTH  {4} \
    CONFIG.DIN_FROM   {0} \
    CONFIG.DIN_TO     {0} \
    CONFIG.DOUT_WIDTH {1} \
] [get_bd_cells xlslice_0]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_RESET0_N] \
               [get_bd_pins xlslice_0/Din]

# ── ofdm_ldpc_rf_top module reference ────────────────────────────────────────
create_bd_cell -type module -reference ofdm_ldpc_rf_top ofdm_ldpc_rf_top_0

# Clock and reset
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] \
               [get_bd_pins ofdm_ldpc_rf_top_0/fclk]
connect_bd_net [get_bd_pins xlslice_0/Dout] \
               [get_bd_pins ofdm_ldpc_rf_top_0/rst_n]

# Make AD9363 interface pins external
make_bd_pins_external [get_bd_pins ofdm_ldpc_rf_top_0/rx_clk_in]
make_bd_pins_external [get_bd_pins ofdm_ldpc_rf_top_0/rx_frame_in]
make_bd_pins_external [get_bd_pins ofdm_ldpc_rf_top_0/rx_data_in]
make_bd_pins_external [get_bd_pins ofdm_ldpc_rf_top_0/tx_clk_out]
make_bd_pins_external [get_bd_pins ofdm_ldpc_rf_top_0/tx_frame_out]
make_bd_pins_external [get_bd_pins ofdm_ldpc_rf_top_0/tx_data_out]
make_bd_pins_external [get_bd_pins ofdm_ldpc_rf_top_0/enable]
make_bd_pins_external [get_bd_pins ofdm_ldpc_rf_top_0/txnrx]
make_bd_pins_external [get_bd_pins ofdm_ldpc_rf_top_0/gpio_resetb]
make_bd_pins_external [get_bd_pins ofdm_ldpc_rf_top_0/gpio_en_agc]
puts "AD9363 pins made external."

# ── xlconcat: {rx_done, pass_flag} → PS7 EMIO GPIO_I[1:0] ───────────────────
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 xlconcat_0
set_property -dict [list \
    CONFIG.NUM_PORTS {2} \
    CONFIG.IN0_WIDTH {1} \
    CONFIG.IN1_WIDTH {1} \
] [get_bd_cells xlconcat_0]
connect_bd_net [get_bd_pins ofdm_ldpc_rf_top_0/pass_flag] \
               [get_bd_pins xlconcat_0/In0]
connect_bd_net [get_bd_pins ofdm_ldpc_rf_top_0/rx_done] \
               [get_bd_pins xlconcat_0/In1]
connect_bd_net [get_bd_pins xlconcat_0/dout] \
               [get_bd_pins processing_system7_0/GPIO_I]
puts "EMIO GPIO: GPIO_I[0]=pass_flag  GPIO_I[1]=rx_done"

# ── Validate & save ───────────────────────────────────────────────────────────
validate_bd_design
save_bd_design
puts "BD validated and saved."

# ── Wrapper ───────────────────────────────────────────────────────────────────
set wrapper_src [make_wrapper -files [get_files ${bd_name}.bd] -top]
file copy -force $wrapper_src ${proj_dir}/pluto_rf_wrapper.v
add_files -norecurse ${proj_dir}/pluto_rf_wrapper.v
update_compile_order -fileset sources_1
set_property top ${bd_name}_wrapper [current_fileset]
update_compile_order -fileset sources_1
puts "Top: [get_property top [current_fileset]]"

# ── Add RF constraints ────────────────────────────────────────────────────────
file copy -force {C:/ofdm_hdl_pluto_rf.xdc} ${proj_dir}/pluto_rf.xdc
add_files -fileset constrs_1 -norecurse ${proj_dir}/pluto_rf.xdc
puts "RF XDC added."

# ── Synthesis ─────────────────────────────────────────────────────────────────
launch_runs synth_1 -jobs 4
wait_on_run synth_1
puts "SYNTH STATUS: [get_property STATUS [get_runs synth_1]]"
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
    puts "SYNTH FAILED"; return
}

# ── Implementation + Bitstream ────────────────────────────────────────────────
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
puts "IMPL STATUS: [get_property STATUS [get_runs impl_1]]"
if {[get_property PROGRESS [get_runs impl_1]] eq "100%"} {
    set bit_file "[get_property DIRECTORY [get_runs impl_1]]/pluto_rf_wrapper.bit"
    file copy -force $bit_file {C:/pluto_rf_wrapper.bit}
    puts "================================================================"
    puts "BITSTREAM DONE: C:/pluto_rf_wrapper.bit"
    puts "================================================================"
} else {
    puts "IMPL FAILED"
}
