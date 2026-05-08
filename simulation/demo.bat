@echo off
REM SDR7010 OFDM+LDPC 一键演示启动器 — Windows 入口
REM
REM 用法:
REM   demo.bat                    自动检测板子
REM   demo.bat --replay           强制 REPLAY
REM   demo.bat --live             强制 LIVE
REM   demo.bat --board 192.168.2.1
REM
REM 前置条件:
REM   1. Python 3.8+ 在 PATH 里
REM   2. 板子驱动装好 (PlutoSDR-M2k-USB-Drivers.exe), 192.168.2.x 网段出现
REM   3. (可选) pip install websockets paramiko    LIVE 模式需要

cd /d "%~dp0"

where python >nul 2>nul
if errorlevel 1 (
    where py >nul 2>nul
    if errorlevel 1 (
        echo [demo.bat] 没找到 python — 请先装 Python 3.8+ 并加到 PATH
        echo            https://www.python.org/downloads/
        pause
        exit /b 1
    )
    py demo.py %*
) else (
    python demo.py %*
)
