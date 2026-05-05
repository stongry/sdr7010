// =============================================================================
// zynq_top.v — Zynq-7010 top-level wrapper for OFDM+LDPC PL demo
// Device: xc7z010clg225-1 (ADALM-PLUTO / PlutoSDR)
//
// Physical ports: ONLY the PS7-mandatory DDR + FIXED_IO pins.
// All ofdm_ldpc_top wide buses (tx_info_bits[511:0], rx_decoded[511:0], etc.)
// are INTERNAL — eliminating the 1081-port IO overutilization error.
//
// Test flow (self-contained loopback):
//   1. PS7 provides FCLK_CLK0 (100 MHz) + FCLK_RESET0_N to PL.
//   2. startup_gen fires tx_valid_in 1000 cycles after reset de-asserts.
//   3. ofdm_ldpc_top encodes TEST_BITS → OFDM-modulates → outputs tx_iq.
//   4. tx_iq is looped back directly to rx_iq (ideal channel, no noise).
//   5. rx_frame_start = rising edge of tx_valid_out (first CP sample).
//   6. Decoder output rx_decoded is compared with TEST_BITS.
//   7. pass_flag / rx_done are observable via JTAG ILA or PS EMIO GPIO.
//
// Board deployment:
//   scp ofdm_ldpc_top.bin root@192.168.2.1:/tmp/
//   echo 0 > /sys/class/fpga_manager/fpga0/flags
//   cp /tmp/ofdm_ldpc_top.bin /lib/firmware/
//   echo "ofdm_ldpc_top.bin" > /sys/class/fpga_manager/fpga0/firmware
// =============================================================================

`timescale 1ns/1ps

module zynq_top (
    // ── PS7 mandatory physical ports ────────────────────────────────────────
    // DDR3 memory interface (actual package pins; constrained by PS7 silicon)
    inout  wire [14:0] DDR_addr,
    inout  wire [2:0]  DDR_ba,
    inout  wire        DDR_cas_n,
    inout  wire        DDR_ck_n,
    inout  wire        DDR_ck_p,
    inout  wire        DDR_cke,
    inout  wire        DDR_cs_n,
    inout  wire [3:0]  DDR_dm,
    inout  wire [31:0] DDR_dq,
    inout  wire [3:0]  DDR_dqs_n,
    inout  wire [3:0]  DDR_dqs_p,
    inout  wire        DDR_odt,
    inout  wire        DDR_ras_n,
    inout  wire        DDR_reset_n,
    inout  wire        DDR_we_n,
    // PS fixed IO
    inout  wire        FIXED_IO_ddr_vrn,
    inout  wire        FIXED_IO_ddr_vrp,
    inout  wire [53:0] FIXED_IO_mio,
    inout  wire        FIXED_IO_ps_clk,
    inout  wire        FIXED_IO_ps_porb,
    inout  wire        FIXED_IO_ps_srstb
);

// ── PL clock + reset from PS7 ─────────────────────────────────────────────
wire [3:0] fclk_clk;
wire [3:0] fclk_rst_n;

// FCLK_CLK0 (100 MHz) through BUFG → global clock routing
wire clk;
BUFG u_clk_buf (.I(fclk_clk[0]), .O(clk));

// FCLK_RESET0_N: active-low, synchronised to FCLK_CLK0
wire rst_n = fclk_rst_n[0];

// ── Zynq PS7 primitive ────────────────────────────────────────────────────
// Only the ports required for our minimal PL demo are connected.
// Vivado synthesis binds unlisted PS7 input ports to 0 by default.
PS7 u_ps7 (
    // DDR
    .DDRA      (DDR_addr),
    .DDRBA     (DDR_ba),
    .DDRCASB   (DDR_cas_n),
    .DDRCKN    (DDR_ck_n),
    .DDRCKP    (DDR_ck_p),
    .DDRCKE    (DDR_cke),
    .DDRCSB    (DDR_cs_n),
    .DDRDM     (DDR_dm),
    .DDRDQ     (DDR_dq),
    .DDRDQSN   (DDR_dqs_n),
    .DDRDQSP   (DDR_dqs_p),
    .DDRDRSTB  (DDR_reset_n),
    .DDRODT    (DDR_odt),
    .DDRRASB   (DDR_ras_n),
    .DDRWEB    (DDR_we_n),
    .DDRVRN    (FIXED_IO_ddr_vrn),
    .DDRVRP    (FIXED_IO_ddr_vrp),
    // MIO / PS config
    .MIO       (FIXED_IO_mio),
    .PSCLK     (FIXED_IO_ps_clk),
    .PSPORB    (FIXED_IO_ps_porb),
    .PSSRSTB   (FIXED_IO_ps_srstb),
    // PL fabric clock/reset outputs
    .FCLKCLK       (fclk_clk),
    .FCLKRESETN    (fclk_rst_n),
    .FCLKCLKTRIGENB(4'hF)       // 1 = disable clock gating → clocks run freely
);

// ── Fixed test pattern: 512 info bits ────────────────────────────────────
// Non-trivial pattern to exercise encoder/decoder properly.
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

// ── Internal wires ────────────────────────────────────────────────────────
wire        tx_start;
wire [15:0] tx_iq_i, tx_iq_q;
wire        tx_valid_out;
wire [511:0] rx_decoded;
wire        rx_valid_out;

// ── Auto-start: one-shot pulse 1000 cycles after reset ───────────────────
startup_gen #(.DELAY(1000)) u_gen (
    .clk      (clk),
    .rst_n    (rst_n),
    .pulse_out(tx_start)
);

// ── RX frame sync: rising edge of tx_valid_out ───────────────────────────
// cp_remove needs frame_start to align to the first CP sample.
// In loopback mode, tx_valid_out rising edge = first CP sample arriving at RX.
reg tx_valid_d1;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) tx_valid_d1 <= 1'b0;
    else        tx_valid_d1 <= tx_valid_out;
end
wire rx_frame_start = tx_valid_out & ~tx_valid_d1;

// ── OFDM+LDPC datapath (TX→RX loopback) ──────────────────────────────────
(* KEEP_HIERARCHY = "TRUE" *)
ofdm_ldpc_top u_top (
    .clk            (clk),
    .rst_n          (rst_n),
    // TX
    .tx_info_bits   (TEST_BITS),
    .tx_valid_in    (tx_start),
    .tx_iq_i        (tx_iq_i),
    .tx_iq_q        (tx_iq_q),
    .tx_valid_out   (tx_valid_out),
    // RX — direct loopback from TX outputs
    .rx_iq_i        (tx_iq_i),
    .rx_iq_q        (tx_iq_q),
    .rx_valid_in    (tx_valid_out),
    .rx_frame_start (rx_frame_start),
    .rx_decoded     (rx_decoded),
    .rx_valid_out   (rx_valid_out)
);

// ── Pass/fail check ───────────────────────────────────────────────────────
// Latched results observable via JTAG ILA or PS EMIO GPIO.
// (* DONT_TOUCH = "TRUE" *) prevents the optimizer from sweeping these.
(* DONT_TOUCH = "TRUE" *) reg pass_flag;
(* DONT_TOUCH = "TRUE" *) reg rx_done;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        pass_flag <= 1'b0;
        rx_done   <= 1'b0;
    end else if (rx_valid_out && !rx_done) begin
        pass_flag <= (rx_decoded == TEST_BITS);
        rx_done   <= 1'b1;
    end
end

endmodule
