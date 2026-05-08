#!/usr/bin/env bash
# SDR7010 OFDM+LDPC 一键演示启动器 — bash 包装层
#
# 用法:
#   ./demo.sh                    # 自动检测板子
#   ./demo.sh --replay           # 强制 REPLAY
#   ./demo.sh --live             # 强制 LIVE
#   ./demo.sh --board 10.0.0.5
#   BOARD_HOST=10.0.0.5 ./demo.sh
#
set -e
cd "$(dirname "$0")"

if ! command -v python3 >/dev/null 2>&1; then
    echo "需要 python3 (≥3.8)" >&2
    exit 1
fi

exec python3 demo.py "$@"
