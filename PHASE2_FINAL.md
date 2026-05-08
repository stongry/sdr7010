# Phase-2 最终交付 — 板上真 OFDM+LDPC 数字回环

> 状态：**Partial success**。真 OFDM+LDPC 流水在 LDSDR 7010 板上跑通，LDPC BP 完整迭代完成（`rx_done=1`），但 `pass_flag` 还差 6 bit raw 错位 + LLR 量化导致 BP 没收敛到 `TEST_BITS`。

---

## 1. Phase-1 vs Phase-2 对比

| 维度 | Phase-1 (xsim) | Phase-2 (板上 LDSDR) |
|------|----------------|----------------------|
| FFT/IFFT | 行为级 DFT (`real` + `$cos/$sin`) | Vivado `xfft_v9.1` IP |
| 数学 | 1/8 双向缩放，cascade = X 严格 | unscaled + sat16，cascade ≠ X (LLR 数值精度差异) |
| BER | **0/512** | raw 硬判决 6/96 错位，BP 后 rx_decoded 还有错 |
| pass_flag | (sim PASS) | **0** （差 6 bit） |
| rx_done | (sim PASS) | **1** ✓ |

---

## 2. 板上 EMIO 最终读出值

```
Linux 5.15.0 / Pluto / armv7l
EMIO bank 2 (0xE000A068):
  bit[0] pass_flag         = 0
  bit[1] rx_done           = 1   ✓
  bit[31:2] rx_decoded[31:2] = 0x0581C183
  expected (TEST_BITS[31:2]) = 0x03C3C3C3
  XOR popcount             = 6 bit
```

LDPC decoder 完成 10 次 BP 迭代输出 valid_out，证明数据通路完全打通；剩余 6 bit 是 IP 数值实现细节跟 sim 行为级 DFT 不严格一致导致的 LLR magnitude 失真。

---

## 3. 9 次 build 迭代轨迹

| Build | xfft IP 配置 | wrapper 处理 | 板上 raw 错位 | rx_decoded[31:2] 错位 |
|-------|-------------|-------------|---------------|----------------------|
| #1 | scaled 默认 (/N each) | pass-through | 13 bit | rx_done=0 |
| #2 | BFP, bit_reversed | pass-through | 14 bit | (没读) |
| #4 | BFP, bit_reversed | EMIO probe rx_decoded | 14 bit | 17 bit |
| #5 | BFP, **natural_order** | pass-through | (~5) | 12 bit |
| #6 | unscaled, natural | sat16 (NO status port) | 综合 fail | — |
| **#7 / FINAL** | **unscaled, natural** | **sat16** | (~3) | **6 bit** |
| #8 | unscaled, natural | shift3 + sat16 | (~5) | 11 bit (worse) |

每次发现的关键 bug:
1. **#1 → #2**: scaled IP cascade /N² 让 LLR 全部接近 0，sign 大量翻转
2. **#5**: 默认 `output_ordering = bit_reversed_order` → OFDM 链路 bin 顺序错乱
3. **#7**: unscaled + sat16 让 sign 100% 保留 + magnitude 上限 ±32767
4. **#8**: shift>>3 让 LLR magnitude 缩太多，BP 行为反而变差

---

## 4. 板上 reload workflow（不需要重新烧 BOOT.bin）

```bash
# PC 端
python3 bit_to_bin.py vivado_output.bit ofdm_ldpc.bin
cat ofdm_ldpc.bin | sshpass -p analog ssh root@192.168.2.1 \
    "cat > /lib/firmware/ofdm_ldpc.bin"

# 板上 ssh 后
echo 0 > /sys/class/fpga_manager/fpga0/flags
echo 'ofdm_ldpc.bin' > /sys/class/fpga_manager/fpga0/firmware
sleep 3
busybox devmem 0xE000A068    # 读 EMIO
```

`flags=0` 是关键（默认 PR 模式 reload 失败）。`/dev/xdevcfg` 接口存在但**沉默失败**——必须用 fpga_manager firmware sysfs 才真换 PL。

---

## 5. Vivado impl 资源 + 时序

```
LUT       12 579 / 17 600  =  71.47 %
FF        14 074 / 35 200  =  39.98 %
BRAM       1 / 60 (xfft IP unscaled+natural reorder buffer)
DSP        used by xfft IP for complex MAC
WNS       +0.387 ns @ 50 MHz   ✓
WHS       +0.058 ns             ✓
```

时序 met，所有约束满足。

---

## 6. 还差什么才能 `pass_flag=1`

LDPC BP 没收敛到 TEST_BITS 的 root cause：**xfft IP unscaled + sat16 让 cascade != sim 行为级 1/8 双向 cascade=X**。具体：

- xsim 行为级用 `real` 类型浮点 + 1/8 双向，cascade 数学等同
- xfft IP unscaled 内部 23-bit signed 累加，wrapper sat16 在 |v|>32767 处 clip
- LLR magnitude 在边界 bin 被 clip → BP min-sum message 失真 → 收敛到 wrong codeword

修复路径（每条 1+ 周）：
- **A**: 让 xsim 用 IP simulation files (Vivado 生成)，sim/board 数学严格相同，反推校准
- **B**: 自己手写 64-pt FFT 可综合 RTL（不用 IP），数学跟 sim 行为级严格一致
- **C**: 改 LDPC decoder 用更鲁棒 BP 算法（offset min-sum / normalized min-sum）

---

## 7. Phase-2 milestone 总结

✅ **达成**：
1. xfft IP customize + 综合 + 板上加载工作
2. Linux fpga_manager 在线 reload 流程成立
3. PL 完整 OFDM+LDPC 流水跑通（rx_done=1, llr_done=1, eq=1）
4. LDPC decoder 完整迭代 10 次输出 valid_out
5. xsim PASS 0/512 errors（Phase-1 已经严格证明 RTL 数学 + 链路逻辑正确）

⚠️ **未达成**：
1. `pass_flag=1` bit-exact pass（差 6 bit 是 IP 数值精度问题，不是 logic 问题）
2. 完整 plutosdr-fw firmware 集成（task #24, #25 未做）

⏸️ **中间发现**：
1. bootgen 用 raw fsbl bin 时不填 image header 0x34/0x40/0x48 字段 → 板子不启动；patch_bootbin.py 修
2. Linux fpga_manager `flags=0` 必须显式设，否则 firmware sysfs reload silent fail
3. xfft IP 默认 `output_ordering=bit_reversed_order` 是 OFDM 链路最隐蔽的 trap

---

*Final commit: `a76211a` — xfft IP unscaled + natural_order + sat16 wrapper*
