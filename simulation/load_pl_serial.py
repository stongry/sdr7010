#!/usr/bin/env python3
"""
windows_load_pl.py — Windows 现场烧录 PL bitstream (无需 RNDIS)

通过 COM3 (Pluto USB CDC ACM) 直接传输 ofdm_ldpc.bin 到板子内存,
跑 fpga_manager 加载,验证 EMIO,然后释放 COM3 给 demo bridge。

用法:
    python windows_load_pl.py
    python windows_load_pl.py --port COM3 --bin C:/sdr7010/ofdm_ldpc.bin

环境变量 (与其他 demo 工具一致):
    SERIAL_PORT       默认 auto-detect (VID=0x0456 = Pluto)
    BOARD_USER        默认 root
    BOARD_PASS        默认 analog
    BIN_PATH          默认 ./ofdm_ldpc.bin 或 C:/sdr7010/ofdm_ldpc.bin

依赖:  pip install pyserial
"""
import argparse
import os
import re
import sys
import time

# Windows GBK -> UTF-8 fix (so emoji prints don't crash)
try:
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
except Exception:
    pass

try:
    import serial
    from serial.tools import list_ports
except ImportError:
    print("[err] need pyserial:  pip install pyserial")
    sys.exit(1)

DEFAULT_BIN = os.environ.get("BIN_PATH",
    "C:/sdr7010/ofdm_ldpc.bin" if sys.platform == "win32"
    else "/home/ysara/fpga_hdl/phase2_artifacts/ofdm_ldpc_FINAL.bin")
USER  = os.environ.get("BOARD_USER", "root")
PASS_ = os.environ.get("BOARD_PASS", "analog")
BAUD  = int(os.environ.get("SERIAL_BAUD", "115200"))


def emit(tag, msg, color=""):
    colors = {"ok": "\x1b[32m", "warn": "\x1b[33m", "err": "\x1b[31m",
              "cyan": "\x1b[36m", "grey": "\x1b[90m", "": ""}
    if not sys.stdout.isatty(): color = ""
    c = colors.get(color, "")
    e = "\x1b[0m" if c else ""
    print(f"{c}[{tag}]{e} {msg}", flush=True)


def find_pluto():
    for p in list_ports.comports():
        if p.vid == 0x0456:
            return p.device
    return None


def wait_for(ser, pat, timeout=8):
    end = time.time() + timeout
    buf = b""
    while time.time() < end:
        n = ser.in_waiting
        if n:
            buf += ser.read(n)
            if re.search(pat, buf.decode("utf-8", "replace")):
                return buf.decode("utf-8", "replace")
        else:
            time.sleep(0.04)
    return buf.decode("utf-8", "replace")


def login(ser):
    emit("login", "trying serial console …", "cyan")
    ser.reset_input_buffer()
    ser.write(b"\x03\r\n"); time.sleep(0.3)
    ser.reset_input_buffer()
    ser.write(b"\r\n"); time.sleep(0.3)
    out = wait_for(ser, r"(login:|#\s*$)", timeout=4)
    if re.search(r"#\s*$", out):
        emit("login", "✅ already at root shell", "ok")
        return
    if "login:" in out.lower():
        ser.write((USER + "\r\n").encode())
        wait_for(ser, r"[Pp]assword:", timeout=4)
        ser.write((PASS_ + "\r\n").encode())
        wait_for(ser, r"#\s*$", timeout=8)
        emit("login", "✅ logged in", "ok")
    else:
        emit("login", f"unclear: {out[-200:]}", "err")
        raise RuntimeError("login failed")


def cmd(ser, line, timeout=5):
    ser.reset_input_buffer()
    marker = f"=={int(time.time()*1000)%100000}=="
    ser.write(f"{line}; echo {marker}\r\n".encode())
    end = time.time() + timeout
    out = ""
    while time.time() < end:
        n = ser.in_waiting
        if n:
            out += ser.read(n).decode("utf-8", "replace")
            if marker in out: break
        else:
            time.sleep(0.04)
    lines = out.replace("\r", "").split("\n")
    result = []
    for ln in lines:
        if marker in ln: break
        if "echo " + marker[:6] in ln: continue
        result.append(ln)
    return "\n".join(result).strip()


def stream_bin(ser, local_path):
    """raw binary 流式传输到板子,用 dd 接收。"""
    size = os.path.getsize(local_path)
    emit("xfer", f"{local_path} → /lib/firmware/ofdm_ldpc.bin  ({size:,} 字节)", "cyan")

    # 板子端启动 dd 接收 raw stdin → 文件
    # 关键: 用 dd 精确读取 size 字节,不会消费命令 prompt
    cmd(ser, "mkdir -p /lib/firmware")
    cmd(ser, "rm -f /lib/firmware/ofdm_ldpc.bin")
    cmd(ser, "stty raw -echo -ixon -ixoff -onlcr 2>/dev/null")  # 关 echo + flow ctrl
    # 启动 dd,不等回包 — dd 启动后立即等输入
    ser.reset_input_buffer()
    ser.write(f"dd of=/lib/firmware/ofdm_ldpc.bin bs=4096 count={(size+4095)//4096} 2>/tmp/dd.err\r\n".encode())
    time.sleep(0.4)  # 让 dd 起来
    ser.reset_input_buffer()

    # 直接写 binary
    sent = 0
    chunk = 1024
    t0 = time.time()
    last = 0
    with open(local_path, "rb") as f:
        while True:
            data = f.read(chunk)
            if not data: break
            # padding 最后一块到 4096 对齐(让 dd count 精确)
            ser.write(data)
            sent += len(data)
            now = time.time()
            if now - last > 1:
                pct = sent * 100 / size
                rate = sent / max(now - t0, 0.001) / 1024
                eta = (size - sent) / max(sent / max(now - t0, 0.001), 1)
                emit("xfer", f"  {sent:>8,}/{size:,}  {pct:5.1f}%  {rate:5.1f} KB/s  ETA {eta:.0f}s", "grey")
                last = now
        # padding 到 4096 边界
        rem = (4096 - (sent % 4096)) % 4096
        if rem:
            ser.write(b"\x00" * rem)
            emit("xfer", f"  padded {rem} zero bytes (4K alignment)", "grey")

    emit("xfer", f"  sent {sent} bytes, draining …", "cyan")
    time.sleep(3)
    ser.reset_input_buffer()

    # 恢复终端
    cmd(ser, "stty -raw echo")
    out = cmd(ser, "wc -c /lib/firmware/ofdm_ldpc.bin && md5sum /lib/firmware/ofdm_ldpc.bin")
    emit("xfer", out.replace("\n", "  |  "), "cyan")
    return out


def load_pl(ser):
    emit("load", "running fpga_manager …", "cyan")
    out = cmd(ser, "echo 0 > /sys/class/fpga_manager/fpga0/flags && "
                   "echo ofdm_ldpc.bin > /sys/class/fpga_manager/fpga0/firmware && "
                   "sleep 2 && cat /sys/class/fpga_manager/fpga0/state",
              timeout=10)
    emit("load", out, "ok" if "operating" in out else "err")
    return "operating" in out


def verify_emio(ser):
    emit("verify", "reading EMIO bank 2 (0xE000A068) …", "cyan")
    for i in range(3):
        v = cmd(ser, "busybox devmem 0xE000A068")
        emit("emio", v, "ok")
        time.sleep(0.3)


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--port", default=os.environ.get("SERIAL_PORT", ""))
    ap.add_argument("--bin", default=DEFAULT_BIN)
    args = ap.parse_args()

    port = args.port or find_pluto()
    if not port:
        emit("err", "no Pluto serial port detected (VID 0x0456). 板子插了吗?", "err")
        sys.exit(2)
    emit("port", port, "cyan")

    if not os.path.exists(args.bin):
        emit("err", f"{args.bin} 不存在 — 用 --bin 指定路径", "err")
        sys.exit(2)
    emit("bin", f"{args.bin} ({os.path.getsize(args.bin):,} 字节)", "cyan")

    try:
        ser = serial.Serial(port, BAUD, timeout=0.5, rtscts=False, dsrdtr=False)
    except Exception as e:
        emit("err", f"无法打开 {port}: {e}", "err")
        emit("err", "可能是 demo bridge 占用了 — 先停 demo 再跑这个脚本", "err")
        sys.exit(3)

    try:
        login(ser)
        stream_bin(ser, args.bin)
        ok = load_pl(ser)
        verify_emio(ser)
        if ok:
            emit("done", "✅ PL 已加载, EMIO 可读 — 现在重启 demo bridge 就能看真数据", "ok")
        else:
            emit("done", "⚠️ fpga_manager 不在 operating 状态", "warn")
    finally:
        ser.close()


if __name__ == "__main__":
    main()
