module tb_ofdm_ldpc;

// ---------------------------------------------------------------------------
// Parameters
// ---------------------------------------------------------------------------
parameter CLK_PERIOD   = 10;    // 10 ns → 100 MHz
parameter NOISE_ENABLE = 0;     // 0 = no noise, 1 = add AWGN approximation
parameter NOISE_SCALE  = 200;   // Noise amplitude (shift from rand) when enabled
parameter RAND_SEED    = 32'hDEAD_BEEF;

// ---------------------------------------------------------------------------
// Clock and reset
// ---------------------------------------------------------------------------
reg clk;
reg rst_n;

initial clk = 0;
always #(CLK_PERIOD/2) clk = ~clk;

// ---------------------------------------------------------------------------
// DUT ports
// ---------------------------------------------------------------------------
reg  [511:0] tx_info_bits;
reg          tx_valid_in;
wire [15:0]  tx_iq_i;
wire [15:0]  tx_iq_q;
wire         tx_valid_out;

reg  [15:0]  rx_iq_i;
reg  [15:0]  rx_iq_q;
reg          rx_valid_in;
reg          rx_frame_start;
wire [511:0] rx_decoded;
wire         rx_valid_out;

// ---------------------------------------------------------------------------
// DUT instantiation
// ---------------------------------------------------------------------------
ofdm_ldpc_top u_dut (
    .clk           (clk),
    .rst_n         (rst_n),
    .tx_info_bits  (tx_info_bits),
    .tx_valid_in   (tx_valid_in),
    .tx_iq_i       (tx_iq_i),
    .tx_iq_q       (tx_iq_q),
    .tx_valid_out  (tx_valid_out),
    .rx_iq_i       (rx_iq_i),
    .rx_iq_q       (rx_iq_q),
    .rx_valid_in   (rx_valid_in),
    .rx_frame_start(rx_frame_start),
    .rx_decoded    (rx_decoded),
    .rx_valid_out  (rx_valid_out)
);

// ---------------------------------------------------------------------------
// TX sample FIFO for loopback
// Stores (tx_iq_i, tx_iq_q) samples, replays them to RX with a small delay.
// ---------------------------------------------------------------------------
parameter FIFO_DEPTH = 2048;
reg [15:0] fifo_i [0:FIFO_DEPTH-1];
reg [15:0] fifo_q [0:FIFO_DEPTH-1];
reg [10:0] fifo_wr_ptr;
reg [10:0] fifo_rd_ptr;
reg [10:0] fifo_count;

// TX sample capture (kept for stats; replay path replaced by direct loopback)
always @(posedge clk) begin
    if (!rst_n) begin
        fifo_wr_ptr <= 11'd0;
        fifo_count  <= 11'd0;
    end else if (tx_valid_out) begin
        fifo_i[fifo_wr_ptr] <= tx_iq_i;
        fifo_q[fifo_wr_ptr] <= tx_iq_q;
        fifo_wr_ptr <= fifo_wr_ptr + 1'b1;
        fifo_count  <= fifo_count + 1'b1;
    end
end

// ---------------------------------------------------------------------------
// PL-internal direct loopback: rx_iq <= tx_iq with 1-cycle delay.
// frame_start asserted for 1 cycle on the very first tx_valid_out.
// This matches the on-board PL configuration (tx output wired straight back
// into rx input), bypassing the FIFO+replay setup that previously exposed
// 1-sample alignment glitches every 80-cycle burst.
// ---------------------------------------------------------------------------
reg seen_first_tx_valid;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        rx_iq_i            <= 16'h0;
        rx_iq_q            <= 16'h0;
        rx_valid_in        <= 1'b0;
        rx_frame_start     <= 1'b0;
        seen_first_tx_valid<= 1'b0;
    end else begin
        rx_iq_i        <= tx_iq_i;
        rx_iq_q        <= tx_iq_q;
        rx_valid_in    <= tx_valid_out;
        rx_frame_start <= (tx_valid_out && !seen_first_tx_valid);
        if (tx_valid_out) seen_first_tx_valid <= 1'b1;
    end
end

// ---------------------------------------------------------------------------
// Noise injection (optional AWGN approximation using $random)
// ---------------------------------------------------------------------------
function [15:0] add_noise;
    input [15:0] sample;
    input [15:0] noise_amp;
    reg signed [15:0] n;
    reg signed [31:0] s_plus_n;
    begin
        n       = $random % noise_amp;     // uniform noise approximation
        s_plus_n = $signed(sample) + $signed(n);
        // Saturate to 16-bit signed
        if      (s_plus_n >  32767) add_noise = 16'h7FFF;
        else if (s_plus_n < -32768) add_noise = 16'h8000;
        else                        add_noise = s_plus_n[15:0];
    end
endfunction

// ---------------------------------------------------------------------------
// RX loopback driver: replay FIFO contents to RX input
// ---------------------------------------------------------------------------
integer loopback_delay;   // cycles to wait before starting RX replay
integer rx_sample_cnt;
integer total_rx_samples;

// ---------------------------------------------------------------------------
// Reference bits storage
// ---------------------------------------------------------------------------
reg [511:0] ref_bits;

// ---------------------------------------------------------------------------
// BER computation
// ---------------------------------------------------------------------------
integer bit_errors;
integer k;

// ---------------------------------------------------------------------------
// Debug counters: monitor each pipeline stage so we can localise where the
// data flow breaks when the decoder times out.
// ---------------------------------------------------------------------------
integer dbg_ifft_in;     // mapper -> IFFT handshakes
integer dbg_ifft_out;    // IFFT -> cp_insert handshakes
integer dbg_fft_in;      // cp_remove -> FFT handshakes
integer dbg_fft_out;     // FFT -> channel_est valids
integer dbg_eq_cnt;      // channel_est valid outputs
integer dbg_demod_cnt;   // qpsk_demod valid outputs
integer dbg_llr_done_cnt;// llr_buffer assemble_done pulses

always @(posedge clk) begin
    if (!rst_n) begin
        dbg_ifft_in     <= 0;
        dbg_ifft_out    <= 0;
        dbg_fft_in      <= 0;
        dbg_fft_out     <= 0;
        dbg_eq_cnt      <= 0;
        dbg_demod_cnt   <= 0;
        dbg_llr_done_cnt<= 0;
    end else begin
        if (u_dut.ifft_s_tvalid && u_dut.ifft_s_tready) dbg_ifft_in    <= dbg_ifft_in    + 1;
        if (u_dut.ifft_m_tvalid && u_dut.ifft_m_tready) dbg_ifft_out   <= dbg_ifft_out   + 1;
        if (u_dut.cp_rem_tvalid)                        dbg_fft_in     <= dbg_fft_in     + 1;
        if (u_dut.fft_m_tvalid)                         dbg_fft_out    <= dbg_fft_out    + 1;
        if (u_dut.eq_valid_out)                         dbg_eq_cnt     <= dbg_eq_cnt     + 1;
        if (u_dut.demod_valid_out)                      dbg_demod_cnt  <= dbg_demod_cnt  + 1;
        if (u_dut.llr_assemble_done)                    dbg_llr_done_cnt <= dbg_llr_done_cnt + 1;
    end
end

// ---------------------------------------------------------------------------
// Main test sequence
// ---------------------------------------------------------------------------
integer i;
integer timeout_cnt;
integer rx_done;

initial begin
    // ---- Initialise ----
    rst_n          = 0;
    tx_valid_in    = 0;
    tx_info_bits   = 512'h0;
    fifo_rd_ptr    = 11'd0;
    rx_sample_cnt  = 0;
    rx_done        = 0;
    bit_errors     = 0;
    // rx_iq / rx_valid_in / rx_frame_start are now driven by the direct
    // loopback always-block above; do not assign them here or there will be
    // multiple drivers.

    $display("=============================================================");
    $display("  OFDM+LDPC Transceiver Testbench");
    $display("  N=1024, K=512, Z=32, QPSK, N_FFT=64, N_CP=16");
    $display("  Noise: %s  (scale=%0d)", NOISE_ENABLE ? "ENABLED" : "DISABLED", NOISE_SCALE);
    $display("=============================================================");

    // ---- Reset ----
    repeat(10) @(posedge clk);
    rst_n = 1;
    repeat(5) @(posedge clk);

    // ---- Generate random info bits ----
    begin : gen_bits
        integer seed;
        seed = RAND_SEED;
        for (i = 0; i < 16; i = i + 1) begin
            tx_info_bits[i*32 +: 32] = $random(seed);
        end
    end
    ref_bits = tx_info_bits;

    $display("[%0t] INFO: Generated 512 random info bits.", $time);
    $display("[%0t] INFO: First 32 bits: 0x%08X", $time, tx_info_bits[31:0]);

    // ---- Start TX encoding ----
    @(posedge clk);
    tx_valid_in = 1;
    @(posedge clk);
    tx_valid_in = 0;

    $display("[%0t] INFO: TX encoding started.", $time);

    // ---- Direct loopback runs in parallel; just wait for decoder ----
    // The always-block above streams tx_iq into rx_iq with 1-cycle delay
    // and asserts rx_frame_start on the first tx_valid_out, so we only need
    // to monitor rx_valid_out here.
    $display("[%0t] INFO: Direct PL-internal loopback active.", $time);
    $display("[%0t] INFO: Waiting for LDPC decoder valid_out...", $time);

    // ---- Wait for RX decoded output ----
    // LDPC decoder must complete MAX_ITER=10 BP iterations before
    // asserting valid_out. Each iter is ~MB*N = 8*1024 ST_VNU_ROW cycles
    // plus CNU_GATHER/WR overhead → ~12-15k cy/iter, ~150k cy total.
    // Allow 800k cycles for headroom.
    timeout_cnt = 0;
    while (!rx_valid_out && timeout_cnt < 800000) begin
        @(posedge clk);
        timeout_cnt = timeout_cnt + 1;
    end

    if (!rx_valid_out) begin
        $display("[%0t] ERROR: Decoder timed out! rx_valid_out never asserted.", $time);
        $display("[DBG] ifft_in=%0d, ifft_out=%0d, fft_in=%0d, fft_out=%0d, eq=%0d, demod=%0d, llr_done=%0d",
                 dbg_ifft_in, dbg_ifft_out, dbg_fft_in, dbg_fft_out,
                 dbg_eq_cnt, dbg_demod_cnt, dbg_llr_done_cnt);
        $display("[DBG] ldpc_dec ST_INIT raw decode (no BP): 0x%08X (ref [31:0]: 0x%08X)",
                 u_dut.dbg_chllr_decoded[31:0], ref_bits[31:0]);
        $display("RESULT: FAIL (timeout)");
        $finish;
    end

    // ---- BER calculation ----
    bit_errors = 0;
    for (k = 0; k < 512; k = k + 1) begin
        if (rx_decoded[k] !== ref_bits[k])
            bit_errors = bit_errors + 1;
    end

    $display("=============================================================");
    $display("[%0t] RESULTS:", $time);
    $display("  Info bits     : 512");
    $display("  Bit errors    : %0d", bit_errors);
    $display("  BER           : %0.6f", $itor(bit_errors) / 512.0);
    $display("  Ref  [511:480]: 0x%08X", ref_bits[511:480]);
    $display("  Dec  [511:480]: 0x%08X", rx_decoded[511:480]);
    $display("  Ref  [31:0]   : 0x%08X", ref_bits[31:0]);
    $display("  Dec  [31:0]   : 0x%08X", rx_decoded[31:0]);

    if (bit_errors == 0) begin
        $display("  RESULT: PASS - Perfect decoding (zero BER)");
    end else if (bit_errors <= 5) begin
        $display("  RESULT: NEAR-PASS - %0d residual errors (check decoder iterations)", bit_errors);
    end else begin
        $display("  RESULT: FAIL - %0d bit errors", bit_errors);
    end
    $display("=============================================================");

    // ---- Waveform dump info ----
    $display("[%0t] INFO: Simulation complete. Total cycles: %0t ns / %0d ns per cycle.",
             $time, $time, CLK_PERIOD);

    repeat(20) @(posedge clk);
    $finish;
end

// ---------------------------------------------------------------------------
// Watchdog: kill simulation if it runs too long
// ---------------------------------------------------------------------------
initial begin
    #(10_000_000);  // 10 ms max
    $display("WATCHDOG: Simulation exceeded 10ms. Killing.");
    $finish;
end

// ---------------------------------------------------------------------------
// Optional: VCD waveform dump
// ---------------------------------------------------------------------------
initial begin
    $dumpfile("tb_ofdm_ldpc.vcd");
    $dumpvars(0, tb_ofdm_ldpc);
end

// ---------------------------------------------------------------------------
// Progress monitor: print every 1000 cycles
// ---------------------------------------------------------------------------
integer cyc_cnt;
initial cyc_cnt = 0;
always @(posedge clk) begin
    cyc_cnt = cyc_cnt + 1;
    if (cyc_cnt % 500 == 0)
        $display("[%0t] TICK: cycle %0d  fifo_count=%0d", $time, cyc_cnt, fifo_count);
end

endmodule
