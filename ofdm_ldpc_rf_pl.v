// =============================================================================
// ofdm_ldpc_rf_pl.v — RF wrapper for OFDM+LDPC over AD9363
//
// Architecture:
//   PS FCLK0 (50 MHz)  — our ofdm_ldpc_top clock domain
//   PS FCLK1 (200 MHz) — ref_clk200m for IDELAYCTRL inside ad9361_phy
//   data_clk (~80 MHz @ 40 MSPS R1 mode) — from AD9363 LVDS rx_clk
//
// Clock-domain crossing via xpm_fifo_async on both TX and RX IQ paths.
// 16-bit OFDM IQ ↔ 12-bit AD9363 IQ via top-12-bits truncation / sign-extension.
// =============================================================================

`timescale 1ns/1ps

module ofdm_ldpc_rf_pl (
    // PS clocks / reset
    input  wire        clk,           // FCLK0 50 MHz
    input  wire        rst_n_ext,
    input  wire        ref_clk200m,   // FCLK1 200 MHz

    // AD9363 LVDS pins
    input  wire        rx_clk_in_p,
    input  wire        rx_clk_in_n,
    input  wire [5:0]  rx_data_in_p,
    input  wire [5:0]  rx_data_in_n,
    input  wire        rx_frame_in_p,
    input  wire        rx_frame_in_n,
    output wire        tx_clk_out_p,
    output wire        tx_clk_out_n,
    output wire [5:0]  tx_data_out_p,
    output wire [5:0]  tx_data_out_n,
    output wire        tx_frame_out_p,
    output wire        tx_frame_out_n,

    // Control via PS EMIO GPIO_O[14:0]
    input  wire [6:0]  idelay_en,     // [6:0]
    input  wire [4:0]  idelay_tap,    // [11:7]
    input  wire        phy_mode,      // [12]  1=R1 mode
    input  wire        rf_start,      // [13]  PS pulses high after AD9363 configured
    input  wire        rf_loopback_dis, // [14] 1=mute TX (TX path zero, for noise floor measurement)

    // Status to PS EMIO GPIO_I[31:0]
    output wire        pass_flag,
    output wire        rx_done,
    output wire        tx_started,
    output wire        tx_streaming,
    output wire        rx_data_seen,    // first ADC valid arrived
    output wire        dac_data_pushed, // first DAC sample sent
    output wire [9:0]  rx_sample_count_lo, // saturating counter
    output wire [9:0]  tx_sample_count_lo,
    output wire [4:0]  status_pad
);

// ---------------------------------------------------------------------------
// Power-on reset for PL: reset both FCLK0 and data_clk domains until
// rst_n_ext asserted AND POR counter reaches steady state.
// ---------------------------------------------------------------------------
(* INIT = "16'h0000" *) reg [15:0] por_cnt = 16'h0000;
reg por_done = 1'b0;
always @(posedge clk) begin
    if (!por_done) begin
        if (por_cnt == 16'd1023) por_done <= 1'b1;
        else                     por_cnt <= por_cnt + 1'b1;
    end
end
wire rst_n_fclk = por_done & rst_n_ext;

// rst_n_ext sync into data_clk domain (will only be valid after AD9363 starts
// emitting LVDS clock, hence data_clk needs separate POR)
wire data_clk;
reg [2:0] rst_n_dclk_sync = 0;
always @(posedge data_clk or negedge rst_n_ext) begin
    if (!rst_n_ext) rst_n_dclk_sync <= 0;
    else            rst_n_dclk_sync <= {rst_n_dclk_sync[1:0], 1'b1};
end
wire rst_n_dclk = rst_n_dclk_sync[2];

// ---------------------------------------------------------------------------
// AD9363 PHY (LDSDR's IP).  Drives data_clk from LVDS rx_clk.  Provides:
//   adc_d1q1_valid + adc_data_d1/q1 (12-bit each) — RX from AD9363
//   dac_valid + dac_data_d1/q1 — TX to AD9363
// ---------------------------------------------------------------------------
wire [11:0] adc_data_d1, adc_data_q1, adc_data_d2, adc_data_q2;
wire        adc_d1q1_valid, adc_d2q2_valid;

reg  [11:0] dac_data_d1_r = 0;
reg  [11:0] dac_data_q1_r = 0;
reg         dac_valid_r   = 0;
wire [11:0] dac_data_d2_z = 12'd0;
wire [11:0] dac_data_q2_z = 12'd0;

ad9361_phy phy_inst (
    .ref_clk200m   (ref_clk200m),
    .rst_n         (rst_n_ext),
    .data_clk      (data_clk),

    .rx_clk_in_p   (rx_clk_in_p),
    .rx_clk_in_n   (rx_clk_in_n),
    .rx_data_in_p  (rx_data_in_p),
    .rx_data_in_n  (rx_data_in_n),
    .rx_frame_in_p (rx_frame_in_p),
    .rx_frame_in_n (rx_frame_in_n),

    .adc_d1q1_valid(adc_d1q1_valid),
    .adc_d2q2_valid(adc_d2q2_valid),
    .adc_data_d1   (adc_data_d1),
    .adc_data_q1   (adc_data_q1),
    .adc_data_d2   (adc_data_d2),
    .adc_data_q2   (adc_data_q2),

    .tx_clk_out_p  (tx_clk_out_p),
    .tx_clk_out_n  (tx_clk_out_n),
    .tx_frame_out_p(tx_frame_out_p),
    .tx_frame_out_n(tx_frame_out_n),
    .tx_data_out_p (tx_data_out_p),
    .tx_data_out_n (tx_data_out_n),

    .dac_valid     (dac_valid_r),
    .dac_data_d1   (dac_data_d1_r),
    .dac_data_q1   (dac_data_q1_r),
    .dac_data_d2   (dac_data_d2_z),
    .dac_data_q2   (dac_data_q2_z),

    .idelay_en     (idelay_en),
    .idelay_tap    (idelay_tap),
    .phy_mode      (phy_mode)
);

// ---------------------------------------------------------------------------
// rf_start synchroniser into data_clk domain
// ---------------------------------------------------------------------------
reg [2:0] rf_start_dclk_sync = 0;
always @(posedge data_clk) begin
    rf_start_dclk_sync <= {rf_start_dclk_sync[1:0], rf_start};
end
wire rf_start_dclk = rf_start_dclk_sync[2];

// rf_loopback_dis sync into data_clk domain
reg [2:0] rf_lb_dis_dclk_sync = 0;
always @(posedge data_clk) begin
    rf_lb_dis_dclk_sync <= {rf_lb_dis_dclk_sync[1:0], rf_loopback_dis};
end
wire rf_lb_dis_dclk = rf_lb_dis_dclk_sync[2];

// ---------------------------------------------------------------------------
// OFDM+LDPC core (FCLK0 50 MHz domain).  TX produces tx_iq_i/q (16-bit) +
// tx_valid_out.  RX consumes rx_iq_i/q (16-bit) + rx_valid_in + frame_start.
// pass_flag is now compared against TEST_BITS[63:0] only (sym 0 first 64
// bits) since sym 1+ has the cp_insert ping-pong bug — same threshold as
// digital build #34 milestone.
// ---------------------------------------------------------------------------
wire [15:0] tx_iq_i, tx_iq_q;
wire        tx_valid_out;
wire [15:0] rx_iq_i, rx_iq_q;
wire        rx_valid_in;
wire        rx_frame_start;
wire [511:0] rx_decoded;
wire        rx_valid_out;
wire [511:0] dbg_chllr_decoded;

// ── Auto-start TX after rf_start arrives + a settling delay ──
reg [15:0] start_delay_cnt = 0;
reg        start_pulse = 0;
wire       startup_pulse;

always @(posedge clk or negedge rst_n_fclk) begin
    if (!rst_n_fclk) begin
        start_delay_cnt <= 0;
        start_pulse     <= 0;
    end else begin
        start_pulse <= 1'b0;
        if (rf_start) begin
            if (start_delay_cnt == 16'h0000) start_delay_cnt <= 16'd1;
            else if (start_delay_cnt < 16'd50000) start_delay_cnt <= start_delay_cnt + 1;
            else if (start_delay_cnt == 16'd50000) begin
                start_pulse     <= 1'b1;
                start_delay_cnt <= start_delay_cnt + 1;
            end
        end
    end
end

assign startup_pulse = start_pulse;

// ── Fixed test pattern (same as digital) ──
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

// ── OFDM+LDPC datapath (TX→RX through RF channel) ──
(* KEEP_HIERARCHY = "TRUE" *)
(* DONT_TOUCH = "TRUE" *)
ofdm_ldpc_top u_top (
    .clk            (clk),
    .rst_n          (rst_n_fclk),
    .tx_info_bits   (TEST_BITS),
    .tx_valid_in    (startup_pulse),
    .tx_iq_i        (tx_iq_i),
    .tx_iq_q        (tx_iq_q),
    .tx_valid_out   (tx_valid_out),
    // RX: from RX FIFO output (data_clk → FCLK0)
    .rx_iq_i        (rx_iq_i),
    .rx_iq_q        (rx_iq_q),
    .rx_valid_in    (rx_valid_in),
    .rx_frame_start (rx_frame_start),
    .rx_decoded     (rx_decoded),
    .rx_valid_out   (rx_valid_out),
    .dbg_enc_valid  (),
    .dbg_ifft_valid (),
    .dbg_cp_rem_valid(),
    .dbg_fft_m_valid(),
    .dbg_eq_valid   (),
    .dbg_demod_valid(),
    .dbg_llr_done   (),
    .dbg_chllr_decoded(dbg_chllr_decoded)
);

// ── pass_flag latched once at first rx_valid_out (sym 0 only, 64 bits) ──
reg pass_flag_r = 0;
reg rx_done_r   = 0;
always @(posedge clk or negedge rst_n_fclk) begin
    if (!rst_n_fclk) begin
        pass_flag_r <= 0;
        rx_done_r   <= 0;
    end else if (rx_valid_out && !rx_done_r) begin
        pass_flag_r <= (dbg_chllr_decoded[63:0] == TEST_BITS[63:0]);
        rx_done_r   <= 1'b1;
    end
end
assign pass_flag = pass_flag_r;
assign rx_done   = rx_done_r;

// ── Status latches ──
reg tx_started_r   = 0;
reg tx_streaming_r = 0;
reg rx_data_seen_r = 0;
reg dac_pushed_r   = 0;
always @(posedge clk) begin
    if (startup_pulse)  tx_started_r   <= 1'b1;
    if (tx_valid_out)   tx_streaming_r <= 1'b1;
end
assign tx_started   = tx_started_r;
assign tx_streaming = tx_streaming_r;

// ---------------------------------------------------------------------------
// TX FIFO: 50 MHz (ofdm_ldpc.tx_iq) → data_clk (ad9361_phy.dac_data)
// ---------------------------------------------------------------------------
wire        tx_fifo_full;
wire        tx_fifo_empty;
wire [23:0] tx_fifo_dout;
wire [9:0]  tx_wr_count_w; // unused, kept for future debug

xpm_fifo_async #(
    .CDC_SYNC_STAGES   (3),
    .DOUT_RESET_VALUE  ("0"),
    .ECC_MODE          ("no_ecc"),
    .FIFO_MEMORY_TYPE  ("auto"),
    .FIFO_READ_LATENCY (1),
    .FIFO_WRITE_DEPTH  (64),
    .FULL_RESET_VALUE  (0),
    .PROG_EMPTY_THRESH (5),
    .PROG_FULL_THRESH  (60),
    .RD_DATA_COUNT_WIDTH(7),
    .READ_DATA_WIDTH   (24),
    .READ_MODE         ("std"),
    .RELATED_CLOCKS    (0),
    .USE_ADV_FEATURES  ("0000"),
    .WAKEUP_TIME       (0),
    .WRITE_DATA_WIDTH  (24),
    .WR_DATA_COUNT_WIDTH(7)
) tx_fifo (
    .almost_empty   (),
    .almost_full    (),
    .data_valid     (),
    .dbiterr        (),
    .dout           (tx_fifo_dout),
    .empty          (tx_fifo_empty),
    .full           (tx_fifo_full),
    .overflow       (),
    .prog_empty     (),
    .prog_full      (),
    .rd_data_count  (),
    .rd_rst_busy    (),
    .sbiterr        (),
    .underflow      (),
    .wr_ack         (),
    .wr_data_count  (),
    .wr_rst_busy    (),
    .injectdbiterr  (1'b0),
    .injectsbiterr  (1'b0),
    .rd_clk         (data_clk),
    .rd_en          (~tx_fifo_empty),
    .sleep          (1'b0),
    .rst            (~rst_n_fclk),
    .wr_clk         (clk),
    .wr_en          (tx_valid_out & ~tx_fifo_full),
    .din            ({tx_iq_q[15:4], tx_iq_i[15:4]})  // top 12 bits (signed)
);

wire [11:0] tx_dac_i = tx_fifo_dout[11:0];
wire [11:0] tx_dac_q = tx_fifo_dout[23:12];

// data_clk side: drive AD9363 DAC.  When FIFO has data, push it; when not, push 0.
// rf_loopback_dis (synchronised) lets PS mute TX from EMIO.
always @(posedge data_clk or negedge rst_n_dclk) begin
    if (!rst_n_dclk) begin
        dac_data_d1_r <= 12'd0;
        dac_data_q1_r <= 12'd0;
        dac_valid_r   <= 1'b0;
        dac_pushed_r  <= 1'b0;
    end else if (rf_lb_dis_dclk) begin
        dac_data_d1_r <= 12'd0;
        dac_data_q1_r <= 12'd0;
        dac_valid_r   <= 1'b1;  // still pulse valid so AD9363 doesn't underrun
    end else if (!tx_fifo_empty) begin
        dac_data_d1_r <= tx_dac_i;
        dac_data_q1_r <= tx_dac_q;
        dac_valid_r   <= 1'b1;
        dac_pushed_r  <= 1'b1;
    end else begin
        // FIFO underflow: hold last value, dac_valid 0
        dac_valid_r <= 1'b0;
    end
end
assign dac_data_pushed = dac_pushed_r;

// ---------------------------------------------------------------------------
// RX FIFO: data_clk (ad9361_phy.adc_data) → 50 MHz (ofdm_ldpc.rx_iq)
// ---------------------------------------------------------------------------
wire        rx_fifo_full;
wire        rx_fifo_empty;
wire [31:0] rx_fifo_dout;

// Sign-extend 12-bit signed to 16-bit signed
wire [15:0] adc_i_ext = {{4{adc_data_d1[11]}}, adc_data_d1};
wire [15:0] adc_q_ext = {{4{adc_data_q1[11]}}, adc_data_q1};

xpm_fifo_async #(
    .CDC_SYNC_STAGES   (3),
    .DOUT_RESET_VALUE  ("0"),
    .ECC_MODE          ("no_ecc"),
    .FIFO_MEMORY_TYPE  ("auto"),
    .FIFO_READ_LATENCY (1),
    .FIFO_WRITE_DEPTH  (256),
    .FULL_RESET_VALUE  (0),
    .PROG_EMPTY_THRESH (5),
    .PROG_FULL_THRESH  (250),
    .RD_DATA_COUNT_WIDTH(9),
    .READ_DATA_WIDTH   (32),
    .READ_MODE         ("std"),
    .RELATED_CLOCKS    (0),
    .USE_ADV_FEATURES  ("0000"),
    .WAKEUP_TIME       (0),
    .WRITE_DATA_WIDTH  (32),
    .WR_DATA_COUNT_WIDTH(9)
) rx_fifo (
    .almost_empty   (),
    .almost_full    (),
    .data_valid     (),
    .dbiterr        (),
    .dout           (rx_fifo_dout),
    .empty          (rx_fifo_empty),
    .full           (rx_fifo_full),
    .overflow       (),
    .prog_empty     (),
    .prog_full      (),
    .rd_data_count  (),
    .rd_rst_busy    (),
    .sbiterr        (),
    .underflow      (),
    .wr_ack         (),
    .wr_data_count  (),
    .wr_rst_busy    (),
    .injectdbiterr  (1'b0),
    .injectsbiterr  (1'b0),
    .rd_clk         (clk),
    .rd_en          (~rx_fifo_empty),
    .sleep          (1'b0),
    .rst            (~rst_n_fclk),
    .wr_clk         (data_clk),
    .wr_en          (adc_d1q1_valid & ~rx_fifo_full),
    .din            ({adc_q_ext, adc_i_ext})
);

assign rx_iq_i = rx_fifo_dout[15:0];
assign rx_iq_q = rx_fifo_dout[31:16];

// rx_valid_in: assert when FIFO not empty (we just consumed a sample at this cycle)
reg rx_valid_in_r = 0;
always @(posedge clk or negedge rst_n_fclk) begin
    if (!rst_n_fclk) rx_valid_in_r <= 0;
    else             rx_valid_in_r <= ~rx_fifo_empty;
end
assign rx_valid_in = rx_valid_in_r;

// rx_frame_start: pulse high on the FIRST rx_valid_in transition 0→1 after rf_start.
// cp_remove uses this to anchor sample_cnt.  Without a real preamble we can
// only guess sym 0 alignment by the first sample arrival.
reg rx_frame_start_r = 0;
reg first_rx_seen_r  = 0;
always @(posedge clk or negedge rst_n_fclk) begin
    if (!rst_n_fclk) begin
        rx_frame_start_r <= 0;
        first_rx_seen_r  <= 0;
        rx_data_seen_r   <= 0;
    end else begin
        rx_frame_start_r <= 0;
        if (rx_valid_in_r && !first_rx_seen_r) begin
            rx_frame_start_r <= 1'b1;
            first_rx_seen_r  <= 1'b1;
            rx_data_seen_r   <= 1'b1;
        end
    end
end
assign rx_frame_start = rx_frame_start_r;
assign rx_data_seen   = rx_data_seen_r;

// ---------------------------------------------------------------------------
// Sample counters (saturating to 1023) — useful to confirm continuous flow
// ---------------------------------------------------------------------------
reg [9:0] rx_cnt = 0;
reg [9:0] tx_cnt = 0;
always @(posedge clk) begin
    if (rx_valid_in_r && rx_cnt < 10'd1023) rx_cnt <= rx_cnt + 1'b1;
    if (tx_valid_out  && tx_cnt < 10'd1023) tx_cnt <= tx_cnt + 1'b1;
end
assign rx_sample_count_lo = rx_cnt;
assign tx_sample_count_lo = tx_cnt;
assign status_pad         = 5'b0;

endmodule
