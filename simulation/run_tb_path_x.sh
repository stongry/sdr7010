#!/bin/bash
# =============================================================================
# run_tb_path_x.sh — Vivado xsim driver for Path X simulation
#
# Usage:
#   source /mnt/backup/Xilinx/Vivado/2024.2/settings64.sh
#   bash run_tb_path_x.sh
#
# Outputs:
#   path_x_sim/path_x.vcd   — waveform for GTKWave
#   path_x_sim/xsim.log     — simulation log
# =============================================================================
set -e
SRC=/home/ysara/fpga_hdl
OUT=/home/ysara/fpga_hdl/path_x_sim
mkdir -p $OUT
cd $OUT

xvlog -sv \
    $SRC/ofdm_ldpc_top.v \
    $SRC/ldpc_encoder.v \
    $SRC/ldpc_decoder.v \
    $SRC/qpsk_mod.v \
    $SRC/qpsk_demod.v \
    $SRC/cp_insert.v \
    $SRC/cp_remove.v \
    $SRC/channel_est.v \
    $SRC/tx_subcarrier_map.v \
    $SRC/rx_subcarrier_demap.v \
    $SRC/llr_assembler.v \
    $SRC/llr_buffer.v \
    $SRC/xfft_stub.v \
    $SRC/tb_path_x.v 2>&1 | tail -20

xelab tb_path_x -debug typical -snapshot path_x_snap 2>&1 | tail -10

cat > run_xsim.tcl <<'EOF'
log_wave -recursive *
run all
quit
EOF

xsim path_x_snap -tclbatch run_xsim.tcl -log xsim.log 2>&1 | tail -40

echo ""
echo "Waveform: $OUT/path_x.vcd"
echo "Log:      $OUT/xsim.log"
