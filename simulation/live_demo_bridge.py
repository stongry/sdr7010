#!/usr/bin/env python3
"""
live_demo_bridge.py — SSH 板子读 EMIO + WebSocket 推送给 live_demo.html

依赖:
    pip install websockets paramiko    (或 pip install --break-system-packages ...)

运行:
    1. 板子上电, ssh root@192.168.2.1 能通 (或自定义 BOARD_HOST/USER/PASS)
    2. python3 live_demo_bridge.py
    3. 浏览器打开 live_demo.html?live  → 自动连 ws://localhost:8765

WS message format (JSON):
    {
      "kind": "info|cmd|hex|ok|warn",     # 给终端的颜色
      "line": "...",                         # 可选, 一行文本
      "emio": "0x60B0306D",                  # 可选, 当前 EMIO bank 2 hex
      "rx_done": 0|1,                         # 可选
      "pass_flag": 0|1,                       # 可选
      "errors": <int>                          # 可选, XOR 比对错位
    }
"""
import asyncio, json, time, subprocess, sys

# ============================================================
# Configuration — adjust to your setup
# ============================================================
BOARD_HOST    = "192.168.2.1"          # USB-C CDC ethernet on Pluto/LDSDR
BOARD_USER    = "root"
BOARD_PASS    = "analog"               # default Pluto password
EMIO_ADDR     = "0xE000A068"           # bank 2, where rx_done/pass_flag/rx_decoded[31:2] map
EXPECTED_HI30 = 0x03C3C3C3             # TEST_BITS[31:2]; XOR target

POLL_INTERVAL_S = 0.10                 # 10 Hz EMIO polling
WS_PORT         = 8765

# ============================================================
# SSH read of EMIO via sshpass (no extra Python deps)
# ============================================================
def read_emio_once():
    """Returns (raw_int, rx_done, pass_flag, hi30, errors) or None on fail."""
    cmd = ["sshpass", "-p", BOARD_PASS, "ssh",
           "-o", "StrictHostKeyChecking=no",
           "-o", "ConnectTimeout=2",
           f"{BOARD_USER}@{BOARD_HOST}",
           f"busybox devmem {EMIO_ADDR}"]
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=3)
        s = out.stdout.strip()
        if not s.startswith("0x"):
            return None
        v = int(s, 16) & 0xFFFFFFFF
    except Exception:
        return None
    rx_done   = (v >> 1) & 1
    pass_flag = (v >> 0) & 1
    hi30      = (v >> 2) & 0x3FFFFFFF
    errors    = bin((hi30 ^ EXPECTED_HI30) & 0x3FFFFFFF).count("1")
    return v, rx_done, pass_flag, hi30, errors


async def board_poller(send):
    last_state = (None, None)
    await send(kind="info", line=f"[bridge] connecting to {BOARD_USER}@{BOARD_HOST} via ssh…")
    seq = 0
    while True:
        r = read_emio_once()
        if r is None:
            await send(kind="warn",
                       line=f"[bridge] EMIO read failed (no ssh? wrong password? board offline?)")
            await asyncio.sleep(2.0)
            continue
        v, rx_done, pass_flag, hi30, errors = r
        await send(emio=f"0x{v:08X}",
                   rx_done=rx_done, pass_flag=pass_flag, errors=errors)
        # only emit a terminal line when something interesting changes
        state = (rx_done, pass_flag)
        if state != last_state or seq % 20 == 0:
            await send(kind="hex",
                       line=f"emio=0x{v:08X}  rx_done={rx_done}  pass_flag={pass_flag}  "
                            f"hi30=0x{hi30:08X}  XOR={errors} bit")
            last_state = state
        seq += 1
        await asyncio.sleep(POLL_INTERVAL_S)


# ============================================================
# WebSocket server
# ============================================================
async def run_ws():
    try:
        import websockets
    except ImportError:
        print("Install: pip install websockets   (or --break-system-packages)")
        sys.exit(1)

    clients = set()

    async def send(**msg):
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
        print(f"[ws] client +{len(clients)} connected from {ws.remote_address}")
        try:
            await ws.wait_closed()
        finally:
            clients.discard(ws)
            print(f"[ws] client -{len(clients)} disconnected")

    print(f"[ws] listening on ws://0.0.0.0:{WS_PORT}")
    print(f"     open live_demo.html?live in browser to attach")
    async with websockets.serve(handler, "0.0.0.0", WS_PORT):
        await board_poller(send)


if __name__ == "__main__":
    try:
        asyncio.run(run_ws())
    except KeyboardInterrupt:
        print("\n[bridge] bye")
