# =============================================================================
# pluto.xdc — ADALM-PLUTO (xc7z010clg225-1) 约束文件
# OFDM+LDPC 课程设计
# =============================================================================

# -----------------------------------------------------------------------------
# 主时钟 (PS 提供给 PL 的时钟，来自 ZYNQ PS FCLK_CLK0)
# 默认频率 100 MHz，可在 PS 配置中修改
# -----------------------------------------------------------------------------
create_clock -period 10.000 -name clk_100m [get_ports clk]

# -----------------------------------------------------------------------------
# 输入/输出延迟（相对于时钟）
# -----------------------------------------------------------------------------
set_input_delay  -clock clk_100m -max 2.0 [get_ports {tx_info_bits[*]}]
set_input_delay  -clock clk_100m -min 0.5 [get_ports {tx_info_bits[*]}]
set_input_delay  -clock clk_100m -max 2.0 [get_ports tx_valid_in]
set_input_delay  -clock clk_100m -min 0.5 [get_ports tx_valid_in]

set_input_delay  -clock clk_100m -max 2.0 [get_ports {rx_iq_i[*]}]
set_input_delay  -clock clk_100m -min 0.5 [get_ports {rx_iq_i[*]}]
set_input_delay  -clock clk_100m -max 2.0 [get_ports {rx_iq_q[*]}]
set_input_delay  -clock clk_100m -min 0.5 [get_ports {rx_iq_q[*]}]

set_output_delay -clock clk_100m -max 2.0 [get_ports {tx_iq_i[*]}]
set_output_delay -clock clk_100m -min 0.5 [get_ports {tx_iq_i[*]}]
set_output_delay -clock clk_100m -max 2.0 [get_ports {tx_iq_q[*]}]
set_output_delay -clock clk_100m -min 0.5 [get_ports {tx_iq_q[*]}]

# -----------------------------------------------------------------------------
# 虚假路径（复位为异步）
# -----------------------------------------------------------------------------
set_false_path -from [get_ports rst_n]

# -----------------------------------------------------------------------------
# 综合属性
# -----------------------------------------------------------------------------
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
