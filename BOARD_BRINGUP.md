# LDSDR 板上 OFDM+LDPC bring-up 操作指南（Phase 2 验证）

> 给板上跑 `xfft_v9.1` IP + 真 OFDM + LDPC 数字回环用的最小化操作流程。
> Phase-1 (xsim) 已验证 0/512 bit errors；这里只剩"写 SD → 上电 → 读 EMIO"。

---

## 步骤 1：拿到 BOOT.bin

编译机上 `~/bootbin_work/BOOT.bin` 已生成，大小约 1-2 MB。从编译机 scp 到本机：

```bash
scp -P 2424 eea@10.24.79.1:~/bootbin_work/BOOT.bin .
```

或者用我下面给你的 commit 里 push 到 GitHub 的 `BOOT.bin`（如果 < 100 MB 可推 release）。

## 步骤 2：写 SD 卡

LDSDR 板用 SD-mode 启动（拨码开关已配好）。SD 卡上有一个 FAT32 的 `BOOT` 分区。

```bash
# 查 SD 卡设备
lsblk

# 假设 SD 卡的 BOOT 分区是 /dev/sdb1
sudo mkdir -p /mnt/sdcard
sudo mount /dev/sdb1 /mnt/sdcard

# 备份原 BOOT.bin（如果想保留的话）
sudo cp /mnt/sdcard/BOOT.bin /mnt/sdcard/BOOT.bin.bak

# 写新 BOOT.bin
sudo cp BOOT.bin /mnt/sdcard/BOOT.bin
sync
sudo umount /mnt/sdcard
```

## 步骤 3：插板 + 上电

1. SD 卡插回 LDSDR 7010 板
2. USB-C 接 PC（电源 + USB CDC ethernet）
3. UART 串口（FT4232H 三个 USB ttyUSB0/1/2）接终端：`screen /dev/ttyUSB0 115200`
4. 上电

预期串口输出：FSBL banner → 加载 bitstream → 启动到 u-boot prompt（或 Linux）

## 步骤 4：读 EMIO `pass_flag`

### 路线 A：u-boot prompt 直接读 GPIO controller register

LDSDR 起到 u-boot prompt 后：

```
zynq-uboot> md.l 0xe000a060 1
```

`0xe000a060` 是 Zynq GPIO bank 2 (EMIO) 的 DATA_RO 寄存器。读出来的 32-bit 值 LSB 即 `pass_flag`：

| 读出位 | 信号 | 期望值 |
|--------|------|--------|
| [0] | pass_flag | **1** = OFDM+LDPC 数字回环成功 |
| [1] | rx_done | 1 |
| [2] | dbg_llr_done_seen | 1 |
| [3] | dbg_eq_seen | 1 |
| [19:4] | dbg_demod_cnt | ≈ 576（12 sym × 48 bin） |
| [31:20] | dbg_ifft_cnt | ≈ 768（12 sym × 64） |

### 路线 B：Linux 启起来后 sysfs 读

如果 Linux 启起来：

```bash
cd /sys/class/gpio
for b in 0 1 2 3; do
    echo $((906+b)) > export 2>/dev/null
    echo "bit $b = $(cat gpio$((906+b))/value)"
done
```

GPIO 906 是 EMIO bit 0 = pass_flag（具体 base 看 `/sys/class/gpio/gpiochip*/base`）。

## 故障排除

### 上电后 USERLED 不亮

PL 没启动。检查：
- bitstream 写入对没有
- BOOT.bin 是不是真的更新了（看 size 跟 fsbl + bit + uboot 总和差不多）
- SD 卡接触是否良好

### USERLED 亮但 pass_flag = 0

PL 跑了但 OFDM+LDPC 链路没通。检查 EMIO bit 1-3：

| bit | 含义 | 0 表示 |
|-----|------|--------|
| 1 | rx_done | LDPC decoder 没出 valid_out |
| 2 | dbg_llr_done | llr_buffer 没攒够 1024 LLR |
| 3 | dbg_eq_seen | channel_est 没出过 valid |

哪一位最高位 = 0，瓶颈就在那一级前面。

### USB CDC 不识别

跟 PL 配置无关。确认 fsbl 是不是用 LDSDR PS7 config 生成的（包含 USB controller MIO 配置）。

---

## Phase-2 validation 成功标准

板上电后 30 秒内，u-boot prompt 读 `md.l 0xe000a060 1`，输出最低位为 `1` → **PASS**。

这等价于 xsim 里 `0/512 bit errors PASS` 在真硬件上重现，证明 Vivado xfft_v9.1 IP + LDPC + OFDM 整套链路在 xc7z010clg400-2 上综合 + 时序收敛 + 板上工作。
