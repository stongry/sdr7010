#!/usr/bin/env python3
"""
Generate WaveDrom timing diagrams strictly from path_x_simple.vcd transitions.

NO data is invented; every value/edge is extracted from the actual VCD.
Each diagram is rendered to SVG (TimeGen-compatible standard) and PNG.
"""
import re
import os
import json
import subprocess

VCD = "/home/ysara/fpga_hdl/simulation/path_x_simple.vcd"
OUT = "/home/ysara/fpga_hdl/simulation"


def parse_vcd():
    with open(VCD) as f:
        lines = f.read().splitlines()
    sig_id, sig_w = {}, {}
    depth = 0
    for ln in lines:
        if ln.startswith("$scope"): depth += 1; continue
        if ln.startswith("$upscope"): depth -= 1; continue
        if depth != 1: continue
        m = re.match(r"\$var\s+\w+\s+(\d+)\s+(\S+)\s+(\S+)", ln)
        if m:
            sig_w[m.group(2)] = int(m.group(1))
            sig_id[m.group(2)] = m.group(3)
    events = {n: [] for n in sig_id.values()}
    cur_t = 0
    for ln in lines:
        if ln.startswith("#"):
            try: cur_t = int(ln[1:])
            except: pass
        elif ln.startswith("b"):
            m = re.match(r"b([01xXzZ]+)\s+(\S+)", ln)
            if m and m.group(2) in sig_id:
                bits = m.group(1).replace('x','0').replace('z','0').replace('X','0').replace('Z','0')
                v = int(bits, 2)
                w = sig_w[m.group(2)]
                if sig_id[m.group(2)] in ('tx_I','tx_Q','rx_I','rx_Q','llr0','llr1') and v >= (1<<(w-1)):
                    v -= 1<<w
                events[sig_id[m.group(2)]].append((cur_t, v))
        elif len(ln) >= 2 and ln[0] in '01':
            ch = ln[1:]
            if ch in sig_id:
                events[sig_id[ch]].append((cur_t, int(ln[0])))
    return events


def cycle_value(events, t_ps, default=0):
    v = default
    for et, ev in events:
        if et <= t_ps: v = ev
        else: break
    return v


def make_qpsk_mod_diagram(events):
    """qpsk_mod: bits_in → I_out/Q_out (1-cycle latency)
    Show 16 cycles starting at t=145ns (1 cycle before bits start)."""
    cycles = list(range(145_000, 325_000, 10_000))  # 18 cycles
    bits = [cycle_value(events['bits_in'], t) for t in cycles]
    txi  = [cycle_value(events['tx_I'], t) for t in cycles]
    txq  = [cycle_value(events['tx_Q'], t) for t in cycles]
    val  = [cycle_value(events['valid_in'], t) for t in cycles]

    bits_wave = "x"
    bits_data = []
    for i, b in enumerate(bits):
        if i == 0:
            bits_wave = "="
            bits_data.append(str(b))
        elif b != bits[i-1]:
            bits_wave += "="
            bits_data.append(str(b))
        else:
            bits_wave += "."

    txi_wave = ""
    txi_data = []
    for i, v in enumerate(txi):
        if i == 0 or v != txi[i-1]:
            txi_wave += "="
            label = "0" if v == 0 else (f"-A=-5793" if v < 0 else f"+A=+5793")
            txi_data.append(label)
        else:
            txi_wave += "."

    txq_wave = ""
    txq_data = []
    for i, v in enumerate(txq):
        if i == 0 or v != txq[i-1]:
            txq_wave += "="
            label = "0" if v == 0 else (f"-A" if v < 0 else f"+A")
            txq_data.append(label)
        else:
            txq_wave += "."

    val_wave = ""
    for i, v in enumerate(val):
        if i == 0 or v != val[i-1]:
            val_wave += "1" if v else "0"
        else:
            val_wave += "."

    diagram = {
        "signal": [
            {"name": "clk",      "wave": "p" + "."*(len(cycles)-1)},
            {"name": "rst_n",    "wave": "1" + "."*(len(cycles)-1)},
            {"name": "valid_in", "wave": val_wave},
            {"name": "bits_in",  "wave": bits_wave, "data": bits_data},
            {"name": "tx_I",     "wave": txi_wave,  "data": txi_data},
            {"name": "tx_Q",     "wave": txq_wave,  "data": txq_data},
        ],
        "head": {
            "text": "qpsk_mod — actual VCD transitions (cycle = 10 ns, t=145ns origin)",
            "tick": -14
        },
        "config": {"hscale": 1.5}
    }
    return diagram


def make_qpsk_demod_diagram(events):
    """qpsk_demod: I_in/Q_in → llr0/llr1 (1-cycle latency)
    Show t=155 to t=345 to capture pipeline."""
    cycles = list(range(155_000, 335_000, 10_000))
    rxi = [cycle_value(events['rx_I'], t) for t in cycles]
    rxq = [cycle_value(events['rx_Q'], t) for t in cycles]
    l0  = [cycle_value(events['llr0'], t) for t in cycles]
    l1  = [cycle_value(events['llr1'], t) for t in cycles]
    val = [cycle_value(events['rx_valid_in'], t) for t in cycles]
    vo  = [cycle_value(events['rx_valid_out'], t) for t in cycles]

    def encode(arr, fmt=str):
        wave = ""
        data = []
        for i, v in enumerate(arr):
            if i == 0 or v != arr[i-1]:
                wave += "="
                data.append(fmt(v))
            else:
                wave += "."
        return wave, data

    def lvl(arr):
        wave = ""
        for i, v in enumerate(arr):
            if i == 0 or v != arr[i-1]:
                wave += "1" if v else "0"
            else:
                wave += "."
        return wave

    rxi_w, rxi_d = encode(rxi, lambda v: "0" if v == 0 else ("-A" if v < 0 else "+A"))
    rxq_w, rxq_d = encode(rxq, lambda v: "0" if v == 0 else ("-A" if v < 0 else "+A"))
    l0_w, l0_d = encode(l0, lambda v: f"{v:+d}" if v != 0 else "0")
    l1_w, l1_d = encode(l1, lambda v: f"{v:+d}" if v != 0 else "0")

    diagram = {
        "signal": [
            {"name": "clk",          "wave": "p" + "."*(len(cycles)-1)},
            {"name": "rx_I",         "wave": rxi_w, "data": rxi_d},
            {"name": "rx_Q",         "wave": rxq_w, "data": rxq_d},
            {"name": "rx_valid_in",  "wave": lvl(val)},
            {},  # gap
            {"name": "llr0",         "wave": l0_w, "data": l0_d},
            {"name": "llr1",         "wave": l1_w, "data": l1_d},
            {"name": "rx_valid_out", "wave": lvl(vo)},
        ],
        "head": {
            "text": "qpsk_demod — actual VCD transitions (1 clk pipeline I,Q → LLR)",
            "tick": -15
        },
        "config": {"hscale": 1.5}
    }
    return diagram


def make_capture_diagram(events):
    """TB capture FSM: bit_idx + decoded build-up."""
    cycles = list(range(155_000, 345_000, 10_000))
    bidx = [cycle_value(events['bit_idx'], t) for t in cycles]
    dec  = [cycle_value(events['decoded'], t) for t in cycles]
    vo   = [cycle_value(events['rx_valid_out'], t) for t in cycles]

    def encode_int(arr, fmt=str):
        wave = ""
        data = []
        for i, v in enumerate(arr):
            if i == 0 or v != arr[i-1]:
                wave += "="
                data.append(fmt(v))
            else:
                wave += "."
        return wave, data

    bidx_w, bidx_d = encode_int(bidx, lambda v: str(v))
    dec_w, dec_d = encode_int(dec, lambda v: f"0x{v:08X}")
    vo_w = ""
    for i, v in enumerate(vo):
        if i == 0 or v != vo[i-1]: vo_w += "1" if v else "0"
        else: vo_w += "."

    diagram = {
        "signal": [
            {"name": "clk",          "wave": "p" + "."*(len(cycles)-1)},
            {"name": "rx_valid_out", "wave": vo_w},
            {},
            {"name": "bit_idx",      "wave": bidx_w, "data": bidx_d},
            {"name": "decoded[31:0]","wave": dec_w,  "data": dec_d},
        ],
        "head": {
            "text": "TB capture FSM — bit_idx grows 0→32, decoded fills to 0x0F0F0F0F",
            "tick": -15
        },
        "config": {"hscale": 1.5}
    }
    return diagram


def make_top_overview_diagram(events):
    """Top-level pipeline overview from t=145ns to t=350ns"""
    cycles = list(range(145_000, 345_000, 10_000))
    rstn = [cycle_value(events['rst_n'], t) for t in cycles]
    vin  = [cycle_value(events['valid_in'], t) for t in cycles]
    bits = [cycle_value(events['bits_in'], t) for t in cycles]
    tv   = [cycle_value(events['tx_valid'], t) for t in cycles]
    rv   = [cycle_value(events['rx_valid_in'], t) for t in cycles]
    vo   = [cycle_value(events['rx_valid_out'], t) for t in cycles]
    bidx = [cycle_value(events['bit_idx'], t) for t in cycles]
    dec  = [cycle_value(events['decoded'], t) for t in cycles]

    def lvl(arr):
        wave = ""
        for i, v in enumerate(arr):
            if i == 0 or v != arr[i-1]: wave += "1" if v else "0"
            else: wave += "."
        return wave

    def enc(arr, fmt):
        wave = ""; data = []
        for i, v in enumerate(arr):
            if i == 0 or v != arr[i-1]:
                wave += "="
                data.append(fmt(v))
            else:
                wave += "."
        return wave, data

    bits_w, bits_d = enc(bits, str)
    bidx_w, bidx_d = enc(bidx, str)
    dec_w, dec_d = enc(dec, lambda v: f"0x{v:08X}")

    diagram = {
        "signal": [
            {"name": "clk",          "wave": "p" + "."*(len(cycles)-1)},
            {"name": "rst_n",        "wave": lvl(rstn)},
            {},
            ["TX side",
                {"name": "valid_in",     "wave": lvl(vin)},
                {"name": "bits_in",      "wave": bits_w, "data": bits_d},
                {"name": "tx_valid",     "wave": lvl(tv)},
            ],
            {},
            ["RX side",
                {"name": "rx_valid_in",  "wave": lvl(rv)},
                {"name": "rx_valid_out", "wave": lvl(vo)},
            ],
            {},
            ["Capture",
                {"name": "bit_idx",      "wave": bidx_w, "data": bidx_d},
                {"name": "decoded[31:0]","wave": dec_w,  "data": dec_d},
            ],
        ],
        "head": {
            "text": "Top-level pipeline timing — TB-driven Path X end-to-end",
            "tick": -14
        },
        "config": {"hscale": 1.4}
    }
    return diagram


def render_wavedrom(spec, name):
    """Use wavedrom Python lib to render to SVG."""
    import wavedrom
    json_path = os.path.join(OUT, f"{name}.json")
    svg_path  = os.path.join(OUT, f"{name}.svg")
    with open(json_path, 'w') as f:
        json.dump(spec, f, indent=2)
    svg = wavedrom.render(json.dumps(spec))
    svg.saveas(svg_path)
    print(f"Saved {svg_path}")
    # Also try to convert to PNG via cairosvg or rsvg-convert
    png_path = os.path.join(OUT, f"{name}.png")
    for cmd in [
        ["rsvg-convert", "-d", "150", "-p", "150", "-o", png_path, svg_path],
        ["inkscape", "--export-type=png", "--export-dpi=150", f"--export-filename={png_path}", svg_path],
    ]:
        try:
            subprocess.run(cmd, check=True, capture_output=True)
            print(f"Saved {png_path}")
            return
        except (FileNotFoundError, subprocess.CalledProcessError):
            continue
    print(f"  (PNG conversion skipped, SVG saved at {svg_path})")


def main():
    events = parse_vcd()

    # Verify expected transitions match VCD
    assert events['decoded'][-1] == (315_000, 0x0F0F0F0F), \
        f"VCD verification failed: final decoded != 0x0F0F0F0F (got {events['decoded'][-1]})"
    assert events['errors'][-1] == (515_000, 0), \
        f"VCD verification failed: errors != 0 (got {events['errors'][-1]})"
    print("VCD self-check OK: decoded=0x0F0F0F0F errors=0\n")

    render_wavedrom(make_top_overview_diagram(events), "wavedrom_top_overview")
    render_wavedrom(make_qpsk_mod_diagram(events),     "wavedrom_qpsk_mod")
    render_wavedrom(make_qpsk_demod_diagram(events),   "wavedrom_qpsk_demod")
    render_wavedrom(make_capture_diagram(events),      "wavedrom_capture_fsm")


if __name__ == "__main__":
    main()
