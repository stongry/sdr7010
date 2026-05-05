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

// TX sample capture
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
    rx_iq_i        = 16'h0;
    rx_iq_q        = 16'h0;
    rx_valid_in    = 0;
    rx_frame_start = 0;
    fifo_rd_ptr    = 11'd0;
    rx_sample_cnt  = 0;
    rx_done        = 0;
    bit_errors     = 0;

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

    // ---- Wait for TX samples to accumulate in FIFO ----
    // Expected: 11 symbols × 80 samples = 880 TX samples
    // Encoding latency: ~34 cycles, then streaming ~11*64 = 704 IFFT inputs
    // Total with pipeline: allow up to 2000 cycles.
    timeout_cnt = 0;
    while (fifo_count < 880 && timeout_cnt < 15000) begin
        @(posedge clk);
        timeout_cnt = timeout_cnt + 1;
    end

    if (fifo_count < 880) begin
        $display("[%0t] WARNING: Only %0d TX samples captured (expected 880). Proceeding with available.", $time, fifo_count);
    end else begin
        $display("[%0t] INFO: %0d TX samples captured in loopback FIFO.", $time, fifo_count);
    end

    // ---- Assert frame_start to synchronise RX ----
    total_rx_samples = fifo_count;

    @(posedge clk);
    rx_frame_start = 1;
    rx_valid_in    = 1;
    // Feed first sample on same cycle as frame_start
    if (NOISE_ENABLE) begin
        rx_iq_i = add_noise(fifo_i[0], NOISE_SCALE);
        rx_iq_q = add_noise(fifo_q[0], NOISE_SCALE);
    end else begin
        rx_iq_i = fifo_i[0];
        rx_iq_q = fifo_q[0];
    end
    fifo_rd_ptr = 1;
    @(posedge clk);
    rx_frame_start = 0;

    $display("[%0t] INFO: RX replay started, driving %0d samples.", $time, total_rx_samples);

    // ---- Stream remaining RX samples ----
    for (i = 1; i < total_rx_samples; i = i + 1) begin
        if (NOISE_ENABLE) begin
            rx_iq_i = add_noise(fifo_i[i], NOISE_SCALE);
            rx_iq_q = add_noise(fifo_q[i], NOISE_SCALE);
        end else begin
            rx_iq_i = fifo_i[i];
            rx_iq_q = fifo_q[i];
        end
        rx_valid_in = 1;
        @(posedge clk);
        if (i % 80 == 0)
            $display("[%0t] INFO: RX symbol %0d / %0d started.", $time, i/80, 11);
    end
    rx_valid_in = 0;
    rx_iq_i     = 16'h0;
    rx_iq_q     = 16'h0;

    $display("[%0t] INFO: All RX samples driven. Waiting for decoder...", $time);

    // ---- Wait for RX decoded output ----
    timeout_cnt = 0;
    while (!rx_valid_out && timeout_cnt < 200000) begin
        @(posedge clk);
        timeout_cnt = timeout_cnt + 1;
    end

    if (!rx_valid_out) begin
        $display("[%0t] ERROR: Decoder timed out! rx_valid_out never asserted.", $time);
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
