###############################################################################
## Pluto-LDSDR: ADI hdl pluto project ported to LDSDR 7010 rev2.1
## Part: xc7z010clg400-2 (vs pluto's xc7z010clg225-1)
## Mode: LVDS_25 (vs pluto's CMOS LVCMOS18)
###############################################################################

source ../../scripts/adi_env.tcl
source $ad_hdl_dir/projects/scripts/adi_project_xilinx.tcl
source $ad_hdl_dir/projects/scripts/adi_board.tcl

# 关键: 改 part = xc7z010clg400-2
adi_project_create pluto_ldsdr 0 {} "xc7z010clg400-2"

adi_project_files pluto_ldsdr [list \
  "system_top.v" \
  "system_constr.xdc" \
  "$ad_hdl_dir/library/common/ad_iobuf.v"]

# Disable 自动生成的 ps7 xdc (我们自己提供)
set_property is_enabled false [get_files  *system_sys_ps7_0.xdc]
adi_project_run pluto_ldsdr
