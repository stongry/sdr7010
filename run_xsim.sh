#!/bin/bash
# -----------------------------------------------------------------------------
# run_xsim.sh — Headless xsim run for tb_ofdm_ldpc, used on the build server.
# -----------------------------------------------------------------------------
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Source Vivado environment
VIVADO_PATH="${VIVADO_PATH:-/mnt/backup/Xilinx/Vivado/2024.2}"
if [ -f "$VIVADO_PATH/settings64.sh" ]; then
    # shellcheck disable=SC1091
    . "$VIVADO_PATH/settings64.sh"
else
    echo "ERROR: Vivado not found at $VIVADO_PATH" >&2
    exit 1
fi

WORK=xsim_work
rm -rf "$WORK"
mkdir -p "$WORK"
cd "$WORK"

SOURCES=(
    ../tb_ofdm_ldpc.v
    ../ofdm_ldpc_top.v
    ../ldpc_encoder.v
    ../ldpc_decoder.v
    ../qpsk_mod.v
    ../qpsk_demod.v
    ../tx_subcarrier_map.v
    ../rx_subcarrier_demap.v
    ../cp_insert.v
    ../cp_remove.v
    ../xfft_stub.v
    ../channel_est.v
    ../llr_assembler.v
    ../llr_buffer.v
)

echo "[1/3] xvlog: compiling ${#SOURCES[@]} sources"
xvlog -sv "${SOURCES[@]}" 2>&1 | tail -40

echo "[2/3] xelab: elaborating tb_ofdm_ldpc"
xelab tb_ofdm_ldpc -snapshot tb_sim -timescale 1ns/1ps 2>&1 | tail -20

echo "[3/3] xsim: running"
xsim tb_sim -R 2>&1 | tee xsim.log
echo "---"
echo "EXIT marker (look for 'PASSED', 'FAILED', or 'bit errors' lines):"
grep -E "(PASS|FAIL|errors|TIMEOUT|rx_decoded|rx_done|pass_flag|frame_start|simulation finished)" xsim.log | head -50
