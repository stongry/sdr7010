# SDR7010 — 完整问答手册（QA.md）

> 项目：<https://github.com/stongry/sdr7010>
> 板卡：LDSDR 7010 rev2.1（xc7z010clg400-2 + AD9363-BBCZ）
> 工具链：Vivado 2024.2 / ADI HDL main / plutosdr-fw v0.38 / Linux iio
>
> 这份 QA 是对 [README.md](./README.md) 与 [lkh.md](./lkh.md) 技术深潜文档的**问答补充**，按读者最常遇到的疑问分类。每条都给出具体代码/文件位置 + 数值证据，便于直接动手复现。

---

## 目录

- [A. 项目入门 / 立项背景](#a-项目入门--立项背景)
- [B. 硬件平台](#b-硬件平台)
- [C. 顶层架构与 PL 容器](#c-顶层架构与-pl-容器)
- [D. LDPC 编/译码](#d-ldpc-编译码)
- [E. OFDM 物理层](#e-ofdm-物理层)
- [F. 仿真与 xsim 验证](#f-仿真与-xsim-验证)
- [G. Path X — Python 软件 OFDM 验证](#g-path-x--python-软件-ofdm-验证)
- [H. Vivado 综合与构建](#h-vivado-综合与构建)
- [I. AD9363 / RF 接口](#i-ad9363--rf-接口)
- [J. plutosdr-fw 与 Linux 集成](#j-plutosdr-fw-与-linux-集成)
- [K. 板上调试：JTAG / UART / EMIO](#k-板上调试jtag--uart--emio)
- [L. 已知限制与下一步工作](#l-已知限制与下一步工作)
- [M. 故障排除 FAQ](#m-故障排除-faq)

---

## A. 项目入门 / 立项背景

### A1. 这个工程到底做了什么？

在 LDSDR 7010 rev2.1 板（一款 PlutoSDR 衍生板，FPGA 是 Zynq-7010 clg400 + AD9363）上完整实现一条 OFDM + LDPC 物理层链路，覆盖三个层次：

1. **数字回环（PL-only digital loopback）**：FPGA 内部 TX→RX 直连，全 PL 数据通路验证。Build #34 通过，`pass_flag=1`。
2. **Path X（软件 OFDM RF loopback）**：Python 在 PC 用 numpy 做 OFDM 调制，把 IQ 经 libiio 灌进 AD9363 TX1，SMA 自环到 RX1，再 numpy 解调对齐解码。32 bit 全对（`0/32 errors`）。
3. **Path A（ADI HDL pluto 移植到 clg400）**：把官方 ADI HDL `pluto` 工程从 clg225 BGA → clg400 LQFP 引脚重排，以便复用 ADI 的全套 axi_ad9361 + axi_dmac + axi_quad_spi BD。

### A2. 为什么先做数字回环再做 RF？

数字回环把 FPGA 内部 TX 输出**直接接**到 RX 输入，绕过 AD9363 / SMA / 模拟噪声，单点定位 OFDM+LDPC 链路本身的逻辑 bug。Build #1–19 大部分时间都是在数字回环里抓 bug（见 [README.md](./README.md) 的 "Bug-hunt diary"）；只有等数字回环 `rx_done=1` 之后，才把同一份 RTL 接到 AD9363 LVDS PHY。

### A3. 这工程的代码大头分布在哪里？

直接在仓库根目录 `/home/ysara/fpga_hdl/`：

```
ofdm_ldpc_top.v          # OFDM + LDPC 数据通路顶层（一个盒装下 TX→RX）
ofdm_ldpc_pl.v           # PL 容器：POR + startup_gen + EMIO debug 锁存
ofdm_ldpc_rf_top.v       # RF 顶层（数字 + AD9363 LVDS 接口）
ldpc_encoder.v           # QC-LDPC IRA 编码器
ldpc_decoder.v           # QC-LDPC layered min-sum BP 译码器
qpsk_mod.v / qpsk_demod.v
tx_subcarrier_map.v / rx_subcarrier_demap.v
cp_insert.v / cp_remove.v
xfft_stub.v              # FFT/IFFT 占位（综合时换成 Vivado FFT IP）
channel_est.v            # 信道估计（双模式：STREAM_MODE / FRAME_MODE）
llr_assembler.v / llr_buffer.v
ad9361_phy.v             # LVDS DDR 物理层（Path A 用 ADI 自带 axi_ad9361）
phy_rx.v / phy_tx.v      # 数字 PHY 适配层
```

构建脚本：

```
run_ldsdr_digital.tcl     # 数字回环 BD（build #34 PASS）
run_ldsdr_rf.tcl          # RF BD（含 AD9363 接口）
build_pluto_ldsdr.sh      # Path A 一键构建脚本
```

仿真：`simulation/` 整目录（testbench + 波形 + 各种渲染图）。

### A4. 这个工程的"完成度"现在是多少？

- ✅ 数字回环：`rx_done=1`、`pass_flag=1`（build #34）
- ✅ Path X 软件 OFDM RF：`0/32 bit errors`，TX→AD9363→SMA→RX→Python 全链路通
- ✅ Path A pluto_ldsdr：clg225→clg400 移植 + bitstream 通过
- 🔧 进行中：plutosdr-fw v0.38 移植到 LDSDR clg400（已能 build，板上验证 pending）
- 🔧 待做：把 `ofdm_ldpc_top` 集成进 plutosdr-fw 的 BD，跑完整 firmware 板上测试

---

## B. 硬件平台

### B1. LDSDR 7010 跟 ADI PlutoSDR 是同一个东西吗？

不是，但是相近的衍生品。**关键区别**：

| 维度 | ADI PlutoSDR | LDSDR 7010 rev2.1 |
|------|--------------|-------------------|
| FPGA part | xc7z010clg225-1 | xc7z010clg400-2 |
| 封装 | BGA 225 | LQFP 400 |
| RF chip | AD9363-BBCZ | AD9363-BBCZ |
| DDR | 512 MB DDR3L | 512 MB DDR3 (16-bit, MT41K256M16) |
| USB | OTG type-C | OTG type-C |
| 增加 | — | 千兆 PHY、JTAG/UART、TF 卡启动、2T2R SMA 全引出 |

工程早期吃过的最大坑：把 LDSDR 当成 PlutoSDR 直接刷官方 firmware → 启动失败。识别正确板型后才有进展（[README.md](./README.md) build #1–6）。

### B2. clg400 vs clg225 引脚不同，怎么处理？

两条路：

- **Path X**：自己写 `ldsdr_toppin.xdc` + 自己搭 BD，与 ADI HDL 解耦
- **Path A**：把 ADI HDL `pluto` 工程的 BGA225 引脚约束**手动改写**成 LQFP400 上对应的 net，参考 `pluto_ldsdr/system_constr.xdc`。这个工作完成后整套 ADI BD（axi_ad9361 + axi_dmac×2 + axi_quad_spi）可以原样复用

### B3. 哪里查每个引脚到 AD9363 的物理对应关系？

- 板厂硬件原理图（`reference_qsm368zp_wf.md` memory 里有完整链接）
- `pluto_rf.xdc`：本工程实际写出的 RF 引脚约束
- `simulation/ad9363_pinmap.png`：人工绘制的 LVDS DDR 引脚映射图

LVDS DDR 关键 pin（板上对应）：

```
RX_FRAME_P/N → LVDS receive frame
RX_DATA_P/N[5:0] → 12-bit DDR (上下沿轮采)
RX_CLK_P/N    → 245.76 MHz feedback clk
TX_FRAME_P/N → LVDS transmit frame
TX_DATA_P/N[5:0] → DDR
TX_CLK_P/N    → 245.76 MHz drive clk
```

### B4. AD9363 跟 AD9361 是一个芯片吗？

逻辑寄存器层面**完全兼容** AD9361，固件同一份。区别仅在 RF 前端：AD9363 限制为 70 MHz–6 GHz、20 MHz BW（AD9361 是 70 MHz–6 GHz、56 MHz BW）。所以代码里所有 driver、DTS 都写 `ad9361`。

### B5. 板上 LVDS_25 IO standard 用对了吗？

是。clg400 的 HP bank 直接支持 LVDS_25。`ldsdr_toppin.xdc` 里明确：

```tcl
set_property IOSTANDARD LVDS_25 [get_ports {rx_data_p[*] rx_data_n[*] ...}]
```

如果误写成 `LVDS` 或 `DIFF_HSTL_I` 综合会过但板上 LVDS 信号摆幅不对，AD9363 解不出 frame。

---

## C. 顶层架构与 PL 容器

### C1. `ofdm_ldpc_top` 和 `ofdm_ldpc_pl` 区别？

- **`ofdm_ldpc_top.v`**：纯数据通路。8 个子模块（编码器→映射→IFFT→CP插→CP除→FFT→均衡→解映射→解调→LLR缓冲→译码器）一字串起。无任何 PS 或 EMIO 逻辑。可独立做仿真。
- **`ofdm_ldpc_pl.v`**：PL "外壳"。包含：
  - POR（power-on reset）合成 `rst_n` 给所有子模块
  - `startup_gen`：上电延时后给 `tx_valid_in` 一个脉冲，无需 PS 干预自动启动
  - **EMIO 32-bit GPIO_I 锁存**（关键！）：把所有内部状态位捕获到一个 32-bit 寄存器，PS 通过 `/sys/class/gpio/gpio906...` 读出，做无 UART 的 bring-up

EMIO bit 布局（[README.md](./README.md) 表格）：

| bit | 信号 | 含义 |
|---|---|---|
| 0 | `pass_flag` | `rx_decoded == TEST_BITS` ? 1 : 0 |
| 1 | `rx_done` | LDPC decoder `valid_out` 见过一次 |
| 2 | `dbg_llr_done_seen` | llr_buffer 攒够 512 LLRs |
| 3 | `dbg_eq_seen` | channel_est 出过 valid |
| 19:4 | `dbg_demod_cnt` | qpsk_demod valid 计数（应该 ≈ 576） |
| 31:20 | `dbg_ifft_cnt` | mapper 输出周期数（应该 ≈ 12 sym × 80 cy） |

### C2. 为什么需要 `startup_gen` 自动启动而不让 PS 触发？

LDSDR 没有 UART 的时候 PS 上 Linux 启不来 → 没法 `echo 1 > /sys/.../gpio_o/value` 触发 TX。`startup_gen` 上电延时（~1 ms）后自己拉 `tx_valid_in` 一个脉冲，PL 完全自启，PS 只读 EMIO 验证结果就行。

### C3. 为什么是 EMIO GPIO 而不是 AXI GPIO？

EMIO 直接挂在 PS GPIO controller 的扩展端口上（`PS7/EMIOGPIOI[31:0]`），bring-up 阶段 **不依赖** PL AXI interconnect 全功能，少一个出错点。Build #7–8 的时候 AXI 还在挣扎复位，靠 EMIO 才看见心跳。

### C4. `ofdm_ldpc_top` 里的 IFFT/FFT 现在是真的吗？

不是。`xfft_stub.v` 是组合 pass-through，"频域"和"时域"在数值上恒等。**这是有意为之**：先把 LDPC + QPSK + 子载波分配 + CP 这条链路打通；FFT 留接口（AXI-S TDATA + TVALID + TLAST），综合时再换 Vivado FFT IP（`xfft_v9.1`，Pipelined Streaming I/O 模式）。

---

## D. LDPC 编/译码

### D1. 用的什么码？(1024, 512) 是什么意思？

QC-LDPC IRA（Irregular Repeat Accumulate）码，码率 1/2：

- N = 1024（码字长度）
- K = 512（信息位长度）
- Z = 64（lifting factor，循环子矩阵尺寸）
- Hb = 8×16（基矩阵；展开后 H = (8·64) × (16·64) = 512 × 1024）
- 系统 col 0..7 + 校验 col 8..15（dual-diagonal 形式）

基矩阵 `Hb` 完整写在 `ldpc_encoder.v` 和 `ldpc_decoder.v` 顶部的 `localparam [767:0] HB`。两边必须**完全一致**，否则译码器收不到合法码字。

### D2. 译码器迭代多少次？

`MAX_ITER = 10`（在 `ldpc_decoder.v` 的 parameter 里）。Min-sum BP 算法，layered schedule（CNU-then-VNU），每层全部 row 处理完才进下一次迭代。10 次是经验性折衷：通信信道 SNR 高时 3-4 次就收敛，loopback 噪声为零时 1 次即收敛。

### D3. LLR 量化几位？为什么会饱和？

`Q = 8`（8-bit signed LLR，范围 −128..+127）。从 `qpsk_demod` 出来的浮点 LLR 乘 SCALE=7 然后 saturate 到 8-bit；`llr_buffer` 用 distributed RAM 存 1024 个 8-bit LLR。这个量化精度对 (1024,512) 码是足够的（FER 几乎不会因为量化损失）。

### D4. 编码器有 8 个 FSM 状态在干什么？

`ldpc_encoder.v` 用了 layered IRA 编码：

1. ST_IDLE：等 `valid_in` 脉冲
2. ST_LOAD：把 512 info bits 存进 `info_reg`
3. ST_PHASE0：算 `parity[Z-1]`（dual-diagonal 闭环的种子）
4. ST_PHASE1：8 行 × 64 列展开 systematic 部分异或入 parity
5. ST_PHASE2：dual-diagonal 累加
6. ST_OUT：拼 `{parity, info}` = 1024-bit 码字
7. ST_DONE：拉 `valid_out` 一拍

**关键 bug**（build #14 修的）：`cycle_cnt` 早期写成 `[4:0]`（max 31），但 Z=64 需要 `[5:0]`，导致 phase-1 出口条件 `cycle_cnt == Z-1 = 63` 永远不成立。改成 `[$clog2(Z)-1:0]` 才解决。

### D5. 为什么早期有"pass_flag=0 但 rx_done=1"的中间状态？

build #19 的状态：编/译码两边 Hb 是同一份 Verilog 数组，**结构一致**，所以译码器能跑完 BP 输出 `valid_out`。但是这套 Hb 的 shift 值是为 Z=32 设计的（max=31），现在跑 Z=64 数学上不再是合法码 → 译码器收敛到的不是原始 info bits。Build #34 的修复：把 Hb 全部改成 Z=64 合法的 shift 值。

---

## E. OFDM 物理层

### E1. OFDM 参数是什么？

| 参数 | 值 |
|------|-----|
| FFT 长度 N_FFT | 64 |
| CP 长度 N_CP | 16 |
| 每符号样本数 | 80 = 64 + 16 |
| 数据子载波 | 48（bin 1-6, 8-20, 22-26, 38-42, 44-56, 58-63） |
| 导频子载波 | 4（bin 7, 21, 43, 57） |
| NULL bin | 12（bin 0 + bin 27..37） |
| 每符号比特 | 96 = 48 × 2（QPSK） |
| 每码字符号数 | 12（96 × 12 = 1152，多余的余量给同步） |
| Pilot 振幅 | 5793（≈ 16384/√8 = 单位幅度的 √2/2 折半） |

定义在 `ofdm_ldpc_top.v` 顶部 + `path_x_v3.py` 的常量段。

### E2. 为什么导频幅度是 5793？

`5793 ≈ 16384 / √8 ≈ 0.353·2^14`。需要满足两个条件：
1. IFFT 后**时域峰值不溢出 16-bit signed**（DAC 是 12-bit 但 RTL 用 16-bit 内部）
2. 导频功率 / 数据功率 ≈ 1（不抢占动态范围）

经过把 8 个子载波 IFFT 解析的常数验证，5793 是稳定不溢出的最大值。

### E3. NULL bin 为什么是 0 + 27..37？

OFDM 标准做法：
- bin 0 = DC（直流，留空避免 LO 泄漏）
- bin 27..37 = "guard band"（FFT 中心附近的 11 个 bin，对应基带最高频率，过零点附近避免 ADC/DAC anti-alias 滤波器衰减区）

11 个 NULL bin 跟 IEEE 802.11a 的 64-FFT OFDM（DC + ±26..±32）虽然布局不同但思想一致——避开基带高频带边和 DC。

### E4. CP=16 够吗？

数字 loopback 不需要（信道是 ideal）；RF SMA self-loop 也基本够（线缆延时 < 1 ns ≪ CP 时长）。真实多径 ISI 信道下 CP 要根据 channel impulse response 长度选。CP=16 对应时长 = 16 / fs，fs=2.5 MHz 时 CP = 6.4 µs。

### E5. `cp_insert` 的 ping-pong 是干什么？

发送侧用两个 64-sample bank：
- bank A 写满（IFFT 输出 64 sample 进来）→ rd_bank=0 时读 bank A 出 80-sample（先 CP=末 16，再 64）
- bank B 同时写下一 symbol → 切换 rd_bank=1

这样输出无 stall。**bug**：rd_bank 复位值早期是 1，导致第一个 bank A 写满时 reader 还指向 bank B（空），TX 死锁。Fix：复位值改 0（build #12）。

---

## F. 仿真与 xsim 验证

### F1. 怎么跑 testbench？

```bash
cd /home/ysara/fpga_hdl
vivado -mode batch -source run_sim.tcl
```

`run_sim.tcl` 会拉起 Vivado xsim，编译 `tb_ofdm_ldpc.v` + 所有 RTL，跑到 `$finish`，输出 VCD 波形 + console pass/fail 行。

### F2. testbench 都验了什么？

`tb_ofdm_ldpc.v`：
1. 给 `ofdm_ldpc_top` 一个 512-bit `TEST_BITS`
2. 等 `tx_valid_out` 拉高，把 16-bit IQ 流接收下来
3. 一拍延时直接接到 `rx_iq_i/q + rx_valid_in + rx_frame_start`（一周期 PL-internal loopback）
4. 等 `rx_valid_out`，比较 `rx_decoded == TEST_BITS`，输出 `0/512 bit errors PASS`

完整波形见 `simulation/path_x_waveform_full.png`。

### F3. xsim 跑通了能保证板上跑通吗？

**不能**。xsim 是 RTL 行为仿真，不验证：
- 时序收敛（WNS/WHS）
- IO planning（pin assign 错也能 sim 过）
- BD AXI interconnect 配错（内存映射、地址解码）
- bootgen / FSBL 链路（只是 RTL 通）

所以 xsim 通过只是必要条件。最终 sign-off 还是 build #34 板上 EMIO 读出 `pass_flag=1`。

### F4. VCD 波形怎么看？

```bash
gtkwave simulation/tb_ofdm_ldpc.vcd
```

或者用 Vivado 自带 wave viewer：

```bash
vivado simulation/tb_ofdm_ldpc.wcfg
```

`simulation/path_x_waveform_full.png` 是已经标注好关键 17 路信号的渲染图，看图即可。

---

## G. Path X — Python 软件 OFDM 验证

### G1. Path X 是什么、为什么要做？

Path X = "PC Python 软件 OFDM + AD9363 RF self-loop" 验证。流程：

```
PC numpy.ifft → 时域 IQ → libiio TCP → AD9363 TX1 → SMA cable → RX1
                                                                    ↓
                                       libiio TCP → numpy.fft → 解码
```

**验证目标**：在不依赖 PL OFDM RTL 的情况下，单独验证 AD9363 模拟链路、libiio buffer 编程、CP 自相关同步等子问题。Path X 通了之后再把同一组比特放进 PL，问题域就缩小了。

### G2. Path X 用了什么 Python 库？

```python
import iio        # libiio
import numpy as np
```

代码 `path_x_v3.py`：4188 字节、约 130 行。核心是：
- `build_symbol(bits64)`：64-bit → 12 OFDM symbols 的 numpy.ifft
- `demap_at(rx_iq, sym_start)`：FFT + 取 48 数据子载波 + 硬判决
- `cp_correlate`：自相关找 frame_start
- `iio.Context("ip:192.168.2.1")`：连板子

### G3. URI 里的 `192.168.2.1` 是哪里来的？

LDSDR 启 USB CDC NCM gadget 后，会暴露一个虚拟以太网，板子端 IP 默认 `192.168.2.1`，PC 端 `192.168.2.10`。这是从 plutosdr-fw 继承的约定（也可以走千兆口 + 不同 IP）。

### G4. 32 个 bit 怎么变成 OFDM symbol 流？

```python
TEST_BITS_LO = 0x0F0F0F0F   # 32 bits, low half
TEST_BITS = TEST_BITS_LO | (TEST_BITS_LO << 32)  # 64 bits

# build_symbol() 把 64 bits 分给 48 个 data bin（每 bin 2 bit QPSK）
# 但只用前 32 bit；后 32 bit 是冗余/对齐空位
```

接收侧 `decoded[31:0] == TEST_BITS_LO` 即认为 PASS（32-bit 比对，不是 64）。

### G5. 关键 RF 配置有哪些？

`path_x_v3.py` 里：

```python
LO = 2.4e9          # TX/RX LO 都设这
fs = 2.5e6          # 2.5 MHz baseband sample rate
TX_atten = -75 dB   # 极低发射功率（短 SMA loop 不需要大功率）
RX_gain = 30 dB     # manual control
DDS = OFF           # AD9363 内部 DDS 关掉，否则 TX 会叠加 sine
```

**关键修复**（lkh.md §17.3）：默认 AD9363 启动后内部 DDS 是开的、会输出 sine wave。要 `iio.Channel.attrs["raw"].value = "0"` 关掉。否则 RX 看到的是 OFDM + DDS 叠加，解码必错。

### G6. 怎么找 frame_start？

CP 自相关：发送的 OFDM symbol 末尾 16 sample 跟开头 16 sample（即 CP）完全一样。RX 端滑窗算 `corr[k] = sum(rx[k:k+16] * conj(rx[k+64:k+80]))`，峰值位置就是 symbol 起点。

`path_x_v3.py` 的 `find_sym_start()` 实现这个。

### G7. 为什么 Path X 通了但 fixed-point HW 还要单独验证？

Python 是浮点 numpy.ifft。HW 是定点 16-bit 算法。两者数值精度差几位 ULP，但累积后 LLR 量化、QPSK 硬判决可能跨 boundary。所以 Path X 通了不代表 HW 通——HW 跑数字 loopback 是另一条独立验证路径。

---

## H. Vivado 综合与构建

### H1. 几个 .tcl 脚本的关系？

| 脚本 | 用途 |
|------|------|
| `run_ldsdr_digital.tcl` | 数字 loopback BD（PL-only，无 AD9363）。这个是 build #34 用的 |
| `run_ldsdr_rf.tcl` | RF loopback BD（含 AD9363 LVDS PHY） |
| `run_bd2.tcl` | 早期实验 BD |
| `run_rf.tcl` / `run_rf_linux.tcl` | RF + Linux 完整 BD |
| `pluto_ldsdr/system_project.tcl` | Path A（ADI HDL 移植） |
| `build_pluto_ldsdr.sh` | Path A 一键打包 |

### H2. 怎么从源码到 BOOT.bin？

```bash
# 1. 在编译机生成 .bit
ssh eea@10.24.79.1 -p 2424
cd ~/sdr7010_build
vivado -mode batch -source run_ldsdr_digital.tcl
# 产出: ldsdr_digital.runs/impl_1/ofdm_ldpc_pl_wrapper.bit

# 2. 生成 FSBL（Vitis 工程）
xsct gen_fsbl.tcl

# 3. bootgen 拼 BOOT.bin
bootgen -arch zynq -image boot.bif -o BOOT.bin -w on
# boot.bif 内容：
# the_ROM_image: { [bootloader] fsbl.elf
#                  ofdm_ldpc_pl_wrapper.bit
#                  u-boot.elf }

# 4. 拷到 SD 卡 BOOT 分区
sudo cp BOOT.bin /media/$USER/BOOT/
```

### H3. 为什么时序收敛跑不过去？

build #9 撞上 WNS = -4.524 ns @ 100 MHz（path 需要 14.5 ns，给到 5.476 ns）。常见解决路径：

1. **降低 fclk0 频率**（最快）：100 MHz → 50 MHz，path 要求变成 14.5 ns vs 给 14.5 ns，WNS 立刻 +1.7 ns 转正
2. 在长组合路径上 retime / 加 pipeline register
3. `set_property MAX_FANOUT` 限制扇出

本工程选 1（PL 数字逻辑没那么吃带宽）。fclk0 配在 `ldsdr_ps7_config.tcl`：

```tcl
set_property -dict [list CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {50}] [get_bd_cells PS7]
```

### H4. 综合把我代码优化掉了怎么办？

build #10–11 撞上：连续两次源码改了，bitstream MD5 不变。原因是综合判定整段逻辑无用、reachability 不到顶层端口，silently 删掉。修复：

```verilog
(* DONT_TOUCH = "TRUE" *) ofdm_ldpc_top u_top (...);

reg [15:0] (* KEEP = "TRUE" *) cnt;
```

把要保留的实例和寄存器加 attribute。`DONT_TOUCH` 阻止综合优化（包括常数传播、死代码消除），`KEEP` 阻止 register merging / removal。

### H5. clg400 跟 clg225 综合的差异？

主要是 IO planning：
- clg225 是 BGA 175 IO + 50 power/gnd
- clg400 是 LQFP 188 IO + 212 power/gnd

ADI HDL 默认 BD 用的 RF 引脚名（如 `MIO0`、`PS_DDR_*`）clg400 部分名字相同但 ball location 完全不同。Path A 重写了 `pluto_ldsdr/system_constr.xdc`，把每个 net 重新 `set_property PACKAGE_PIN`。

### H6. `mb_debug_sys_rst` 为什么是高电平有效？

ARM Microblaze debug system reset。**高电平有效**（不是 active-low）。Vivado 默认 `proc_sys_reset_0/mb_debug_sys_rst` 这个 input 不接的话会浮空 → 在 BD 验证时 Vivado 会自动拉成 1 → 整个 `peripheral_aresetn` 永久挂在 reset。

build #8 的修：

```tcl
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 xlconst_zero
set_property CONFIG.CONST_VAL {0} [get_bd_cells xlconst_zero]
connect_bd_net [get_bd_pins xlconst_zero/dout] \
               [get_bd_pins proc_sys_reset_0/mb_debug_sys_rst]
```

---

## I. AD9363 / RF 接口

### I1. AD9363 怎么跟 FPGA 对话？

LVDS DDR 接口，250 Mbps × 2 lanes × 6 数据 wire = 数据带宽够 12-bit IQ × 2 channel × 245.76 MHz：

- **数据**：6 对 LVDS DDR（上下沿各取一个 6-bit half-word，凑成 12-bit sample）
- **frame**：1 对 LVDS DDR，标记 sample boundary（IQ pair 的边界）
- **clk**：1 对 LVDS DDR，AD9363 → FPGA 的源同步时钟（DCLK）

控制总线另用 SPI（4 wire，clk/cs/mosi/miso），由 `axi_quad_spi` 在 PL 里出。

### I2. `axi_ad9361` IP 跟自己写 `ad9361_phy.v` 区别？

- **`axi_ad9361`** 是 ADI 官方 LogiCORE，处理 LVDS DDR 接收/发送 + IDELAY 校准 + 4-channel demux + AXI-Stream 输出 + AXI-Lite 控制接口。**Path A 用这个**
- **`ad9361_phy.v`** 是手写最小化的 LVDS 物理层 wrapper，只做 IDELAY + DDR de-serialize，不带 AXI。早期 Path X 阶段为了跳过 ADI HDL 复杂度而做的。**没在最终 build 里使用**

推荐：直接用 ADI 的 `axi_ad9361`，省时间。

### I3. IDELAY 是干什么的？

LVDS DDR 数据线在 PCB 上传输有 ~1-2 ns 延时差。IDELAYE2 让 FPGA 接收端在 ps 级别精度地推迟单根 wire 的采样时刻，对齐 6-wire 的 setup/hold window。`axi_ad9361` 自带 calibration FSM，板上跑一次后把 tap 值锁进 reg 即可。

`IDELAYCTRL` 给 IDELAYE2 提供 200 MHz 参考时钟（必需），需要在 BD 里独立例化。

### I4. 板上 idelay tap 值跑出来多少？

LDSDR 实测（每个 wire）通常在 8–15（5 bit tap，0..31，每 tap ~78 ps @ 200 MHz refclk）。具体数字每板不同（PCB 长度差异），所以一定要让 calibration FSM 在每次上电跑一次，不能 hard-code。

---

## J. plutosdr-fw 与 Linux 集成

### J1. plutosdr-fw 是什么？

ADI 维护的 PlutoSDR 完整 buildroot firmware：U-Boot + Linux kernel + ad9361 driver + libiio server + minimal rootfs。从源码 build 整出 `pluto.frm`（4 MB U-Boot + uImage + initramfs 打包），写到 PlutoSDR 的 mass storage 即可升级。

仓库：<https://github.com/analogdevicesinc/plutosdr-fw>

### J2. 为什么要把 plutosdr-fw 移植到 LDSDR？

PlutoSDR 原 firmware 默认 part 是 xc7z010clg225。LDSDR 是 clg400，需要：

1. 改 device tree（DTS）里所有 IO ball location 引用
2. 改 BD（system_top.v + system_bd.tcl）
3. 重新 build U-Boot（dtb 不同）+ Linux kernel（同 dtb）
4. 重新 bootgen 出 `pluto_new.frm`

### J3. clone 仓库要几 GB？

```bash
git clone --recursive https://github.com/analogdevicesinc/plutosdr-fw.git
# 完整 clone 约 4-5 GB（含子模块 buildroot + linux + u-boot + adi-hdl）
# 浅 clone：git clone --depth 1 --recurse-submodules --shallow-submodules
```

### J4. 编译机要装什么？

- Vivado 2024.2（带 Vitis）
- gcc-arm-linux-gnueabihf（cross compile）
- 30+ buildroot 必备：`flex bison libssl-dev u-boot-tools libtinfo5 libncurses5-dev`

具体到本工程：编译服务器 `eea@10.24.79.1:2424`，已配好整套 Vivado + Vitis + ARM toolchain（ref [reference_build_server.md](memory)）。

### J5. 怎么把自己的 ofdm_ldpc_top 集成进 plutosdr-fw 的 BD？

正在做（task #24）。计划：

1. 在 `plutosdr-fw/hdl/projects/pluto/` 加 `ofdm_ldpc_top.v` 等所有 RTL 源码
2. 改 `system_bd.tcl`，在 `axi_ad9361` 后加 `ofdm_ldpc_top` 实例（TX/RX 接到 axi_ad9361 的 sample stream port）
3. 加 EMIO GPIO 端口暴露调试位
4. 重新 build → `pluto_new.frm`
5. 板上 `iio_attr` 验证 RTL 能跑 + iio 驱动正常

### J6. `pluto.frm` 是怎么写到板子的？

PlutoSDR / LDSDR 启动后会暴露一个 USB Mass Storage 设备（4 MB FAT 分区）。挂载后把 `pluto_new.frm` 拷进去，**`eject`** 触发 firmware 自更新（U-Boot 内置的 `firmware update` 命令检测 `.frm` 写入后从 SD/QSPI 重写）。

```bash
# Linux 端：
cp pluto_new.frm /run/media/$USER/PlutoSDR/
udisksctl unmount -b /dev/sdX1
# 板子 LED 闪几下 → 重启 → 新固件生效
```

---

## K. 板上调试：JTAG / UART / EMIO

### K1. 没 UART 怎么 debug？

LDSDR 有 UART 但 build #1–8 时还没接通。当时全靠 EMIO GPIO_I 32-bit 寄存器：

```bash
# 启动后 PS Linux
cd /sys/class/gpio
echo 906 > export    # MIO 906 = EMIO bit 0
cat gpio906/value    # 读 pass_flag
```

或者更暴力——在 u-boot 里 `md` 直接读 GPIO controller 寄存器：

```
zynq-uboot> md.l 0xe000a060 1   # GPIO bank 2 input data
```

### K2. JTAG 能 debug PL 内部信号吗？

可以。Vivado ILA（Integrated Logic Analyzer）可以挂在 BD 任何 net 上：

```tcl
# 在 BD 里：
create_bd_cell -type ip -vlnv xilinx.com:ip:ila:6.2 ila_0
connect_bd_net [get_bd_pins ila_0/probe0] [get_bd_pins ofdm_ldpc_top/dbg_*]
```

下载完 bitstream 用 `vivado -mode gui` 打开 hardware manager，选 ILA core，trigger 设条件，dump 波形。**缺点**：ILA 占 BRAM，每路 1 K sample × 16 路用掉 1-2 个 RAMB36。

### K3. 编译机怎么传文件到板上？

```bash
# 1. 网络（千兆口）
scp BOOT.bin root@192.168.6.118:/media/BOOT/

# 2. JTAG（Xilinx xmd / xsct）
xsct
> conn -url tcp:localhost:3121
> dow BOOT.bin

# 3. SD 卡（最稳）
sudo dd if=BOOT.bin of=/dev/mmcblk0p1
```

### K4. 板上 iio 启动了怎么验证？

```bash
# 板上 shell
iio_info | head -30
# 应输出 ad9361-phy + cf-axi-adc + cf-axi-dac

# PC 端 libiio 远程
iio_attr -u "ip:192.168.2.1" -d ad9361-phy
```

如果 `iio_info` 报 "no devices"，先看 `dmesg | grep ad9361` 有无 SPI probe error。

---

## L. 已知限制与下一步工作

### L1. 当前最大 caveat 是什么？

**xfft_stub** 是组合 pass-through，不是真的 IFFT/FFT。所以现在的"频域操作"在数值上恒等于"时域操作"。RF SMA loop 通过完全靠 Path X Python 端做的真 IFFT/FFT，**HW PL 端不算真 OFDM 处理**。

下一步：替换 `xfft_stub.v` 为 Vivado FFT IP（`xfft_v9.1`，Pipelined Streaming，64-pt complex，Scaling=Unscaled），AXI-Stream 接口已经预留。

### L2. `channel_est` 现在跑的是什么模式？

`STREAM_MODE = 1`：寄存 pass-through，不做导频均衡。设这个的原因：数字 loopback 信道 H = 1，不需要均衡；先把数据通路打通。

`FRAME_MODE = 0`：用 4 个导频 bin 做最小二乘 H 估计 + 整 64 bin 除 H。RF 信道下要切回这个模式。

### L3. LDPC HB 矩阵 Z=64 一定对了吗？

Build #34 跑通 `pass_flag=1`，loopback 端到端成功 → 至少在数字回环里编/译码自洽。但严格的 minimum-distance + ACE check 没做，AWGN BER 曲线也没扫过。"通"和"商用品质"差很远。

### L4. 还需要做什么才算完整 firmware？

- [ ] FFT IP 替换 xfft_stub
- [ ] channel_est 切回 FRAME_MODE
- [ ] 把 ofdm_ldpc_top 集成进 plutosdr-fw BD（task #24）
- [ ] 完整 plutosdr-fw 构建（task #25）
- [ ] 板上 iio attr 验证（板上 ad9361 driver 跑起来 + PL 数字回环 EMIO `pass_flag=1`）
- [ ] AWGN 信道扫 BER 曲线 vs 理论 LDPC FER

---

## M. 故障排除 FAQ

### M1. `vivado -mode batch -source ...tcl` 中途报 "ERROR: [BD 41-758]"

意思是 BD validation 失败，通常因为某条 net 没接好或 IP 参数冲突。`run_ldsdr_digital.tcl` 在 BD 创建后调 `validate_bd_design` 强制校验，所以 console 上会有具体哪个 cell/pin 出错。

常见原因：

| 错误 | 原因 |
|------|------|
| "no driver" on `peripheral_aresetn` | proc_sys_reset 没接到 PS7 的 `FCLK_RESET0_N` |
| "interface mismatch" between `axi_dmac` and `axi_ad9361` | DMA TDATA width 设了 32 但 axi_ad9361 输出是 64 |
| "invalid clock domain" | axi_dmac s_axis_aclk 跟 m_axi_aclk 没接到同一个 clk |

### M2. 板子 USB 插上没 mass storage

按顺序排查：

1. UART log 看到 `firmware update started` 没？没 → FSBL 没启动 → BOOT.bin 写错位置
2. UART log 看到 U-Boot 提示符？没 → fsbl.elf 不对 / part 不匹配
3. U-Boot 跑过去了但 Linux 没启？kernel cmdline 里 init= 路径错了
4. Linux 启了但 `iio_info` 报 no devices？SPI driver probe 失败 → AD9363 reset_n / spi_cs 引脚约束错

### M3. xsim 跑到一半挂死

99% 是 RTL 写死循环没 timeout：

```verilog
while (!some_flag) begin
   // forgot to advance time
end
```

或者 testbench 没给 `$finish` 上限：

```verilog
initial begin
   #1_000_000;     // 1 ms 超时强制结束
   $display("TIMEOUT");
   $finish;
end
```

### M4. Path X Python 报 "iio.IIOError: Cannot connect"

依次检查：

```bash
ip a                                      # 192.168.2.10 有没有
ping -c 3 192.168.2.1                     # 板子在不在
iio_info -u "ip:192.168.2.1"              # libiio 直连
```

如果 ping 通但 iio 不通 → 板上 iiod 没启 → `ssh root@192.168.2.1 "ps ax | grep iiod"`。

### M5. `pass_flag=0` 但 `rx_done=1` 是什么状态？

数据通路通了，LDPC 译码器跑完了 BP，输出 `rx_decoded` 但是值不等于 `TEST_BITS`。原因 = LDPC HB 矩阵在 encoder/decoder 两边某个 entry 不一致 OR 矩阵对当前 Z 不合法。

排查办法：让 decoder 同时输出 `dbg_chllr_decoded`（ST_INIT 时的 raw hard-decision，512-bit），**绕过 BP** 直接判 LLR 符号。如果这个 raw 值对而 `rx_decoded` 错 → 就是 BP 没收敛到正解 → HB 矩阵问题。Build #34 就是这么定位的。

### M6. `rx_done=0` 卡死怎么深入？

EMIO 每 4 bit 一阶段，从 TX 到 RX 顺次往后看：

| EMIO bit | 信号 | 含义 |
|---|---|---|
| `dbg_enc_valid` | 编码器活了 |
| `dbg_ifft_valid` | mapper 输出 |
| `dbg_demod_cnt` | demod 计数 |
| `dbg_llr_done` | llr_buffer 攒满 |
| `dbg_eq_valid` | channel_est 有出 |
| `rx_done` | decoder 出过 valid |

哪一位 0 就在哪一级前面卡。Build #14–18 的 bug-hunt 全靠这个。

### M7. 时序报告 WNS 转正了但板上还是 demod_cnt 不够

`set_clock_groups -asynchronous` 用错了？或者 `set_false_path` 把关键 path 误标了？检查 `impl_1/timing_summary.rpt` 的 "Inter-Clock Paths" 部分，确认所有跨 clock domain 的 path 都过了。

如果 timing 真的没问题但 demod_cnt 仍少 ~20 个，可能是：
- `cp_remove` 的 frame_start 同步晚了几拍 → 第一个 symbol 丢了
- `channel_est` 在第一个符号给了假的 `valid=0` → 后面少 1 个 sym × 48 = 48 demod

提高 N_SYM（13、14）增加冗余余量是简单粗暴的修法（build #18 就这么做的）。

---

## 参考资料

- [README.md](./README.md) — 项目概览 + bug-hunt diary
- [lkh.md](./lkh.md) — 完整技术深潜（2788 行，22 章）
- [PHASE0_RF_VERIFY.md](./PHASE0_RF_VERIFY.md) — Path X RF verify 早期记录
- [path_a_archive/README.md](./path_a_archive/README.md) — Path A 归档说明
- 仿真目录 [simulation/](./simulation/) — 全套 RTL 框图、波形、时序、利用率图

---

*Last updated: 2026-05-08 · Build #34 PASS, Path X 0/32 errors, plutosdr-fw 移植进行中*
