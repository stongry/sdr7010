@echo off
REM SDR7010 一键 demo (UART 串口模式) — Windows 双击即用
REM 自动检测板子 COM 端口, 登录 root, 周期读 EMIO 推送 WebSocket
REM 浏览器自动打开 → 真实板子数据驱动面板

cd /d "%~dp0"
title SDR7010 Live Demo (UART)

where python >nul 2>nul
if errorlevel 1 (
    echo [demo] 没找到 python.  请先装 Python 3.8+
    pause
    exit /b 1
)

echo [demo] 检查依赖...
python -c "import serial, websockets" 2>nul || (
    echo [demo] 装 pyserial + websockets...
    python -m pip install --quiet --user pyserial websockets
)

python -u demo.py --serial %*
