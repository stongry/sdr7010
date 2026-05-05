// =============================================================================
// ofdm_ldpc_rf_top.v — OFDM+LDPC with real AD9363 RF interface
//
// Architecture:
//   startup_gen → ofdm_ldpc_top TX → [TX CDC FIFO] → ad9363_cmos_if → AD9363
//   AD9363 → ad9363_cmos_if → [RX CDC FIFO] → ofdm_ldpc_top RX → pass_flag
//
// Clock domains:
//   fclk   : 100 MHz from PS7 FCLK_CLK0 (ofdm_ldpc_top domain)
//   ad_clk : ~61.44 MHz from AD9363 rx_clk_in (ad9363_cmos_if domain)
//   CDC via xpm_fifo_async (Vivado XPM macros, no IP catalog needed)
//
// AD9363 control signals are tied for FDD (TX+RX simultaneous) operation.
// The AD9363 must be pre-configured by the original PlutoSDR firmware before
// this bitstream is loaded.
//
// TX→RX synchronisation:
//   When TX starts, after N_SYNC_DELAY AD9363 samples, frame_start is pulsed.
//   This compensates for TX→RX pipeline delay (~8-12 samples over cable).
//   Default N_SYNC_DELAY = 8; adjust via parameter if needed.
// =============================================================================
`timescale 1ns/1ps

module ofdm_ldpc_rf_top #(
    parameter N_SYNC_DELAY = 8    // AD9363 samples to skip before frame_start
)(
    // ── PS7 clock / reset ─────────────────────────────────────────────────
    input  wire fclk,             // 100 MHz
    input  wire rst_n,            // Active-low from PS7 FCLK_RESET0_N

    // ── AD9363 CMOS pins (to top-level / XDC) ────────────────────────────
    input  wire        rx_clk_in,
    input  wire        rx_frame_in,
    input  wire [11:0] rx_data_in,
    output wire        tx_clk_out,
    output wire        tx_frame_out,
    output wire [11:0] tx_data_out,

    // ── AD9363 control (FDD, always-on) ──────────────────────────────────
    output wire        enable,        // 1 = enabled
    output wire        txnrx,         // 1 = FDD TX+RX
    // gpio_resetb and gpio_en_agc are driven directly by PS7 EMIO GPIO[13:12]
    // (Linux ad9361 driver expects to control reset/agc via these pins)

    // ── Results to PS EMIO GPIO ───────────────────────────────────────────
    output wire        pass_flag,
    output wire        rx_done
);

// ── AD9363 control: FDD mode, always enabled ──────────────────────────────
assign enable = 1'b1;
assign txnrx  = 1'b1;

// ── AD9363 CMOS interface ─────────────────────────────────────────────────
wire        ad_clk;          // Buffered rx_clk (~61.44 MHz)
wire [11:0] ad_rx_i, ad_rx_q;
wire        ad_rx_valid;
wire [11:0] ad_tx_i, ad_tx_q;
wire        ad_tx_read;      // Pulsed when TX FIFO should output next pair

ad9363_cmos_if u_cmos (
    .rx_clk_in  (rx_clk_in),
    .rx_frame_in(rx_frame_in),
    .rx_data_in (rx_data_in),
    .tx_clk_out (tx_clk_out),
    .tx_frame_out(tx_frame_out),
    .tx_data_out(tx_data_out),
    .data_clk   (ad_clk),
    .rx_i       (ad_rx_i),
    .rx_q       (ad_rx_q),
    .rx_valid   (ad_rx_valid),
    .tx_i       (ad_tx_i),
    .tx_q       (ad_tx_q),
    .tx_read    (ad_tx_read)
);

// ── RX CDC FIFO: ad_clk write → fclk read ────────────────────────────────
// {rx_i[11:0], rx_q[11:0]} = 24 bits
wire [23:0] rx_fifo_dout;
wire        rx_fifo_empty, rx_fifo_full;
wire        rx_rd_en;

xpm_fifo_async #(
    .FIFO_WRITE_DEPTH   (512),
    .FIFO_READ_LATENCY  (0),
    .READ_MODE          ("fwft"),
    .FIFO_MEMORY_TYPE   ("auto"),
    .CDC_SYNC_STAGES    (2),
    .FULL_RESET_VALUE   (0),
    .USE_ADV_FEATURES   ("0000"),
    .RELATED_CLOCKS     (0),
    .SIM_ASSERT_CHK     (0),
    .WAKEUP_TIME        (0),
    .WRITE_DATA_WIDTH   (24),
    .READ_DATA_WIDTH    (24),
    .WR_DATA_COUNT_WIDTH(10),
    .RD_DATA_COUNT_WIDTH(10)
) u_rx_cdc (
    .wr_clk     (ad_clk),
    .wr_en      (ad_rx_valid),
    .din        ({ad_rx_i, ad_rx_q}),
    .rd_clk     (fclk),
    .rd_en      (rx_rd_en),
    .dout       (rx_fifo_dout),
    .empty      (rx_fifo_empty),
    .full       (rx_fifo_full),
    .rst        (~rst_n),
    .overflow   (),
    .underflow  (),
    .wr_rst_busy(),
    .rd_rst_busy(),
    .almost_empty(),
    .almost_full(),
    .wr_data_count(),
    .rd_data_count(),
    .sleep      (1'b0),
    .injectdbiterr(1'b0),
    .injectsbiterr(1'b0),
    .dbiterr    (),
    .sbiterr    ()
);

// ── TX CDC FIFO: fclk write → ad_clk read ────────────────────────────────
// {tx_i[11:0], tx_q[11:0]} = 24 bits
wire [23:0] tx_fifo_dout;
wire        tx_fifo_empty, tx_fifo_full;
wire        tx_wr_en;
wire [23:0] tx_fifo_din;

xpm_fifo_async #(
    .FIFO_WRITE_DEPTH   (2048),
    .FIFO_READ_LATENCY  (0),
    .READ_MODE          ("fwft"),
    .FIFO_MEMORY_TYPE   ("auto"),
    .CDC_SYNC_STAGES    (2),
    .FULL_RESET_VALUE   (0),
    .USE_ADV_FEATURES   ("0000"),
    .RELATED_CLOCKS     (0),
    .SIM_ASSERT_CHK     (0),
    .WAKEUP_TIME        (0),
    .WRITE_DATA_WIDTH   (24),
    .READ_DATA_WIDTH    (24),
    .WR_DATA_COUNT_WIDTH(11),
    .RD_DATA_COUNT_WIDTH(11)
) u_tx_cdc (
    .wr_clk     (fclk),
    .wr_en      (tx_wr_en),
    .din        (tx_fifo_din),
    .rd_clk     (ad_clk),
    .rd_en      (ad_tx_read & ~tx_fifo_empty),
    .dout       (tx_fifo_dout),
    .empty      (tx_fifo_empty),
    .full       (tx_fifo_full),
    .rst        (~rst_n),
    .overflow   (),
    .underflow  (),
    .wr_rst_busy(),
    .rd_rst_busy(),
    .almost_empty(),
    .almost_full(),
    .wr_data_count(),
    .rd_data_count(),
    .sleep      (1'b0),
    .injectdbiterr(1'b0),
    .injectsbiterr(1'b0),
    .dbiterr    (),
    .sbiterr    ()
);

// TX FIFO → ad9363_cmos_if (scale 12-bit from OFDM TX, in ad_clk domain)
assign ad_tx_i = tx_fifo_empty ? 12'h000 : tx_fifo_dout[23:12];
assign ad_tx_q = tx_fifo_empty ? 12'h000 : tx_fifo_dout[11:0];

// ── OFDM+LDPC datapath (fclk domain) ─────────────────────────────────────
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

// Startup pulse (fclk domain)
wire tx_start;
startup_gen #(.DELAY(1000)) u_gen (
    .clk      (fclk),
    .rst_n    (rst_n),
    .pulse_out(tx_start)
);

// OFDM+LDPC TX/RX
wire [15:0] tx_iq_i, tx_iq_q;
wire        tx_valid_out;
wire [511:0] rx_decoded;
wire         rx_valid_out;
wire         rx_frame_start;

// RX frame synchronisation state machine (fclk domain)
// ─────────────────────────────────────────────────────
// States:
//   IDLE    : wait for tx_valid_out rise
//   DELAY   : count N_SYNC_DELAY RX samples (compensate TX→RX pipeline delay)
//   SYNC    : pulse rx_frame_start for one cycle
//   RUN     : feed RX samples to ofdm_ldpc_top
localparam ST_IDLE  = 2'd0,
           ST_DELAY = 2'd1,
           ST_SYNC  = 2'd2,
           ST_RUN   = 2'd3;

reg [1:0]  sync_state;
reg [$clog2(N_SYNC_DELAY+1)-1:0] sync_cnt;
reg        tx_valid_d1;
reg        frame_start_r;
reg        rx_in_valid;

always @(posedge fclk or negedge rst_n) begin
    if (!rst_n) begin
        sync_state   <= ST_IDLE;
        sync_cnt     <= 0;
        tx_valid_d1  <= 1'b0;
        frame_start_r<= 1'b0;
        rx_in_valid  <= 1'b0;
    end else begin
        tx_valid_d1   <= tx_valid_out;
        frame_start_r <= 1'b0;
        rx_in_valid   <= 1'b0;

        case (sync_state)
            ST_IDLE: begin
                // Wait for TX to start sending
                if (tx_valid_out & ~tx_valid_d1) begin
                    sync_state <= ST_DELAY;
                    sync_cnt   <= 0;
                end
            end
            ST_DELAY: begin
                // Count N_SYNC_DELAY RX FIFO outputs
                if (!rx_fifo_empty) begin
                    if (sync_cnt == N_SYNC_DELAY - 1)
                        sync_state <= ST_SYNC;
                    else
                        sync_cnt <= sync_cnt + 1;
                end
            end
            ST_SYNC: begin
                frame_start_r <= 1'b1;  // One-cycle pulse
                sync_state    <= ST_RUN;
            end
            ST_RUN: begin
                // Continuously drain RX FIFO into ofdm_ldpc_top
                if (!rx_fifo_empty)
                    rx_in_valid <= 1'b1;
            end
        endcase
    end
end

assign rx_frame_start = frame_start_r;
// Read RX FIFO whenever in RUN state and FIFO has data
assign rx_rd_en = (sync_state == ST_RUN || sync_state == ST_DELAY)
                    && !rx_fifo_empty;

// Scale AD9363 12-bit → 16-bit (sign extend × 16 = shift left 4)
wire [11:0] rx_i_12 = rx_fifo_dout[23:12];
wire [11:0] rx_q_12 = rx_fifo_dout[11:0];
wire [15:0] rx_i_16 = {{4{rx_i_12[11]}}, rx_i_12};
wire [15:0] rx_q_16 = {{4{rx_q_12[11]}}, rx_q_12};

// Scale OFDM TX 16-bit → 12-bit for AD9363 (top 12 bits)
wire [11:0] tx_i_12 = tx_iq_i[15:4];
wire [11:0] tx_q_12 = tx_iq_q[15:4];
assign tx_wr_en   = tx_valid_out & ~tx_fifo_full;
assign tx_fifo_din = {tx_i_12, tx_q_12};

// Instantiate OFDM+LDPC core
(* KEEP_HIERARCHY = "TRUE" *)
ofdm_ldpc_top u_ofdm (
    .clk            (fclk),
    .rst_n          (rst_n),
    .tx_info_bits   (TEST_BITS),
    .tx_valid_in    (tx_start),
    .tx_iq_i        (tx_iq_i),
    .tx_iq_q        (tx_iq_q),
    .tx_valid_out   (tx_valid_out),
    .rx_iq_i        (rx_i_16),
    .rx_iq_q        (rx_q_16),
    .rx_valid_in    (rx_in_valid),
    .rx_frame_start (rx_frame_start),
    .rx_decoded     (rx_decoded),
    .rx_valid_out   (rx_valid_out)
);

// ── Pass/fail latch → EMIO GPIO ──────────────────────────────────────────
reg pass_flag_r, rx_done_r;
always @(posedge fclk or negedge rst_n) begin
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

endmodule
