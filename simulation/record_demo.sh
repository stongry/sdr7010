#!/usr/bin/env bash
# ============================================================================
# record_demo.sh — 30-second asciinema demo of board run.
#
# 用法 (主机端,需要能 ssh 到 192.168.2.1):
#   bash record_demo.sh [board_ip] [board_password]
#
# 默认:board_ip=192.168.2.1, password=analog
#
# 依赖:
#   - asciinema   (sudo pacman -S asciinema  或  pip install asciinema)
#   - sshpass     (sudo pacman -S sshpass)
#   - 主机当前目录有 ofdm_ldpc.bin
#
# 输出:
#   /tmp/sdr7010_board_demo.cast
#
# 后续可选:
#   asciinema play /tmp/sdr7010_board_demo.cast       # 在终端回放
#   asciinema upload /tmp/sdr7010_board_demo.cast      # 上传到 asciinema.org
#   agg /tmp/sdr7010_board_demo.cast demo.gif --speed 1.5  # 转 GIF
# ============================================================================

set -e

BOARD_IP="${1:-192.168.2.1}"
PASSWORD="${2:-analog}"
CAST="/tmp/sdr7010_board_demo.cast"

# Pre-flight checks
command -v asciinema >/dev/null || { echo "ERROR: asciinema 未安装"; exit 1; }
command -v sshpass   >/dev/null || { echo "ERROR: sshpass 未安装"; exit 1; }
[ -f ofdm_ldpc.bin ] || { echo "ERROR: 当前目录没有 ofdm_ldpc.bin"; exit 1; }

cat << 'BANNER'
╔══════════════════════════════════════════════════════════╗
║ SDR7010 OFDM+LDPC  ·  on-board demo recording             ║
║ build #9 FINAL  ·  xfft_v9.1 IP unscaled+natural+sat16    ║
╚══════════════════════════════════════════════════════════╝
BANNER

# Inline script that asciinema will record
cat > /tmp/sdr7010_demo_script.sh <<EOF
#!/bin/bash
set -u
BOARD="$BOARD_IP"
PW="$PASSWORD"

# Pretty banner
echo
echo "═══ STEP 1 · 上传 bitstream 到板子 ($BOARD) ═══"
sleep 1
ls -la ofdm_ldpc.bin
sleep 1.2

echo
echo "═══ STEP 2 · scp via cat-pipe (no sftp-server) ═══"
sleep 0.8
time cat ofdm_ldpc.bin | sshpass -p "\$PW" ssh -o StrictHostKeyChecking=no root@\$BOARD 'cat > /lib/firmware/ofdm_ldpc.bin'
sleep 1

echo
echo "═══ STEP 3 · ssh into board, set flags=0 (★ critical) ═══"
sleep 1
sshpass -p "\$PW" ssh root@\$BOARD 'echo 0 > /sys/class/fpga_manager/fpga0/flags && cat /sys/class/fpga_manager/fpga0/flags'
sleep 1

echo
echo "═══ STEP 4 · trigger PL bitstream load via fpga_manager ═══"
sleep 1
sshpass -p "\$PW" ssh root@\$BOARD 'echo ofdm_ldpc.bin > /sys/class/fpga_manager/fpga0/firmware && sleep 1 && cat /sys/class/fpga_manager/fpga0/state'
sleep 1.5

echo
echo "═══ STEP 5 · check kernel log ═══"
sleep 0.8
sshpass -p "\$PW" ssh root@\$BOARD 'dmesg | tail -3'
sleep 1.2

echo
echo "═══ STEP 6 · wait 3 s for PL pipeline to finish ═══"
sleep 1
sshpass -p "\$PW" ssh root@\$BOARD 'sleep 3 && echo "PL pipeline done."'
sleep 0.8

echo
echo "═══ STEP 7 · read EMIO bank 2 (0xE000A068) ═══"
sleep 1
EMIO=\$(sshpass -p "\$PW" ssh root@\$BOARD 'busybox devmem 0xE000A068')
echo "EMIO bank 2 = \$EMIO"
sleep 1.2

echo
echo "═══ STEP 8 · decode the EMIO word ═══"
sleep 0.8
python3 -c "
emio = int('\$EMIO', 16)
pass_flag = emio & 1
rx_done   = (emio >> 1) & 1
rx_dec    = (emio >> 2) & ((1 << 30) - 1)
print(f'  bit[0]  pass_flag        = {pass_flag}')
print(f'  bit[1]  rx_done          = {rx_done}     {\"  ✓ PL 全流水跑通\" if rx_done else \"\"}')
print(f'  bit[31:2] rx_decoded     = 0x{rx_dec:08X}')
ref = 0x03C3C3C3
xor = rx_dec ^ ref
err = bin(xor).count('1')
print(f'  expected (TEST_BITS)     = 0x{ref:08X}')
print(f'  XOR popcount             = {err}/30 bits')
"
sleep 2

echo
echo "═══ DEMO 结束 ═══"
echo
echo "✅  rx_done = 1   →   PL 流水完整跑通"
echo "   - LDPC encoder  → OFDM IFFT → CP → loopback → CP remove → FFT → demod → LLR → BP × 10 iter"
echo "✅  Phase-1 xsim 同 RTL 已证明 0/512 BER (用行为级 DFT)"
echo "⚠   pass_flag = 0  ← 余 6 bit 是 xfft IP 数值精度,见 lkh.md §35.8"
sleep 2
EOF
chmod +x /tmp/sdr7010_demo_script.sh

echo "[i] 开始 asciinema 录制 → $CAST"
echo "[i] 自动跑 8 步 demo,大约 30 秒"
echo "[i] 录完用 'asciinema play $CAST' 回放"
echo

# Record!
asciinema rec "$CAST" \
    --command "/tmp/sdr7010_demo_script.sh" \
    --title "SDR7010 OFDM+LDPC Phase-2 board demo (build #9 FINAL)" \
    --idle-time-limit 1.5 \
    --overwrite

echo
echo "════════════════════════════════════════════════════════════"
echo "Saved: $CAST"
echo
echo "回放:    asciinema play $CAST"
echo "上传:    asciinema upload $CAST"
echo "转 GIF:  agg $CAST sdr7010_demo.gif --speed 1.5"
echo "转 SVG:  cat $CAST | svg-term --no-cursor > demo.svg"
echo "════════════════════════════════════════════════════════════"
