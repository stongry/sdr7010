# Customize Vivado xfft_v9.1 IP for 64-pt fixed-point pipelined streaming.
# Output: ./ip_xfft/xfft_64/xfft_64.xci + sim/synth files.

create_project -in_memory -part xc7z010clg400-2 tmp
set_property target_language Verilog [current_project]

create_ip -name xfft -vendor xilinx.com -library ip -version 9.1 \
    -module_name xfft_64 -dir ./ip_xfft

set_property -dict [list \
    CONFIG.transform_length          {64} \
    CONFIG.implementation_options    {pipelined_streaming_io} \
    CONFIG.data_format               {fixed_point} \
    CONFIG.input_width               {16} \
    CONFIG.scaling_options           {scaled} \
    CONFIG.rounding_modes            {convergent_rounding} \
    CONFIG.phase_factor_width        {16} \
    CONFIG.cyclic_prefix_insertion   {false} \
    CONFIG.throttle_scheme           {nonrealtime} \
    CONFIG.target_data_throughput    {50} \
    CONFIG.target_clock_frequency    {50} \
    CONFIG.aresetn                   {true} \
    CONFIG.aclken                    {false} \
] [get_ips xfft_64]

generate_target all [get_files [get_ips xfft_64].xci]
puts "==> xfft_64 IP files generated under ./ip_xfft/"

# Print the .veo (instantiation template) so we see the exact port list
set veo_path [get_files -filter {NAME =~ "*.veo"} -of_objects [get_ips xfft_64]]
if {[llength $veo_path] > 0} {
    set fp [open [lindex $veo_path 0] r]
    puts "==== xfft_64.veo (instantiation template) ===="
    puts [read $fp]
    close $fp
}
