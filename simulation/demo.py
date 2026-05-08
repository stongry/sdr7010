#!/usr/bin/env python3
"""
demo.py  —  SDR7010 OFDM+LDPC 一键演示启动器

功能 (无外部依赖, 标准库纯 Python):
  · 启动本地 HTTP server (静态文件)
  · 自动检测板子是否在线 (TCP probe 22)
  · 板子在线 → 后台拉起 live_demo_bridge.py (WebSocket → 实时 EMIO)
  · 板子不在线 → REPLAY 模式 (HTML 内嵌真实启动序列)
  · 自动打开浏览器到 http://localhost:8000/live_demo.html
  · Ctrl+C 一键清理 (bridge + http server)

用法:
    python3 demo.py                     # 自动检测
    python3 demo.py --replay            # 强制 REPLAY (不连板子)
    python3 demo.py --live              # 强制 LIVE (板子必须在线)
    python3 demo.py --board 192.168.3.140 --port 8080
    BOARD_HOST=10.0.0.5 python3 demo.py
"""
import argparse
import http.server
import os
import signal
import socket
import socketserver
import subprocess
import sys
import threading
import time
import webbrowser
from pathlib import Path

HERE = Path(__file__).resolve().parent
DEFAULT_BOARD = os.environ.get("BOARD_HOST", "192.168.2.1")
DEFAULT_HTTP_PORT = 8000
DEFAULT_WS_PORT = 8765


# ---------------------------------------------------------------------------
def color(s, c):
    if not sys.stdout.isatty():
        return s
    codes = {"green": 32, "amber": 33, "red": 31, "cyan": 36, "grey": 90}
    return f"\x1b[{codes[c]}m{s}\x1b[0m"


def log(tag, msg, c="cyan"):
    print(f"{color('[demo]', c)} {color(tag, c)} {msg}")


# ---------------------------------------------------------------------------
def check_board(host, port=22, timeout=1.5):
    try:
        with socket.create_connection((host, port), timeout=timeout):
            return True
    except (OSError, socket.timeout):
        return False


def find_free_port(start):
    for p in range(start, start + 30):
        with socket.socket() as s:
            try:
                s.bind(("127.0.0.1", p))
                return p
            except OSError:
                continue
    return None


# ---------------------------------------------------------------------------
class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass

    def end_headers(self):
        # avoid browser cache during demo iterations
        self.send_header("Cache-Control", "no-store")
        super().end_headers()


def serve_http(port, ready):
    os.chdir(HERE)
    with socketserver.ThreadingTCPServer(("", port), QuietHandler) as srv:
        srv.allow_reuse_address = True
        ready.set()
        srv.serve_forever()


# ---------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--board", default=DEFAULT_BOARD,
                    help=f"board host (default: {DEFAULT_BOARD})")
    ap.add_argument("--port", type=int, default=DEFAULT_HTTP_PORT,
                    help=f"HTTP port (default: {DEFAULT_HTTP_PORT})")
    ap.add_argument("--ws-port", type=int, default=DEFAULT_WS_PORT,
                    help=f"WebSocket port (default: {DEFAULT_WS_PORT})")
    ap.add_argument("--live", action="store_true",
                    help="force LIVE mode (board must be online)")
    ap.add_argument("--replay", action="store_true",
                    help="force REPLAY mode (skip board)")
    ap.add_argument("--serial", action="store_true",
                    help="use UART/COMx bridge (live_demo_bridge_serial.py) "
                         "— for Windows or when RNDIS unavailable")
    ap.add_argument("--no-browser", action="store_true",
                    help="do not auto-open browser")
    args = ap.parse_args()

    if args.live and args.replay:
        ap.error("--live and --replay are mutually exclusive")

    log("init", f"working dir: {HERE}")

    # detect board
    online = False
    serial_mode = args.serial
    if args.replay:
        log("mode", "REPLAY (forced)", "amber")
    elif args.serial:
        log("mode", "LIVE via serial UART", "green")
        online = True   # bridge will probe COM port itself
    elif args.live:
        log("probe", f"checking {args.board}:22 ...")
        online = check_board(args.board)
        if not online:
            log("error", f"--live required but {args.board} unreachable", "red")
            log("hint", "try --serial for UART bridge, or --replay", "amber")
            sys.exit(2)
        log("mode", "LIVE (forced)", "green")
    else:
        log("probe", f"checking {args.board}:22 ...")
        online = check_board(args.board)
        log("mode", "LIVE — board online" if online else
                    "REPLAY — board offline", "green" if online else "amber")

    # find free HTTP port
    http_port = args.port
    if not find_free_port(http_port):
        log("error", f"port {http_port} unavailable", "red"); sys.exit(3)

    # start HTTP server
    ready = threading.Event()
    t = threading.Thread(target=serve_http, args=(http_port, ready), daemon=True)
    t.start()
    if not ready.wait(2.0):
        log("error", "HTTP server failed to start", "red"); sys.exit(4)
    log("http", f"http://localhost:{http_port}/live_demo.html", "green")

    # start bridge if live
    bridge_proc = None
    if online:
        env = os.environ.copy()
        env["BOARD_HOST"] = args.board
        env["WS_PORT"] = str(args.ws_port)
        bridge_script = "live_demo_bridge_serial.py" if serial_mode else "live_demo_bridge.py"
        bridge_proc = subprocess.Popen(
            [sys.executable, str(HERE / bridge_script)],
            env=env,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            bufsize=1, text=True)

        # forward bridge output prefixed
        def pump():
            for line in bridge_proc.stdout:
                print(color("[bridge]", "grey"), line.rstrip())
        threading.Thread(target=pump, daemon=True).start()
        time.sleep(0.4)
        log("ws", f"ws://localhost:{args.ws_port}  ←  EMIO {args.board}", "green")

    # open browser
    url = f"http://localhost:{http_port}/live_demo.html"
    if not args.no_browser:
        log("open", url, "cyan")
        try:
            webbrowser.open(url)
        except Exception:
            pass
    else:
        log("ready", url, "cyan")

    # wait for Ctrl+C
    log("info", "Ctrl+C to stop", "grey")
    try:
        while True:
            time.sleep(1.0)
            if bridge_proc and bridge_proc.poll() is not None:
                log("warn", "bridge exited unexpectedly — switching to REPLAY in browser",
                    "amber")
                bridge_proc = None
    except KeyboardInterrupt:
        print()
        log("stop", "cleaning up ...", "amber")
        if bridge_proc:
            bridge_proc.terminate()
            try:
                bridge_proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                bridge_proc.kill()
        log("bye", "✓", "green")


if __name__ == "__main__":
    main()
