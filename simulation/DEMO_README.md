# SDR7010 Live Demo — 一键演示

> 直观展示 LDSDR 7010 板上 OFDM+LDPC 跑通的状态:
> terminal 启动日志 + LED 状态 + HEX dump + 双通道示波器 + 8 块 metric tile。
> 默认零依赖、自动检测、无缝降级。

---

## 最简用法 (一键)

```bash
cd simulation
./demo.sh
```

或者跨平台:

```bash
python3 demo.py
```

会自动:
1. 启动本地 HTTP server (`http://localhost:8000`)
2. TCP 探测板子 `192.168.2.1:22` 是否在线
3. **板子在线** → 后台启动 `live_demo_bridge.py`,真实 EMIO 数据驱动面板
4. **板子离线** → REPLAY 模式 (HTML 内嵌真实启动序列)
5. 自动打开浏览器到 `live_demo.html`
6. **Ctrl+C 一键清理**所有后台进程

---

## 选项

| 命令 | 效果 |
|------|------|
| `./demo.sh` | 自动检测,在线 LIVE / 离线 REPLAY |
| `./demo.sh --replay` | 强制 REPLAY (跳过板子检测) |
| `./demo.sh --live` | 强制 LIVE (板子离线则报错退出) |
| `./demo.sh --board 192.168.3.140` | 自定义板子地址 |
| `./demo.sh --port 8080` | 自定义 HTTP 端口 |
| `./demo.sh --no-browser` | 不自动开浏览器 (服务器/远程模式) |
| `BOARD_HOST=10.0.0.5 ./demo.sh` | 用环境变量改板子 |

URL 参数 (覆盖自动检测):
- `live_demo.html?replay` — 强制 REPLAY
- `live_demo.html?live` — 强制 LIVE,失败不降级
- `live_demo.html?host=192.168.1.10&ws=8765` — 自定义 WS 地址 (远程访问)

---

## 三种运行模式

### REPLAY (零依赖,自包含)

只需浏览器,直接 `file://` 打开 `live_demo.html` 都行。
内嵌真实板上启动序列做 typing animation,5 秒一轮循环。
**适合**:演讲、GitHub Pages、面试、文档展示。

### LIVE (板子在线)

`demo.py` 会检测板子,自动起 `live_demo_bridge.py`:
- 10 Hz SSH 板子读 EMIO `0xE000A068`
- WebSocket 推送 JSON `{emio, rx_done, pass_flag, errors, ...}`
- HTML 自动连 `ws://localhost:8765`,所有 LED/HEX/示波器都用真实数据

需要装 `websockets`:
```bash
pip install --break-system-packages websockets
```

可选 `sshpass` (用密码登录板子,默认 `analog`):
```bash
sudo pacman -S sshpass    # arch/manjaro
sudo apt install sshpass  # debian/ubuntu
```

或者预先 SSH keypair (无密码):
```bash
ssh-copy-id root@192.168.2.1
```

### MOCK (调试 HTML 用)

不连板子,bridge 自己产生伪数据(rx_done 周期翻转、pass_flag 偶尔 flap):

```bash
MOCK=1 python3 live_demo_bridge.py    # 单独跑 bridge
# 或
MOCK=1 ./demo.sh --live --no-browser  # 完整 demo 但伪数据
```

---

## 文件清单

| 文件 | 作用 |
|------|------|
| `demo.sh` | bash 一键启动器 (透传 `python3 demo.py`) |
| `demo.py` | 核心启动器: HTTP + 探测 + bridge + 浏览器 + 清理 |
| `live_demo.html` | 自包含展示页面 (REPLAY / LIVE 自动检测) |
| `live_demo_bridge.py` | 板子 EMIO ↔ WebSocket 桥 |
| `live_demo_preview.png` | 截图预览 |

---

## 部署到 GitHub Pages

```
Settings → Pages → Source: main / simulation
访问 https://stongry.github.io/sdr7010/live_demo.html
```

GitHub Pages 上 WebSocket 连不到本地 (跨源),所以会自动降级到 REPLAY,
而不会报错。访客看到的就是 5 秒一轮循环的板上启动动画。

如果想给远程访客**实时**看你板子,把 WebSocket 桥暴露到公网:

```bash
# 简单:cloudflare tunnel
cloudflared tunnel --url ws://localhost:8765

# 然后访客打开
https://stongry.github.io/sdr7010/live_demo.html?host=YOUR_TUNNEL.trycloudflare.com&ws=443
```

---

## 故障排查

| 现象 | 原因 / 修复 |
|------|-----------|
| HTML 一直显示 detecting... | 浏览器禁用了 `ws://localhost`. 用 `?replay` |
| LIVE failed badge 红色 | bridge 没启动. 跑 `python3 live_demo_bridge.py` 单独看错误 |
| `[bridge] EMIO read failed` | 板子离线 / SSH 没设好. 装 sshpass 或 ssh-copy-id |
| 端口 8000 占用 | `./demo.sh --port 8080` |
| 浏览器没自动打开 | `./demo.sh --no-browser` 然后手动开 URL |
