// =============================================================================
// tb_path_x.v — Vivado xsim testbench mirroring the Path X RF experiment
//
// Path X (verified on real LDSDR hardware, 0/32 bit errors over RF):
//   - Generate one OFDM symbol carrying TEST_BITS[31:0] = 0x0F0F0F0F
//   - QPSK map (PILOT_A=5793) onto 48 data bins (skip pilots 7,21,43,57; nulls 0,27..37)
//   - IFFT64 + CP16 → 80 IQ samples
//   - Loop back through digital channel
//   - cp_remove → FFT64 → channel_est → rx_demap → qpsk_demod
//   - Compare lowest 32 bits of recovered LLR hard-decisions against TEST_BITS[31:0]
//
// This TB drives the same `ofdm_ldpc_top` DUT used in build #34 (digital pass=1).
// We use the SAME TEST_BITS pattern as Path X (0x0F0F0F0F at bits [31:0]) and
// check that `dbg_chllr_decoded[31:0]` recovers it exactly.
//
// Run:
//   vivado -mode batch -source compile_tb_path_x.tcl
// or in xsim direct:
//   xvlog tb_path_x.v ofdm_ldpc_top.v ldpc_encoder.v ldpc_decoder.v \
//         qpsk_mod.v qpsk_demod.v cp_insert.v cp_remove.v channel_est.v \
//         tx_subcarrier_map.v rx_subcarrier_demap.v llr_assembler.v \
//         llr_buffer.v xfft_stub.v
//   xelab tb_path_x -debug typical
//   xsim tb_path_x -tclbatch run.tcl
// =============================================================================
`timescale 1ns/1ps

module tb_path_x;

// ── Parameters ─────────────────────────────────────────────────────────────
parameter CLK_PERIOD = 10;            // 100 MHz
parameter [31:0] TEST_BITS_LO = 32'h0F0F0F0F;  // Path X expected pattern

// 512-bit info field: low 32 bits = TEST_BITS_LO (rest 0).  After LDPC
// encoding this maps into the OFDM symbol stream identically to how the
// Python Path X script puts those 32 bits into the first OFDM symbol.
//
// NOTE: ofdm_ldpc_top includes LDPC encode/decode internally.  Path X
// (Python) skipped LDPC and just hard-mapped QPSK over the data bins.
// Both paths, however, place TEST_BITS_LO at the SAME 32 LLR positions
// at the receiver — `dbg_chllr_decoded[31:0]` matches in either case.

// ── Clock / reset ──────────────────────────────────────────────────────────
reg clk = 0;
reg rst_n = 0;
always #(CLK_PERIOD/2) clk = ~clk;

// ── DUT signals ────────────────────────────────────────────────────────────
reg  [511:0] tx_info_bits;
reg          tx_valid_in;
wire [15:0]  tx_iq_i, tx_iq_q;
wire         tx_valid_out;

reg  [15:0]  rx_iq_i, rx_iq_q;
reg          rx_valid_in;
reg          rx_frame_start;
wire [511:0] rx_decoded;
wire         rx_valid_out;

wire dbg_enc_valid, dbg_ifft_valid, dbg_cp_rem_valid;
wire dbg_fft_m_valid, dbg_eq_valid, dbg_demod_valid, dbg_llr_done;
wire [511:0] dbg_chllr_decoded;

ofdm_ldpc_top u_dut (
    .clk            (clk),
    .rst_n          (rst_n),
    .tx_info_bits   (tx_info_bits),
    .tx_valid_in    (tx_valid_in),
    .tx_iq_i        (tx_iq_i),
    .tx_iq_q        (tx_iq_q),
    .tx_valid_out   (tx_valid_out),
    .rx_iq_i        (rx_iq_i),
    .rx_iq_q        (rx_iq_q),
    .rx_valid_in    (rx_valid_in),
    .rx_frame_start (rx_frame_start),
    .rx_decoded     (rx_decoded),
    .rx_valid_out   (rx_valid_out),
    .dbg_enc_valid    (dbg_enc_valid),
    .dbg_ifft_valid   (dbg_ifft_valid),
    .dbg_cp_rem_valid (dbg_cp_rem_valid),
    .dbg_fft_m_valid  (dbg_fft_m_valid),
    .dbg_eq_valid     (dbg_eq_valid),
    .dbg_demod_valid  (dbg_demod_valid),
    .dbg_llr_done     (dbg_llr_done),
    .dbg_chllr_decoded(dbg_chllr_decoded)
);

// ── TX→RX digital loopback FIFO (same as build #34 digital test) ──────────
parameter FIFO_DEPTH = 2048;
reg [15:0] fifo_i [0:FIFO_DEPTH-1];
reg [15:0] fifo_q [0:FIFO_DEPTH-1];
reg [10:0] fifo_wr_ptr = 0;
reg [10:0] fifo_count  = 0;

always @(posedge clk) begin
    if (!rst_n) begin
        fifo_wr_ptr <= 0;
        fifo_count  <= 0;
    end else if (tx_valid_out) begin
        fifo_i[fifo_wr_ptr] <= tx_iq_i;
        fifo_q[fifo_wr_ptr] <= tx_iq_q;
        fifo_wr_ptr <= fifo_wr_ptr + 1;
        fifo_count  <= fifo_count + 1;
    end
end

// ── Sample counters ───────────────────────────────────────────────────────
integer  i;
integer  timeout_cnt;
integer  bit_errors;
reg [10:0] rx_rd_ptr;
reg [31:0] decoded_lo;

// ── Waveform dump (VCD for xsim / GTKWave) ─────────────────────────────────
initial begin
    $dumpfile("path_x.vcd");
    $dumpvars(0, tb_path_x);
end

// ── Stimulus ───────────────────────────────────────────────────────────────
initial begin
    $display("==============================================================");
    $display("  Path X simulation — OFDM digital loopback for TEST_BITS_LO");
    $display("  Mirrors the verified RF experiment (0/32 bit errors).");
    $display("  TEST_BITS_LO = 0x%08X", TEST_BITS_LO);
    $display("==============================================================");

    tx_info_bits   = 512'h0;
    tx_info_bits[31:0] = TEST_BITS_LO;
    tx_valid_in    = 0;
    rx_iq_i        = 16'h0;
    rx_iq_q        = 16'h0;
    rx_valid_in    = 0;
    rx_frame_start = 0;
    rx_rd_ptr      = 0;

    // Reset
    repeat (10) @(posedge clk);
    rst_n = 1;
    repeat (5) @(posedge clk);

    // Trigger TX
    @(posedge clk);
    tx_valid_in = 1;
    @(posedge clk);
    tx_valid_in = 0;
    $display("[%0t ns] TX info_bits[31:0] = 0x%08X loaded.", $time, tx_info_bits[31:0]);

    // Wait for first 80 samples of symbol 0 in the FIFO
    timeout_cnt = 0;
    while (fifo_count < 80 && timeout_cnt < 5000) begin
        @(posedge clk);
        timeout_cnt = timeout_cnt + 1;
    end
    if (fifo_count < 80) begin
        $display("[%0t ns] FAIL: TX did not produce 80 samples in time.", $time);
        $finish;
    end
    $display("[%0t ns] TX produced %0d IQ samples for symbol 0.", $time, fifo_count);

    // Wait until full frame (11 symbols * 80 = 960) for clean RX demap
    while (fifo_count < 960 && timeout_cnt < 15000) begin
        @(posedge clk);
        timeout_cnt = timeout_cnt + 1;
    end
    $display("[%0t ns] TX produced %0d IQ samples (full frame).", $time, fifo_count);

    // Drive RX with frame_start + samples from FIFO
    @(posedge clk);
    rx_frame_start = 1;
    rx_valid_in    = 1;
    rx_iq_i        = fifo_i[0];
    rx_iq_q        = fifo_q[0];
    rx_rd_ptr      = 1;
    @(posedge clk);
    rx_frame_start = 0;

    // Stream the rest
    for (i = 1; i < 960; i = i + 1) begin
        rx_iq_i = fifo_i[rx_rd_ptr];
        rx_iq_q = fifo_q[rx_rd_ptr];
        rx_rd_ptr = rx_rd_ptr + 1;
        @(posedge clk);
    end
    rx_valid_in = 0;
    rx_iq_i = 0;
    rx_iq_q = 0;

    // Wait for RX pipeline to settle (channel_est, demap, llr)
    timeout_cnt = 0;
    while (!dbg_llr_done && timeout_cnt < 50000) begin
        @(posedge clk);
        timeout_cnt = timeout_cnt + 1;
        if ((timeout_cnt & 16'h1FFF) == 0)
            $display("[%0t ns] waiting for llr_done (cycle=%0d)", $time, timeout_cnt);
    end
    if (!dbg_llr_done) begin
        $display("[%0t ns] FAIL: dbg_llr_done never asserted.", $time);
        $finish;
    end
    $display("[%0t ns] RX llr_done. dbg_chllr_decoded[63:0]=0x%016X", $time, dbg_chllr_decoded[63:0]);

    // Check Path X criterion: low 32 bits of decoded LLR hard-decisions
    decoded_lo = dbg_chllr_decoded[31:0];
    bit_errors = 0;
    for (i = 0; i < 32; i = i + 1) begin
        if (decoded_lo[i] !== TEST_BITS_LO[i])
            bit_errors = bit_errors + 1;
    end

    $display("==============================================================");
    $display("  decoded[31:0] = 0x%08X", decoded_lo);
    $display("  expected[31:0]= 0x%08X", TEST_BITS_LO);
    $display("  bit errors    = %0d / 32", bit_errors);
    if (bit_errors == 0)
        $display("  *** PASS *** Path X simulation matches RF result (0/32).");
    else
        $display("  *** FAIL *** %0d bit errors.", bit_errors);
    $display("==============================================================");

    repeat (50) @(posedge clk);
    $finish;
end

// Watchdog
initial begin
    #5000000;
    $display("[%0t ns] WATCHDOG TIMEOUT", $time);
    $finish;
end

endmodule
