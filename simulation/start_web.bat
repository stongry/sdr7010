@echo off
REM SDR7010 OFDM+LDPC 一键 Web 演示启动器 (Windows)
REM
REM 双击即:
REM   1. 装 pyserial + websockets + paramiko (已装跳过)
REM   2. 通过 RNDIS SSH 烧 PL bitstream (~5 秒, 如果板子已连)
REM   3. 启动 demo (HTTP :8000 + WebSocket :8765, 串口模式)
REM   4. 自动打开默认浏览器到 http://localhost:8000/live_demo.html
REM
REM Ctrl+C 退出 demo

setlocal
cd /d "%~dp0"
title SDR7010 OFDM+LDPC Live Demo
chcp 65001 > nul

echo.
echo ================================================================
echo   SDR7010 OFDM+LDPC Live Web Demo
echo   xc7z010clg400-2 + AD9363 ^| OFDM 64-FFT + LDPC (1024,512)
echo ================================================================
echo.

REM ---------------------------------------------------------------
REM Step 1: 检查 + 装依赖
REM ---------------------------------------------------------------
where python >nul 2>nul
if errorlevel 1 (
    echo [error] 没找到 python. 请装 Python 3.8+ 然后加进 PATH
    echo         https://www.python.org/downloads/
    pause
    exit /b 1
)

python -c "import serial, websockets, paramiko" >nul 2>&1
if errorlevel 1 (
    echo [1/3] 安装依赖 pyserial + websockets + paramiko ...
    python -m pip install --quiet --user pyserial websockets paramiko
    if errorlevel 1 (
        echo [warn] pip 装包有问题, 继续试...
    )
)

REM ---------------------------------------------------------------
REM Step 2: 烧 PL bitstream (秒级, 失败也继续)
REM ---------------------------------------------------------------
echo [2/3] 烧 PL bitstream (paramiko + ssh-rsa legacy) ...
echo.
python -u load_pl_legacy_ssh.py
if errorlevel 1 (
    echo.
    echo [warn] PL 烧录失败. 可能原因:
    echo        - 板子没插到 USB-C
    echo        - RNDIS driver 没装好 (没出现 192.168.2.10 接口)
    echo        - 板子刚上电 dropbear 还没起 (等 15 秒重试)
    echo        demo 还会启动, 但 EMIO 显示的是默认 PL 不是 ofdm_ldpc
    echo.
    timeout /t 3 >nul
)

REM ---------------------------------------------------------------
REM Step 3: 启动 demo + 自动开浏览器
REM ---------------------------------------------------------------
echo.
echo ================================================================
echo  [3/3] 启动 demo (HTTP :8000 + WebSocket :8765 + serial bridge)
echo  浏览器会自动打开 http://localhost:8000/live_demo.html
echo  按 Ctrl+C 退出
echo ================================================================
echo.

python -u demo.py --serial

endlocal
