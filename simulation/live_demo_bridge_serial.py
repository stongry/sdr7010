#!/usr/bin/env python3
"""
live_demo_bridge_serial.py — UART (COMx / /dev/ttyACMx) 直连板子读 EMIO

不依赖任何网络驱动 (RNDIS / iio-usbd 都不需要)。Pluto/LDSDR 通过 USB CDC ACM
暴露 Linux console 串口,本脚本登录后周期跑 `busybox devmem` 读 EMIO,然后
WebSocket 推送同样的 JSON 协议给 live_demo.html。

环境变量:
    SERIAL_PORT     COM3   (Linux: /dev/ttyACM0)
    SERIAL_BAUD     115200
    BOARD_USER      root
    BOARD_PASS      analog
    EMIO_ADDR       0xE000A068
    WS_PORT         8765
    POLL_INTERVAL   0.5

依赖:
    pip install pyserial websockets

用法:
    python live_demo_bridge_serial.py            # use SERIAL_PORT env
    SERIAL_PORT=COM4 python live_demo_bridge_serial.py
    python live_demo_bridge_serial.py --probe   # auto-detect Pluto serial port
"""
import asyncio
import json
import os
import re
import sys
import time

DEFAULT_PORT = os.environ.get("SERIAL_PORT", "COM3" if sys.platform == "win32" else "/dev/ttyACM0")
DEFAULT_BAUD = int(os.environ.get("SERIAL_BAUD", "115200"))
BOARD_USER   = os.environ.get("BOARD_USER", "root")
BOARD_PASS   = os.environ.get("BOARD_PASS", "analog")
EMIO_ADDR    = os.environ.get("EMIO_ADDR", "0xE000A068")
EXPECTED_HI30 = int(os.environ.get("EXPECTED_HI30", "0x03C3C3C3"), 16) & 0x3FFFFFFF
WS_PORT      = int(os.environ.get("WS_PORT", "8765"))
POLL_INTERVAL = float(os.environ.get("POLL_INTERVAL", "0.5"))


def emit(tag, msg):
    print(f"{tag}: {msg}", flush=True)


# ---------------------------------------------------------------------------
def find_pluto_serial():
    """Auto-detect first port whose USB VID = 0x0456 (ADI)."""
    try:
        from serial.tools import list_ports
    except ImportError:
        return None
    for p in list_ports.comports():
        if p.vid == 0x0456 or "Pluto" in (p.description or "") or "Pluto" in (p.manufacturer or ""):
            return p.device
    return None


# ---------------------------------------------------------------------------
class SerialSession:
    """Persistent 'login + run command' helper over UART."""

    def __init__(self, port, baud=115200):
        self.port = port
        self.baud = baud
        self.ser = None

    def open(self):
        import serial
        self.ser = serial.Serial(self.port, self.baud, timeout=0.5,
                                 rtscts=False, dsrdtr=False)
        self.ser.reset_input_buffer()
        # nudge a newline to wake the prompt
        self.ser.write(b"\r\n")
        time.sleep(0.3)
        out = self._read_for(0.5)
        # Are we already at root prompt?
        if re.search(r"#\s*$", out, re.M):
            return
        # Login flow
        if "login:" in out or "login" in out.lower():
            self.ser.write((BOARD_USER + "\r\n").encode())
            time.sleep(0.5)
            self._read_for(0.6)
        # password prompt
        self.ser.write((BOARD_PASS + "\r\n").encode())
        time.sleep(1.0)
        out = self._read_for(1.0)
        if "incorrect" in out.lower() or "fail" in out.lower():
            raise RuntimeError("login failed: " + out[-200:])

    def _read_for(self, secs):
        end = time.time() + secs
        buf = b""
        while time.time() < end:
            n = self.ser.in_waiting
            if n:
                buf += self.ser.read(n)
            else:
                time.sleep(0.05)
        return buf.decode("utf-8", "replace")

    def cmd(self, line, timeout=1.5):
        self.ser.reset_input_buffer()
        marker = f"==MARK_{int(time.time()*1000)}=="
        full = f"{line}; echo {marker}\r\n"
        self.ser.write(full.encode())
        end = time.time() + timeout
        out = ""
        while time.time() < end:
            n = self.ser.in_waiting
            if n:
                out += self.ser.read(n).decode("utf-8", "replace")
                if marker in out:
                    break
            else:
                time.sleep(0.03)
        # extract between echo of cmd and marker
        # remove marker echo (`echo MARK`) and the marker output line
        lines = out.replace("\r", "").split("\n")
        # first line is cmd echo, last with marker is end
        for i, ln in enumerate(lines):
            if marker in ln and "echo" not in ln:
                # the marker line itself
                return "\n".join(lines[1:i]).strip()
        return out.strip()

    def close(self):
        try:
            if self.ser: self.ser.close()
        except: pass


# ---------------------------------------------------------------------------
def parse_emio(s):
    m = re.search(r"0x([0-9A-Fa-f]+)", s)
    if not m: return None
    try:
        v = int(m.group(1), 16) & 0xFFFFFFFF
    except ValueError:
        return None
    rx_done   = (v >> 1) & 1
    pass_flag = (v >> 0) & 1
    hi30      = (v >> 2) & 0x3FFFFFFF
    errors    = bin((hi30 ^ EXPECTED_HI30) & 0x3FFFFFFF).count("1")
    return v, rx_done, pass_flag, hi30, errors


# ---------------------------------------------------------------------------
async def board_poller(broadcast, port):
    sess = SerialSession(port, DEFAULT_BAUD)
    while True:
        try:
            emit("serial", f"opening {port} @ {DEFAULT_BAUD}")
            sess.open()
            emit("serial", "logged in, polling EMIO")
            await broadcast(kind="ok",
                            line=f"[bridge] serial {port} login OK, polling EMIO {EMIO_ADDR}")
            break
        except Exception as e:
            emit("warn", f"serial open/login failed: {e}, retry in 3s")
            await broadcast(kind="warn", line=f"[bridge] serial {port}: {e}")
            sess.close()
            await asyncio.sleep(3)

    last = (None, None)
    seq = 0
    while True:
        try:
            out = sess.cmd(f"busybox devmem {EMIO_ADDR}")
            r = parse_emio(out)
        except Exception as e:
            emit("warn", f"serial cmd failed: {e}, reconnecting")
            await broadcast(kind="warn", line=f"[bridge] serial cmd error: {e}")
            sess.close()
            await asyncio.sleep(2)
            try:
                sess = SerialSession(port, DEFAULT_BAUD); sess.open()
            except Exception as e2:
                emit("warn", f"reconnect failed: {e2}")
                await asyncio.sleep(3)
            continue
        if r is None:
            await broadcast(kind="warn",
                            line=f"[bridge] failed to parse EMIO: {out[:80]}")
            await asyncio.sleep(POLL_INTERVAL)
            continue
        v, rx_done, pass_flag, hi30, errors = r
        await broadcast(emio=f"0x{v:08X}",
                        rx_decoded=f"0x{hi30:08X}",
                        rx_done=rx_done, pass_flag=pass_flag,
                        errors=errors)
        state = (rx_done, pass_flag)
        if state != last or seq % 10 == 0:
            await broadcast(kind="hex",
                            line=f"emio=0x{v:08X}  rx_done={rx_done}  "
                                 f"pass_flag={pass_flag}  hi30=0x{hi30:08X}  XOR={errors} bit")
            last = state
        seq += 1
        await asyncio.sleep(POLL_INTERVAL)


# ---------------------------------------------------------------------------
async def run_ws(port):
    try:
        import websockets
    except ImportError:
        emit("error", "需要 'websockets' 包: pip install websockets")
        sys.exit(1)
    try:
        import serial
    except ImportError:
        emit("error", "需要 'pyserial' 包: pip install pyserial")
        sys.exit(1)

    clients = set()

    async def broadcast(**msg):
        if not clients:
            return
        data = json.dumps(msg)
        dead = []
        for c in clients:
            try:
                await c.send(data)
            except Exception:
                dead.append(c)
        for c in dead:
            clients.discard(c)

    async def handler(ws):
        clients.add(ws)
        emit("client", f"+1 ({len(clients)} total)")
        try:
            await broadcast(kind="ok",
                            line=f"[bridge] client connected — UART {port}")
            await ws.wait_closed()
        finally:
            clients.discard(ws)

    emit("ws", f"listening on ws://0.0.0.0:{WS_PORT}")
    async with websockets.serve(handler, "0.0.0.0", WS_PORT):
        await board_poller(broadcast, port)


# ---------------------------------------------------------------------------
if __name__ == "__main__":
    if "--probe" in sys.argv:
        p = find_pluto_serial()
        print("Detected:", p or "(none)")
        sys.exit(0 if p else 1)

    port = DEFAULT_PORT
    if port in ("auto", ""):
        port = find_pluto_serial()
        if not port:
            emit("error", "auto-detect failed — set SERIAL_PORT env (e.g. COM3)")
            sys.exit(1)
        emit("info", f"auto-detected port: {port}")

    try:
        asyncio.run(run_ws(port))
    except KeyboardInterrupt:
        emit("stop", "bye")
