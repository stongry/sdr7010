# Vivado GUI launcher for Path X simulation
# Usage:
#   vivado -mode gui -source open_in_vivado.tcl
#
# Compiles the testbench, runs simulation, opens waveform viewer.

set this_dir [file dirname [file normalize [info script]]]
set src_dir  "[file dirname $this_dir]"   ;# fpga_hdl/

set work_dir "$this_dir/path_x_sim"
file mkdir $work_dir
cd $work_dir

# Compile
exec xvlog \
    "$src_dir/qpsk_mod.v" \
    "$src_dir/qpsk_demod.v" \
    "$this_dir/tb_path_x_simple.v" >&@ stdout

# Elaborate
exec xelab tb_path_x_simple -debug typical -snapshot pxs >&@ stdout

# Launch xsim GUI
exec xsim --gui pxs &
