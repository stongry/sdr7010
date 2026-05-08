#!/usr/bin/env python3
"""windows_load_pl_paramiko_v2.py — paramiko 强制兼容老 dropbear"""
import os, sys, time, hashlib

try:
    sys.stdout.reconfigure(encoding="utf-8"); sys.stderr.reconfigure(encoding="utf-8")
except Exception: pass

import paramiko
from paramiko.transport import Transport

HOST = "192.168.2.1"
USER = "root"
PASS = "analog"
BIN  = r"C:\sdr7010\ofdm_ldpc.bin" if sys.platform == "win32" else "/home/ysara/fpga_hdl/phase2_artifacts/ofdm_ldpc_FINAL.bin"


def emit(t, m): print(f"[{t}] {m}", flush=True)


def main():
    if not os.path.exists(BIN):
        emit("err", f"missing {BIN}"); sys.exit(2)
    size = os.path.getsize(BIN)
    md5 = hashlib.md5(open(BIN, "rb").read()).hexdigest()
    emit("bin", f"{BIN}  {size:,} bytes  md5={md5}")

    # Use raw Transport, force legacy SSH algorithms
    import socket
    sock = socket.create_connection((HOST, 22), timeout=10)
    emit("tcp", "connected, starting SSH transport with legacy algos…")

    transport = Transport(sock)
    # 显式偏好老算法 (避免新 paramiko 跟老 dropbear 谈判失败)
    transport.get_security_options().kex = (
        'diffie-hellman-group14-sha1',
        'diffie-hellman-group1-sha1',
        'diffie-hellman-group-exchange-sha1',
    )
    transport.get_security_options().ciphers = (
        'aes128-ctr', 'aes128-cbc', '3des-cbc',
    )
    transport.get_security_options().digests = ('hmac-sha1', 'hmac-md5',)
    transport.get_security_options().key_types = ('ssh-rsa',)

    emit("kex", "starting SSH key exchange…")
    transport.start_client(timeout=15)
    emit("kex", "✅ key exchange done")

    transport.auth_password(USER, PASS)
    emit("auth", "✅ logged in as " + USER)

    # 流式上传
    emit("xfer", f"→ /lib/firmware/ofdm_ldpc.bin  ({size:,} bytes)")
    chan = transport.open_session()
    chan.exec_command("mkdir -p /lib/firmware && cat > /lib/firmware/ofdm_ldpc.bin")
    t0 = time.time(); sent = 0; last = 0; chunk = 32768
    with open(BIN, "rb") as f:
        while True:
            data = f.read(chunk)
            if not data: break
            chan.sendall(data)
            sent += len(data)
            now = time.time()
            if now - last > 0.5:
                pct = sent * 100 / size
                rate = sent / max(now - t0, 0.001) / 1024
                emit("xfer", f"  {sent:>8,}/{size:,}  {pct:5.1f}%  {rate:.1f} KB/s")
                last = now
    chan.shutdown_write()
    chan.recv_exit_status()
    chan.close()
    elapsed = time.time() - t0
    emit("xfer", f"done in {elapsed:.1f}s ({size/elapsed/1024:.1f} KB/s)")

    # md5 verify
    chan = transport.open_session(); chan.exec_command("md5sum /lib/firmware/ofdm_ldpc.bin")
    board_md5 = chan.makefile().read().decode().split()[0]
    chan.close()
    emit("md5", f"local={md5}  board={board_md5}  {'MATCH' if md5 == board_md5 else 'MISMATCH'}")

    # fpga_manager
    chan = transport.open_session()
    chan.exec_command("echo 0 > /sys/class/fpga_manager/fpga0/flags && "
                      "echo ofdm_ldpc.bin > /sys/class/fpga_manager/fpga0/firmware && "
                      "sleep 2 && cat /sys/class/fpga_manager/fpga0/state")
    state = chan.makefile().read().decode().strip()
    chan.close()
    emit("load", f"state={state}")

    # EMIO read
    for i in range(3):
        chan = transport.open_session(); chan.exec_command("busybox devmem 0xE000A068")
        v = chan.makefile().read().decode().strip()
        chan.close()
        if v.startswith("0x"):
            iv = int(v, 16)
            emit("emio", f"EMIO={v}  rx_done={(iv>>1)&1}  pass_flag={iv&1}  hi30=0x{iv>>2:08X}")

    transport.close()
    emit("done", "PL loaded — restart demo to see real EMIO")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        emit("err", f"{type(e).__name__}: {e}")
        import traceback; traceback.print_exc()
