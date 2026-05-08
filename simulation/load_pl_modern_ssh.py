#!/usr/bin/env python3
"""
windows_load_pl_ssh.py — Windows 现场通过 RNDIS SSH 烧录 PL bitstream

paramiko 走 192.168.2.1 SSH:
  1. 流式传 ofdm_ldpc.bin → /lib/firmware/ (944KB ~10 秒)
  2. fpga_manager 加载
  3. 读 EMIO 验证

依赖:  pip install paramiko
"""
import os
import sys
import time
import hashlib

try:
    import paramiko
except ImportError:
    print("[err] 装 paramiko: pip install --user paramiko"); sys.exit(1)

HOST = os.environ.get("BOARD_HOST", "192.168.2.1")
USER = os.environ.get("BOARD_USER", "root")
PASS = os.environ.get("BOARD_PASS", "analog")
BIN  = os.environ.get("BIN_PATH",
    r"C:\sdr7010\ofdm_ldpc.bin" if sys.platform == "win32"
    else "/home/ysara/fpga_hdl/phase2_artifacts/ofdm_ldpc_FINAL.bin")


def emit(tag, msg):
    print(f"[{tag}] {msg}", flush=True)


def main():
    if not os.path.exists(BIN):
        emit("err", f"找不到 {BIN}"); sys.exit(2)
    size = os.path.getsize(BIN)
    md5  = hashlib.md5(open(BIN, "rb").read()).hexdigest()
    emit("bin", f"{BIN}  {size:,} bytes  md5={md5}")

    emit("ssh", f"connect {USER}@{HOST} ...")
    c = paramiko.SSHClient()
    c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    c.connect(HOST, username=USER, password=PASS,
              timeout=5, banner_timeout=5, auth_timeout=5,
              allow_agent=False, look_for_keys=False)
    emit("ssh", "✅ connected")

    # 流式上传 (用 exec_command + stdin pipe)
    emit("xfer", "→ /lib/firmware/ofdm_ldpc.bin")
    t0 = time.time()
    stdin, stdout, stderr = c.exec_command(
        "mkdir -p /lib/firmware && cat > /lib/firmware/ofdm_ldpc.bin", timeout=60)
    sent = 0
    last = 0
    chunk = 32768
    with open(BIN, "rb") as f:
        while True:
            data = f.read(chunk)
            if not data: break
            stdin.write(data)
            sent += len(data)
            now = time.time()
            if now - last > 0.5:
                pct = sent * 100 / size
                rate = sent / max(now - t0, 0.001) / 1024
                emit("xfer", f"  {sent:>8,}/{size:,}  {pct:5.1f}%  {rate:5.1f} KB/s")
                last = now
    stdin.close()
    stdout.read()
    elapsed = time.time() - t0
    emit("xfer", f"✅ done in {elapsed:.1f}s ({size/elapsed/1024:.1f} KB/s)")

    # 验证 md5
    _, stdout, _ = c.exec_command("md5sum /lib/firmware/ofdm_ldpc.bin")
    board_md5 = stdout.read().decode().split()[0]
    emit("md5", f"local={md5}  board={board_md5}  {'✅ MATCH' if md5 == board_md5 else '❌ MISMATCH'}")

    # 加载 PL
    emit("load", "fpga_manager ...")
    _, stdout, _ = c.exec_command(
        "echo 0 > /sys/class/fpga_manager/fpga0/flags && "
        "echo ofdm_ldpc.bin > /sys/class/fpga_manager/fpga0/firmware && "
        "sleep 2 && cat /sys/class/fpga_manager/fpga0/state")
    state = stdout.read().decode().strip()
    emit("load", f"state = {state}  {'✅' if 'operating' in state else '❌'}")

    # EMIO 验证
    emit("emio", "reading EMIO bank 2 ...")
    for i in range(3):
        _, stdout, _ = c.exec_command("busybox devmem 0xE000A068")
        v = stdout.read().decode().strip()
        if v.startswith("0x"):
            iv = int(v, 16) & 0xFFFFFFFF
            rxd = (iv >> 1) & 1
            pf  = iv & 1
            hi30 = (iv >> 2) & 0x3FFFFFFF
            emit("emio", f"  EMIO={v}  rx_done={rxd}  pass_flag={pf}  rx_decoded[31:2]=0x{hi30:08X}")
        time.sleep(0.3)

    c.close()
    emit("done", "✅ 烧录完成 — 现在 demo 看真实数据")


if __name__ == "__main__":
    main()
