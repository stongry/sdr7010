# =============================================================================
# run_sim.tcl — Vivado behavioral simulation (batch)
# =============================================================================
open_project {E:/fpga course design/ofdm_ldpc_pluto/ofdm_ldpc_pluto.xpr}
set_property target_simulator XSim [current_project]
set_property -name {xsim.simulate.runtime} -value {10ms} -objects [get_filesets sim_1]
launch_simulation -simset sim_1 -mode behavioral
run 10ms
close_sim
puts "==> Simulation complete"
