#!/bin/bash
# Path A: 在 build server 上构建 pluto_ldsdr 项目
# 把 ADI pluto reference 移植到 LDSDR rev2.1 (xc7z010clg400-2) + LVDS 模式
set -e
SERVER="eea@10.24.79.1"
PORT=2424

# 1. 在 build server 创建项目目录
ssh -p $PORT $SERVER "mkdir -p /home/eea/adi_hdl/projects/pluto_ldsdr"

# 2. 上传我们写的项目文件
scp -P $PORT /home/ysara/fpga_hdl/pluto_ldsdr/* $SERVER:/home/eea/adi_hdl/projects/pluto_ldsdr/

# 3. 启动 Vivado 编译 (后台 nohup)
ssh -p $PORT $SERVER "cd /home/eea/adi_hdl/projects/pluto_ldsdr && \
  source /mnt/backup/Xilinx/Vivado/2024.2/settings64.sh && \
  ADI_IGNORE_VERSION_CHECK=1 nohup vivado -mode batch -source system_project.tcl > build.log 2>&1 &"

echo "Build started on server. Check with:"
echo "  ssh -p $PORT $SERVER 'tail -f /home/eea/adi_hdl/projects/pluto_ldsdr/build.log'"
