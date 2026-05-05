# =============================================================================
# run_bd2.tcl — Block Design build in fresh C:\zynq_build project
# Run from project working dir:
#   cd "E:\fpga course design\ofdm_ldpc_pluto"
#   vivado -mode batch -source C:\run_bd2.tcl
# =============================================================================

open_project {C:/zynq_build/ofdm_ldpc_zynq.xpr}

# ── Add ofdm_ldpc_pl.v if not already present ─────────────────────────────────
if {[get_files -quiet -filter {NAME =~ *ofdm_ldpc_pl.v}] eq ""} {
    add_files -norecurse {
        {E:/fpga course design/ofdm_ldpc_pluto/src/hdl/ofdm_ldpc_pl.v}
    }
    puts "Added ofdm_ldpc_pl.v"
}
update_compile_order -fileset sources_1

# ── Fully purge any existing BD files from the project and disk ───────────────
# Stale BD files cause configure_noc.tcl init errors on subsequent runs.
foreach bd_f [get_files -quiet -filter {FILE_TYPE == {Block Designs}}] {
    remove_files $bd_f
    puts "Removed BD from project: $bd_f"
}
set bd_src_dir {C:/zynq_build/ofdm_ldpc_zynq.srcs/sources_1/bd}
if {[file exists $bd_src_dir]} {
    file delete -force $bd_src_dir
    puts "Deleted BD source dir."
}

# ── Create fresh BD ───────────────────────────────────────────────────────────
# Wrap in catch: Vivado may emit non-fatal configure_noc.tcl / bd::utils::dbg
# errors but still write the BD file successfully.
set bd_name "pluto_bd"
catch {create_bd_design $bd_name} create_err

if {[llength [get_bd_designs -quiet $bd_name]] == 0} {
    # BD not in memory — check if file was written anyway (usually is)
    set bd_written "${bd_src_dir}/${bd_name}/${bd_name}.bd"
    if {[file exists $bd_written]} {
        add_files -norecurse $bd_written
        open_bd_design [get_files -filter "NAME =~ *${bd_name}.bd"]
        puts "BD opened from written file."
    } else {
        puts "FATAL: BD creation failed and no file written. Error: $create_err"
        return
    }
}
current_bd_design $bd_name
delete_bd_objs -quiet [get_bd_cells *]
puts "BD ready: $bd_name"

# ── PS7 IP ────────────────────────────────────────────────────────────────────
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 processing_system7_0

set_property -dict [list \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100} \
    CONFIG.PCW_USE_FABRIC_INTERRUPT      {0}   \
    CONFIG.PCW_USE_M_AXI_GP0             {0}   \
    CONFIG.PCW_USE_S_AXI_HP0             {0}   \
] [get_bd_cells processing_system7_0]

apply_bd_automation \
    -rule xilinx.com:bd_rule:processing_system7 \
    -config {make_external "FIXED_IO, DDR" apply_board_preset "0"} \
    [get_bd_cells processing_system7_0]

puts "PS7 configured, DDR/FIXED_IO externalised."

# ── xlslice: FCLK_RESET0_N[3:0] → bit[0] ─────────────────────────────────────
create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:1.0 xlslice_0
set_property -dict [list \
    CONFIG.DIN_WIDTH  {4} \
    CONFIG.DIN_FROM   {0} \
    CONFIG.DIN_TO     {0} \
    CONFIG.DOUT_WIDTH {1} \
] [get_bd_cells xlslice_0]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_RESET0_N] \
               [get_bd_pins xlslice_0/Din]
puts "xlslice wired."

# ── ofdm_ldpc_pl module reference ────────────────────────────────────────────
create_bd_cell -type module -reference ofdm_ldpc_pl ofdm_ldpc_pl_0
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] \
               [get_bd_pins ofdm_ldpc_pl_0/clk]
connect_bd_net [get_bd_pins xlslice_0/Dout] \
               [get_bd_pins ofdm_ldpc_pl_0/rst_n]
puts "ofdm_ldpc_pl connected."

# ── Validate, save ────────────────────────────────────────────────────────────
validate_bd_design
save_bd_design
puts "BD validated and saved."

# ── Generate wrapper, copy to no-space path, set as top ──────────────────────
set wrapper_src [make_wrapper -files [get_files ${bd_name}.bd] -top]
puts "Wrapper at: $wrapper_src"
file copy -force $wrapper_src {C:/zynq_build/pluto_bd_wrapper.v}
add_files -norecurse {C:/zynq_build/pluto_bd_wrapper.v}
update_compile_order -fileset sources_1
set_property top ${bd_name}_wrapper [current_fileset]
update_compile_order -fileset sources_1
puts "Top: [get_property top [current_fileset]]"

# ── Disable all existing XDC, add minimal global config ──────────────────────
foreach xdc_f [get_files -of_objects [get_filesets constrs_1] \
               -filter {FILE_TYPE == XDC}] {
    set_property is_enabled false $xdc_f
    puts "Disabled XDC: $xdc_f"
}
set fh [open {C:/zynq_build/pluto_bd.xdc} w]
puts $fh {set_property CFGBVS        VCCO [current_design]}
puts $fh {set_property CONFIG_VOLTAGE 3.3  [current_design]}
close $fh
add_files -fileset constrs_1 -norecurse {C:/zynq_build/pluto_bd.xdc}
puts "XDC added."

# ── Synthesis ─────────────────────────────────────────────────────────────────
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
puts "SYNTH STATUS: [get_property STATUS [get_runs synth_1]]"
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
    puts "SYNTH FAILED — stopping."; return
}

# ── Implementation + Bitstream ────────────────────────────────────────────────
reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
puts "IMPL STATUS: [get_property STATUS [get_runs impl_1]]"
if {[get_property PROGRESS [get_runs impl_1]] eq "100%"} {
    puts "================================================================"
    puts "BITSTREAM DONE: [get_property DIRECTORY [get_runs impl_1]]/pluto_bd_wrapper.bit"
    puts "================================================================"
} else {
    puts "IMPL FAILED"
}
