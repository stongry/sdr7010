# =============================================================================
# pluto_zynq.xdc — Constraints for zynq_top wrapper
# Device: xc7z010clg225-1 (ADALM-PLUTO)
#
# DDR and FIXED_IO ports are constrained automatically by the PS7 primitive
# (silicon-fixed connections to specific package balls — no XDC needed).
#
# The PL clock comes from PS7 FCLK_CLK0 (100 MHz) through a BUFG.
# Vivado infers this clock from the PS7 primitive configuration.
# We declare it explicitly here for timing analysis.
# =============================================================================

# PL fabric clock: PS7 FCLK_CLK0 → BUFG → clk (100 MHz)
create_clock -period 10.000 -name clk_fpga_0 [get_pins u_ps7/FCLKCLK[0]]

# False path on async reset (fclk_rst_n comes from PS7 FCLK_RESET0_N,
# which is async relative to PL logic until synchronized).
set_false_path -from [get_pins u_ps7/FCLKRESETN[0]]

# Global device configuration
set_property CFGBVS        VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3  [current_design]
