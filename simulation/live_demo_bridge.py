#!/usr/bin/env python3
"""
live_demo_bridge.py — 板子 EMIO → WebSocket → live_demo.html

环境变量配置 (与 demo.py 协同):
    BOARD_HOST    板子 IP        (default 192.168.2.1)
    BOARD_USER    SSH user      (default root)
    BOARD_PASS    SSH password  (default analog)
    EMIO_ADDR     EMIO 寄存器  (default 0xE000A068)
    WS_PORT       WebSocket port (default 8765)
    POLL_INTERVAL 秒          (default 0.10)
    MOCK=1        不连板子,伪造数据 (调试 HTML 用)

依赖:
    pip install --break-system-packages websockets
    sshpass (system)  — 或者预先 ssh-copy-id 设好 keypair

直接调用:
    python3 live_demo_bridge.py
推荐使用 demo.py 启动 (一键 HTTP + WS + 浏览器):
    python3 demo.py
"""
import asyncio
import json
import os
import shutil
import subprocess
import sys

# ---------------------------------------------------------------------------
BOARD_HOST    = os.environ.get("BOARD_HOST", "192.168.2.1")
BOARD_USER    = os.environ.get("BOARD_USER", "root")
BOARD_PASS    = os.environ.get("BOARD_PASS", "analog")
EMIO_ADDR     = os.environ.get("EMIO_ADDR", "0xE000A068")
EXPECTED_HI30 = int(os.environ.get("EXPECTED_HI30", "0x03C3C3C3"), 16) & 0x3FFFFFFF
WS_PORT       = int(os.environ.get("WS_PORT", "8765"))
POLL_INTERVAL = float(os.environ.get("POLL_INTERVAL", "0.10"))
MOCK          = os.environ.get("MOCK", "") == "1"

HAS_SSHPASS   = shutil.which("sshpass") is not None

# paramiko fallback (works on Windows where sshpass is unavailable)
_paramiko = None
_paramiko_client = None
try:
    import paramiko as _paramiko
except ImportError:
    pass


def emit(tag, msg):
    print(f"{tag}: {msg}", flush=True)


def _paramiko_read():
    """Persistent SSH session via paramiko — used when sshpass missing (Windows)."""
    global _paramiko_client
    if _paramiko is None:
        return None
    if _paramiko_client is None:
        try:
            c = _paramiko.SSHClient()
            c.set_missing_host_key_policy(_paramiko.AutoAddPolicy())
            c.connect(BOARD_HOST, username=BOARD_USER, password=BOARD_PASS,
                      timeout=3, banner_timeout=3, auth_timeout=3,
                      allow_agent=False, look_for_keys=False)
            _paramiko_client = c
        except Exception as e:
            emit("warn", f"paramiko connect failed: {e}")
            return None
    try:
        _, stdout, _ = _paramiko_client.exec_command(
            f"busybox devmem {EMIO_ADDR}", timeout=2)
        return stdout.read().decode("ascii", "ignore").strip()
    except Exception as e:
        emit("warn", f"paramiko exec failed, reconnecting: {e}")
        try: _paramiko_client.close()
        except: pass
        _paramiko_client = None
        return None


# ---------------------------------------------------------------------------
def read_emio_once():
    """Returns (emio_int, rx_done, pass_flag, hi30, errors) or None."""
    if MOCK:
        # rotate through realistic states
        import random, time
        t = time.time()
        rx_done = 1 if (t % 4) > 0.5 else 0
        pass_flag = 0
        hi30 = 0x01607060
        # add a little flapping
        if random.random() < 0.05: hi30 ^= (1 << random.randint(0, 29))
        errors = bin((hi30 ^ EXPECTED_HI30) & 0x3FFFFFFF).count("1")
        emio = (hi30 << 2) | (rx_done << 1) | pass_flag
        return emio, rx_done, pass_flag, hi30, errors

    s = None
    if HAS_SSHPASS:
        cmd = ["sshpass", "-p", BOARD_PASS, "ssh",
               "-o", "StrictHostKeyChecking=no",
               "-o", "ConnectTimeout=2",
               "-o", "BatchMode=no",
               f"{BOARD_USER}@{BOARD_HOST}",
               f"busybox devmem {EMIO_ADDR}"]
        try:
            r = subprocess.run(cmd, capture_output=True, text=True, timeout=3)
            s = r.stdout.strip()
        except (FileNotFoundError, subprocess.TimeoutExpired):
            pass
    elif _paramiko is not None:
        # Windows: use paramiko persistent session (no sshpass needed)
        s = _paramiko_read()
        if s is not None:
            s = s.strip()
    else:
        cmd = ["ssh",
               "-o", "StrictHostKeyChecking=no",
               "-o", "ConnectTimeout=2",
               "-o", "BatchMode=yes",          # require keypair (no password prompt)
               f"{BOARD_USER}@{BOARD_HOST}",
               f"busybox devmem {EMIO_ADDR}"]
        try:
            r = subprocess.run(cmd, capture_output=True, text=True, timeout=3)
            s = r.stdout.strip()
        except (FileNotFoundError, subprocess.TimeoutExpired):
            pass

    if s is None:
        return None
    if not s.startswith("0x"):
        return None
    try:
        v = int(s, 16) & 0xFFFFFFFF
    except ValueError:
        return None
    rx_done   = (v >> 1) & 1
    pass_flag = (v >> 0) & 1
    hi30      = (v >> 2) & 0x3FFFFFFF
    errors    = bin((hi30 ^ EXPECTED_HI30) & 0x3FFFFFFF).count("1")
    return v, rx_done, pass_flag, hi30, errors


# ---------------------------------------------------------------------------
async def board_poller(broadcast):
    if MOCK:
        emit("mode", "MOCK — using synthetic data")
    else:
        emit("target", f"{BOARD_USER}@{BOARD_HOST} (EMIO {EMIO_ADDR})")
        if HAS_SSHPASS:
            emit("auth", "sshpass (Linux/Mac)")
        elif _paramiko is not None:
            emit("auth", "paramiko (cross-platform, password-based)")
        else:
            emit("auth", "ssh keypair (BatchMode=yes) — install paramiko or sshpass for password auth")
    last = (None, None)
    seq = 0
    fails = 0
    while True:
        r = read_emio_once()
        if r is None:
            fails += 1
            if fails == 1:
                hint = ""
                if not HAS_SSHPASS and not MOCK:
                    hint = (" — install sshpass OR run "
                            "ssh-copy-id root@" + BOARD_HOST +
                            " OR set MOCK=1 to test the HTML")
                await broadcast(kind="warn",
                                line=f"[bridge] EMIO read failed{hint}")
            await asyncio.sleep(2.0)
            continue
        if fails > 0:
            await broadcast(kind="ok", line=f"[bridge] reconnected after {fails} retry")
            fails = 0
        v, rx_done, pass_flag, hi30, errors = r
        await broadcast(emio=f"0x{v:08X}",
                        rx_decoded=f"0x{hi30:08X}",
                        rx_done=rx_done, pass_flag=pass_flag,
                        errors=errors)
        state = (rx_done, pass_flag)
        if state != last or seq % 30 == 0:
            await broadcast(kind="hex",
                            line=f"emio=0x{v:08X}  rx_done={rx_done}  "
                                 f"pass_flag={pass_flag}  hi30=0x{hi30:08X}  XOR={errors} bit")
            last = state
        seq += 1
        await asyncio.sleep(POLL_INTERVAL)


# ---------------------------------------------------------------------------
async def run_ws():
    try:
        import websockets
    except ImportError:
        emit("error", "需要 'websockets' 包: pip install --break-system-packages websockets")
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
        emit("client", f"+1 ({len(clients)} total) {ws.remote_address}")
        try:
            await broadcast(kind="ok",
                            line=f"[bridge] client connected — pushing EMIO {EMIO_ADDR}")
            await ws.wait_closed()
        finally:
            clients.discard(ws)
            emit("client", f"-1 ({len(clients)} total)")

    emit("ws", f"listening on ws://0.0.0.0:{WS_PORT}")
    async with websockets.serve(handler, "0.0.0.0", WS_PORT):
        await board_poller(broadcast)


# ---------------------------------------------------------------------------
if __name__ == "__main__":
    try:
        asyncio.run(run_ws())
    except KeyboardInterrupt:
        emit("stop", "bye")
