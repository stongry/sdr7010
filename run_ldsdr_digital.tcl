# =============================================================================
# run_ldsdr_digital.tcl — Digital loopback OFDM+LDPC for LDSDR 7010 rev2.1
# Target: xc7z010clg400-2 (LDSDR board, NOT PlutoSDR)
# Verifies pass_flag=1 and rx_done=1 via EMIO GPIO from PS
# Run: source /mnt/backup/Xilinx/Vivado/2024.2/settings64.sh
#      vivado -mode batch -source /home/eea/fpga_hdl/run_ldsdr_digital.tcl
# =============================================================================

set src_dir  /home/eea/fpga_hdl
set proj_dir /home/eea/zynq_build_ldsdr
set bit_out  /home/eea/ofdm_ldpc_ldsdr.bit

# ── Fresh project (LDSDR part = xc7z010clg400-2) ─────────────────────────────
if {[file exists $proj_dir]} {
    file delete -force $proj_dir
}
create_project ofdm_ldpc_ldsdr $proj_dir -part xc7z010clg400-2
set_property target_language Verilog [current_project]
puts "Project created: $proj_dir (xc7z010clg400-2)"

# ── Add HDL sources (digital loopback - no AD9363 interface needed) ──────────
foreach src_file {
    ofdm_ldpc_pl.v
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
}
update_compile_order -fileset sources_1
puts "Sources added (15 modules)"

# ── Block Design (with catch workaround for Vivado 2024.2) ──────────────────
set bd_name "ldsdr_digital_bd"
set bd_src_dir "${proj_dir}/ofdm_ldpc_ldsdr.srcs/sources_1/bd"
catch {create_bd_design $bd_name} create_err
if {[llength [get_bd_designs -quiet $bd_name]] == 0} {
    set bd_written "${bd_src_dir}/${bd_name}/${bd_name}.bd"
    if {[file exists $bd_written]} {
        add_files -norecurse $bd_written
        open_bd_design [get_files -filter "NAME =~ *${bd_name}.bd"]
    } else {
        puts "FATAL: BD creation failed. Error: $create_err"; return
    }
}
current_bd_design $bd_name
delete_bd_objs -quiet [get_bd_cells *]
puts "BD ready: $bd_name"

# ── PS7 with FULL LDSDR config (extracted from LDSDR design_1_bd.tcl) ────────
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 processing_system7_0

# Source LDSDR's exact PS7 config (618 PCW_* params: DDR, MIO, USB, I2C, SPI, etc)
source ${src_dir}/ldsdr_ps7_config.tcl

# Override only what we need: enable EMIO GPIO with 32 bits to read full counters
lappend ps7_props CONFIG.PCW_GPIO_EMIO_GPIO_ENABLE {1}
lappend ps7_props CONFIG.PCW_GPIO_EMIO_GPIO_IO {32}
# Disable AXI GP0 since we don't use it (LDSDR enabled it for ad9361 driver)
lappend ps7_props CONFIG.PCW_USE_M_AXI_GP0 {0}
# Lower FCLK0 from 100MHz to 50MHz: WNS=-4.524ns at 100MHz means design path needs ~14.5ns
# 50MHz (20ns period) gives generous timing margin and avoids functional bugs from timing violations
lappend ps7_props CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {50}

set_property -dict $ps7_props [get_bd_cells processing_system7_0]

apply_bd_automation \
    -rule xilinx.com:bd_rule:processing_system7 \
    -config {make_external "FIXED_IO, DDR" apply_board_preset "0"} \
    [get_bd_cells processing_system7_0]
puts "PS7 configured with LDSDR's exact MIO/DDR/USB/I2C/SPI settings + EMIO GPIO 6 bits"

# ── xlslice for FCLK_RESET0_N → rst_n ────────────────────────────────────────
create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:1.0 xlslice_0
set_property -dict [list \
    CONFIG.DIN_WIDTH  {4} \
    CONFIG.DIN_FROM   {0} \
    CONFIG.DIN_TO     {0} \
    CONFIG.DOUT_WIDTH {1} \
] [get_bd_cells xlslice_0]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_RESET0_N] [get_bd_pins xlslice_0/Din]

# ── proc_sys_reset for proper synchronous reset (1-cycle min hold) ──────────
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 proc_sys_reset_0
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins proc_sys_reset_0/slowest_sync_clk]
connect_bd_net [get_bd_pins xlslice_0/Dout] [get_bd_pins proc_sys_reset_0/ext_reset_in]
# ext_reset_in active LOW = matches FCLK_RESET0_N
set_property CONFIG.C_EXT_RST_HIGH_ACTIVE {0} [get_bd_cells proc_sys_reset_0]
set_property CONFIG.C_AUX_RST_HIGH_ACTIVE {0} [get_bd_cells proc_sys_reset_0]

# Tie aux_reset_in HIGH (not used, C_AUX_RST_HIGH_ACTIVE=0 -> 1=inactive)
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 xlconst_one
set_property -dict [list CONFIG.CONST_WIDTH {1} CONFIG.CONST_VAL {1}] [get_bd_cells xlconst_one]
connect_bd_net [get_bd_pins xlconst_one/dout] [get_bd_pins proc_sys_reset_0/aux_reset_in]
connect_bd_net [get_bd_pins xlconst_one/dout] [get_bd_pins proc_sys_reset_0/dcm_locked]
# CRITICAL: mb_debug_sys_rst is HIGH-ACTIVE - must tie LOW or peripheral_aresetn never releases
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 xlconst_zero
set_property -dict [list CONFIG.CONST_WIDTH {1} CONFIG.CONST_VAL {0}] [get_bd_cells xlconst_zero]
connect_bd_net [get_bd_pins xlconst_zero/dout] [get_bd_pins proc_sys_reset_0/mb_debug_sys_rst]

# ── ofdm_ldpc_pl module reference (pure digital) ────────────────────────────
create_bd_cell -type module -reference ofdm_ldpc_pl ofdm_ldpc_pl_0
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins ofdm_ldpc_pl_0/clk]
# Use peripheral_aresetn (active-low, synchronized) - matches our rst_n convention
connect_bd_net [get_bd_pins proc_sys_reset_0/peripheral_aresetn] [get_bd_pins ofdm_ldpc_pl_0/rst_n_ext]

# ── xlconcat: 6 debug bits → PS GPIO_I[5:0] ─────────────────────────────────
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 xlconcat_0
# Layout: bit[0]=pf, bit[1]=rxd, bit[31:2]=chllr_decoded[125:96] (raw bits)
set_property -dict [list CONFIG.NUM_PORTS {3} \
    CONFIG.IN0_WIDTH {1} CONFIG.IN1_WIDTH {1} CONFIG.IN2_WIDTH {30}] \
    [get_bd_cells xlconcat_0]
# EMIO 32-bit map: pf, rxd, chllr_decoded[125:96] raw
connect_bd_net [get_bd_pins ofdm_ldpc_pl_0/pass_flag]         [get_bd_pins xlconcat_0/In0]
connect_bd_net [get_bd_pins ofdm_ldpc_pl_0/rx_done]           [get_bd_pins xlconcat_0/In1]
connect_bd_net [get_bd_pins ofdm_ldpc_pl_0/dbg_chllr_sym1_lo] [get_bd_pins xlconcat_0/In2]

connect_bd_net [get_bd_pins xlconcat_0/dout] [get_bd_pins processing_system7_0/GPIO_I]

# Expose heartbeat to physical LED pin (LDSDR USERLED on G14)
# Visual proof PL is alive even without UART/EMIO access
create_bd_port -dir O led_heartbeat
connect_bd_net [get_bd_ports led_heartbeat] [get_bd_pins ofdm_ldpc_pl_0/heartbeat]
puts "Created led_heartbeat external port -> G14"
puts "EMIO GPIO_I\[5:0\] = {dbg_llr_done_seen,dbg_eq_seen,dbg_fft_m_seen,dbg_cp_rem_seen,rx_done,pass_flag}"

validate_bd_design
save_bd_design

# ── Wrapper ──────────────────────────────────────────────────────────────────
set wrapper_src [make_wrapper -files [get_files ${bd_name}.bd] -top]
add_files -norecurse $wrapper_src
update_compile_order -fileset sources_1
set_property top ${bd_name}_wrapper [current_fileset]
update_compile_order -fileset sources_1

# ── XDC: LED pin (G14 = USERLED on LDSDR) ──────────────────────────────────
set led_xdc "${proj_dir}/ldsdr_led.xdc"
set fp [open $led_xdc w]
puts $fp "set_property -dict {PACKAGE_PIN G14 IOSTANDARD LVCMOS18} \[get_ports led_heartbeat\]"
puts $fp "set_property BITSTREAM.GENERAL.COMPRESS TRUE \[current_design\]"
close $fp
add_files -fileset constrs_1 -norecurse $led_xdc
puts "LED + compress XDC added (G14 = USERLED)"

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
