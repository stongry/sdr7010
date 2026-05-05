// =============================================================================
// ad9363_cmos_if.v — AD9363 CMOS 1R1T 12-bit parallel interface
//
// AD9363 CMOS interface (PlutoSDR, 1R1T mode):
//   RX: rx_clk_in (~61.44 MHz), rx_frame_in (1=I, 0=Q), rx_data_in[11:0]
//   TX: tx_clk_out (echo of rx_clk), tx_frame_out, tx_data_out[11:0]
//
// RX output: one {i,q} pair every 2 rx_clk cycles → ~30.72 MHz complex rate
// TX input:  one {i,q} pair consumed every 2 rx_clk cycles
//
// All internal logic runs in rx_clk domain (buffered as data_clk).
// =============================================================================
`timescale 1ns/1ps

module ad9363_cmos_if (
    // ── AD9363 physical pins ─────────────────────────────────────────────
    input  wire        rx_clk_in,
    input  wire        rx_frame_in,
    input  wire [11:0] rx_data_in,
    output wire        tx_clk_out,
    output wire        tx_frame_out,
    output wire [11:0] tx_data_out,

    // ── Buffered data clock (rx_clk domain) for user logic ────────────────
    output wire        data_clk,

    // ── RX IQ output (data_clk domain, valid pulses every 2 cycles) ───────
    output reg  [11:0] rx_i,
    output reg  [11:0] rx_q,
    output reg         rx_valid,

    // ── TX IQ input (data_clk domain) ────────────────────────────────────
    // tx_i/tx_q sampled when tx_read pulses; user should keep them stable
    input  wire [11:0] tx_i,
    input  wire [11:0] tx_q,
    output reg         tx_read    // pulses when tx_i/tx_q are consumed (I cycle)
);

// ── Buffer rx_clk_in for internal use ─────────────────────────────────────
wire clk;
BUFG u_rxclk_buf (.I(rx_clk_in), .O(clk));
assign data_clk = clk;

// ── Echo TX clock back to AD9363 via ODDR ─────────────────────────────────
// SAME_EDGE: both D1,D2 presented on rising edge, Q on falling/rising edges
ODDR #(.DDR_CLK_EDGE("SAME_EDGE"), .INIT(1'b0), .SRTYPE("ASYNC"))
u_txclk_oddr (
    .Q (tx_clk_out),
    .C (clk),
    .CE(1'b1),
    .D1(1'b0),
    .D2(1'b1),
    .R (1'b0),
    .S (1'b0)
);

// ── Capture RX data & frame (register to meet setup/hold) ─────────────────
reg [11:0] rx_data_r;
reg        rx_frame_r, rx_frame_d;

always @(posedge clk) begin
    rx_data_r  <= rx_data_in;
    rx_frame_r <= rx_frame_in;
    rx_frame_d <= rx_frame_r;
end

// ── Separate I and Q from interleaved stream ───────────────────────────────
reg [11:0] i_hold;

always @(posedge clk) begin
    rx_valid <= 1'b0;
    if (rx_frame_r) begin
        // HIGH frame → this cycle is I data
        i_hold <= rx_data_r;
    end else if (!rx_frame_r && rx_frame_d) begin
        // Falling edge of frame → Q data now valid, output pair
        rx_i    <= i_hold;
        rx_q    <= rx_data_r;
        rx_valid <= 1'b1;
    end
end

// ── TX: generate tx_frame and tx_data synchronous to data_clk ─────────────
// We mirror the RX frame timing: when frame=1 output I, when frame=0 output Q
reg [11:0] tx_data_r;
reg        tx_frame_r;
reg [11:0] tx_i_hold;

always @(posedge clk) begin
    tx_read   <= 1'b0;
    tx_frame_r <= rx_frame_r;   // Lock TX frame to RX frame phase
    if (rx_frame_r) begin
        // I cycle: latch tx_i, drive I data
        tx_i_hold  <= tx_i;
        tx_data_r  <= tx_i;
        tx_read    <= 1'b1;     // Consume one IQ pair
    end else begin
        // Q cycle: drive Q data
        tx_data_r  <= tx_q;
    end
end

assign tx_frame_out = tx_frame_r;
assign tx_data_out  = tx_data_r;

endmodule
