// =============================================================================
// ofdm_ldpc_pl.v — PL logic module for Zynq Block Design module reference
//
// Ports: ONLY clk and rst_n (from PS7 FCLK0 / FCLK_RESET0_N).
// All wide buses (tx_info_bits[511:0], rx_decoded[511:0], etc.) are INTERNAL.
// This avoids placing those buses as physical IOs.
//
// Test flow: auto-start after reset → TX encode → OFDM → TX→RX loopback
//            → OFDM demod → LDPC decode → pass/fail latch.
// pass_flag and rx_done observable via JTAG ILA in Vivado Hardware Manager.
// =============================================================================

`timescale 1ns/1ps

module ofdm_ldpc_pl (
    input  wire clk,
    input  wire rst_n_ext,
    output wire pass_flag,
    output wire rx_done,
    output wire heartbeat,       // alive indicator (clk/2^25) - to LED
    output wire por_alive,       // POR done flag (kept for backward compat)
    output wire tx_started,      // tx_valid_in fired
    output wire tx_streaming,    // tx_valid_out has been high
    output wire dbg_enc_seen,    // ldpc_encoder produced enc_valid_out at any point
    output wire dbg_ifft_seen,   // tx_subcarrier_map produced ifft_tvalid at any point
    output wire dbg_cp_rem_seen, // cp_remove produced cp_rem_tvalid
    output wire dbg_fft_m_seen,  // FFT produced fft_m_tvalid
    output wire dbg_eq_seen,     // channel_est produced eq_valid_out
    output wire dbg_llr_done_seen, // llr_buffer assembled
    // demod_valid count threshold bits: [5]=>32, [7]=>128, [9]=>512
    output wire [15:0] dbg_demod_cnt_o, // full demod_valid count
    output wire [11:0] dbg_ifft_cnt_o   // ifft_tvalid count [11:0]
);

// ── Power-on reset: PL config initializes regs to 0, naturally generates ──
// ── a reset pulse for ~1024 cycles after fpga_manager bitstream load. ────
(* INIT = "16'h0000" *) reg [15:0] por_cnt = 16'h0000;
reg por_done = 1'b0;
always @(posedge clk) begin
    if (!por_done) begin
        if (por_cnt == 16'd1023)
            por_done <= 1'b1;
        else
            por_cnt <= por_cnt + 1'b1;
    end
end
// Combine PL POR with external rst_n: rst_n=1 only when both POR done AND ext released
wire rst_n = por_done & rst_n_ext;

// ── Fixed 512-bit test pattern ─────────────────────────────────────────────
localparam [511:0] TEST_BITS = {
    32'hDEADBEEF, 32'hCAFEBABE, 32'h01234567, 32'h89ABCDEF,
    32'hDEADBEEF, 32'hCAFEBABE, 32'h01234567, 32'h89ABCDEF,
    32'hDEADBEEF, 32'hCAFEBABE, 32'h01234567, 32'h89ABCDEF,
    32'hDEADBEEF, 32'hCAFEBABE, 32'h01234567, 32'h89ABCDEF,
    32'hA5A5A5A5, 32'h5A5A5A5A, 32'hF0F0F0F0, 32'h0F0F0F0F,
    32'hA5A5A5A5, 32'h5A5A5A5A, 32'hF0F0F0F0, 32'h0F0F0F0F,
    32'hA5A5A5A5, 32'h5A5A5A5A, 32'hF0F0F0F0, 32'h0F0F0F0F,
    32'hA5A5A5A5, 32'h5A5A5A5A, 32'hF0F0F0F0, 32'h0F0F0F0F
};

// ── Internal wires ─────────────────────────────────────────────────────────
wire        tx_start;
wire [15:0] tx_iq_i, tx_iq_q;
wire        tx_valid_out;
wire [511:0] rx_decoded;
wire         rx_valid_out;
wire         dbg_enc_valid;
wire         dbg_ifft_valid;
wire         dbg_cp_rem_valid;
wire         dbg_fft_m_valid;
wire         dbg_eq_valid;
wire         dbg_demod_valid;
wire         dbg_llr_done;

// ── Auto-start: one-shot pulse 1000 cycles after reset ────────────────────
startup_gen #(.DELAY(1000)) u_gen (
    .clk      (clk),
    .rst_n    (rst_n),
    .pulse_out(tx_start)
);

// ── RX frame sync: rising edge of tx_valid_out ────────────────────────────
reg tx_valid_d1;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) tx_valid_d1 <= 1'b0;
    else        tx_valid_d1 <= tx_valid_out;
end
wire rx_frame_start = tx_valid_out & ~tx_valid_d1;

// ── OFDM+LDPC datapath (TX→RX loopback) ──────────────────────────────────
(* KEEP_HIERARCHY = "TRUE" *)
(* DONT_TOUCH = "TRUE" *)
ofdm_ldpc_top u_top (
    .clk            (clk),
    .rst_n          (rst_n),
    .tx_info_bits   (TEST_BITS),
    .tx_valid_in    (tx_start),
    .tx_iq_i        (tx_iq_i),
    .tx_iq_q        (tx_iq_q),
    .tx_valid_out   (tx_valid_out),
    // TX→RX loopback
    .rx_iq_i        (tx_iq_i),
    .rx_iq_q        (tx_iq_q),
    .rx_valid_in    (tx_valid_out),
    .rx_frame_start (rx_frame_start),
    .rx_decoded     (rx_decoded),
    .rx_valid_out   (rx_valid_out),
    .dbg_enc_valid    (dbg_enc_valid),
    .dbg_ifft_valid   (dbg_ifft_valid),
    .dbg_cp_rem_valid (dbg_cp_rem_valid),
    .dbg_fft_m_valid  (dbg_fft_m_valid),
    .dbg_eq_valid     (dbg_eq_valid),
    .dbg_demod_valid  (dbg_demod_valid),
    .dbg_llr_done     (dbg_llr_done)
);

// Latch debug pulses so PS can sample them via EMIO
(* DONT_TOUCH = "TRUE" *) reg dbg_enc_seen_r      = 0;
(* DONT_TOUCH = "TRUE" *) reg dbg_ifft_seen_r     = 0;
(* DONT_TOUCH = "TRUE" *) reg dbg_cp_rem_seen_r   = 0;
(* DONT_TOUCH = "TRUE" *) reg dbg_fft_m_seen_r    = 0;
(* DONT_TOUCH = "TRUE" *) reg dbg_eq_seen_r       = 0;
(* DONT_TOUCH = "TRUE" *) reg dbg_llr_done_seen_r = 0;
// Counters for bottleneck analysis
(* DONT_TOUCH = "TRUE" *) reg [15:0] dbg_demod_cnt = 0;
(* DONT_TOUCH = "TRUE" *) reg [15:0] dbg_ifft_cnt  = 0;
always @(posedge clk) begin
    if (dbg_enc_valid)    dbg_enc_seen_r      <= 1'b1;
    if (dbg_ifft_valid)   dbg_ifft_seen_r     <= 1'b1;
    if (dbg_cp_rem_valid) dbg_cp_rem_seen_r   <= 1'b1;
    if (dbg_fft_m_valid)  dbg_fft_m_seen_r    <= 1'b1;
    if (dbg_eq_valid)     dbg_eq_seen_r       <= 1'b1;
    if (dbg_llr_done)     dbg_llr_done_seen_r <= 1'b1;
    if (dbg_demod_valid)  dbg_demod_cnt       <= dbg_demod_cnt + 1'b1;
    if (dbg_ifft_valid)   dbg_ifft_cnt        <= dbg_ifft_cnt  + 1'b1;
end
assign dbg_enc_seen      = dbg_enc_seen_r;
assign dbg_ifft_seen     = dbg_ifft_seen_r;
assign dbg_cp_rem_seen   = dbg_cp_rem_seen_r;
assign dbg_fft_m_seen    = dbg_fft_m_seen_r;
assign dbg_eq_seen       = dbg_eq_seen_r;
assign dbg_llr_done_seen = dbg_llr_done_seen_r;
assign dbg_demod_cnt_o = dbg_demod_cnt[15:0];
assign dbg_ifft_cnt_o  = dbg_ifft_cnt[11:0];

// ── Pass/fail latch (output ports for EMIO GPIO read by PS) ──────────────
(* DONT_TOUCH = "TRUE" *) reg pass_flag_r;
(* DONT_TOUCH = "TRUE" *) reg rx_done_r;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        pass_flag_r <= 1'b0;
        rx_done_r   <= 1'b0;
    end else if (rx_valid_out && !rx_done_r) begin
        pass_flag_r <= (rx_decoded == TEST_BITS);
        rx_done_r   <= 1'b1;
    end
end

assign pass_flag = pass_flag_r;
assign rx_done   = rx_done_r;

// ── Debug heartbeat (clk div 2^25 ≈ 3 Hz @ 100MHz, easy to see toggle)
(* DONT_TOUCH = "TRUE" *) reg [25:0] hb_cnt = 0;
always @(posedge clk) hb_cnt <= hb_cnt + 1;
assign heartbeat = hb_cnt[25];

// POR alive
assign por_alive = por_done;

// TX started latch
(* DONT_TOUCH = "TRUE" *) reg tx_started_r = 0;
(* DONT_TOUCH = "TRUE" *) reg tx_streaming_r = 0;
always @(posedge clk) begin
    if (tx_start) tx_started_r <= 1'b1;
    if (tx_valid_out) tx_streaming_r <= 1'b1;
end
assign tx_started   = tx_started_r;
assign tx_streaming = tx_streaming_r;

endmodule
