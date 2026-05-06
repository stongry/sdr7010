`timescale 1ns/1ps
module ofdm_ldpc_top (
    input  wire         clk,
    input  wire         rst_n,

    // TX interface
    input  wire [511:0] tx_info_bits,   // 512 information bits per LDPC block
    input  wire         tx_valid_in,    // Pulse to start TX encoding
    output wire [15:0]  tx_iq_i,        // TX I output stream (to DAC)
    output wire [15:0]  tx_iq_q,        // TX Q output stream (to DAC)
    output wire         tx_valid_out,   // One cycle per valid TX sample

    // RX interface
    input  wire [15:0]  rx_iq_i,        // RX I input stream (from ADC)
    input  wire [15:0]  rx_iq_q,        // RX Q input stream (from ADC)
    input  wire         rx_valid_in,    // One cycle per valid RX sample
    input  wire         rx_frame_start, // Frame sync pulse for CP removal
    output wire [511:0] rx_decoded,     // Decoded information bits
    output wire         rx_valid_out,   // Pulse when decoded bits ready

    // DEBUG outputs (latched in ofdm_ldpc_pl) for EMIO bring-up
    output wire         dbg_enc_valid,  // ldpc_encoder produced enc_valid_out
    output wire         dbg_ifft_valid, // tx_subcarrier_map produced ifft_tvalid
    output wire         dbg_cp_rem_valid, // cp_remove produced cp_rem_tvalid
    output wire         dbg_fft_m_valid,  // FFT produced fft_m_tvalid
    output wire         dbg_eq_valid,     // channel_est/eq produced eq_valid_out
    output wire         dbg_demod_valid,  // qpsk_demod produced demod_valid_out
    output wire         dbg_llr_done,     // llr_buffer assembled valid_out
    output wire [511:0] dbg_chllr_decoded // raw hard-decision of K LLRs (no BP)
);

// ---------------------------------------------------------------------------
// Parameters
// ---------------------------------------------------------------------------
localparam N_FFT   = 64;
localparam N_CP    = 16;
localparam N_DATA  = 48;    // Data subcarriers per symbol
localparam N_PIL   = 4;     // Pilot subcarriers per symbol
localparam N_SYM   = 12;    // OFDM symbols per LDPC block (was 11; +1 margin so demod_cnt comfortably > 512 LLR threshold)
localparam N_CW    = 1024;  // LDPC codeword length
localparam K       = 512;   // LDPC info bits
localparam PILOT_A = 16'sd5793;  // Pilot amplitude

// ---------------------------------------------------------------------------
// Internal wires
// ---------------------------------------------------------------------------

// LDPC encoder output
wire [N_CW-1:0]  enc_codeword;
wire             enc_valid_out;

// QPSK modulator
wire [15:0]      qpsk_i_out;
wire [15:0]      qpsk_q_out;
wire             qpsk_valid_out;

// Subcarrier mapper → IFFT
wire [31:0]      ifft_s_tdata;
wire             ifft_s_tvalid;
wire             ifft_s_tready;

// IFFT → CP insert (AXI-S)
wire [31:0]      ifft_m_tdata;
wire             ifft_m_tvalid;
wire             ifft_m_tready;

// CP insert → TX output
wire [31:0]      cp_ins_tdata;
wire             cp_ins_tvalid;

// CP remove → FFT
wire [31:0]      cp_rem_tdata;
wire             cp_rem_tvalid;
wire             cp_rem_tlast;

// FFT → channel estimator
wire [31:0]      fft_m_tdata;
wire             fft_m_tvalid;

// Channel estimator outputs
wire [15:0]      eq_i_out;
wire [15:0]      eq_q_out;
wire             eq_valid_out;

// RX subcarrier demap → QPSK demod
wire [15:0]      demap_i_out;
wire [15:0]      demap_q_out;
wire             demap_valid_out;

// QPSK demodulator
wire [7:0]       llr0_out;
wire [7:0]       llr1_out;
wire             demod_valid_out;

// llr_buffer → LDPC decoder (serial read-port interface, no wide bus)
wire [9:0]        llr_rd_addr;
wire [7:0]        llr_rd_data;
wire              llr_assemble_done;

// ---------------------------------------------------------------------------
// TX PATH
// ---------------------------------------------------------------------------

// 1. LDPC Encoder
ldpc_encoder #(
    .N(N_CW), .K(K), .Z(64), .MB(8), .NB(16)
) u_ldpc_enc (
    .clk       (clk),
    .rst_n     (rst_n),
    .k_bits    (tx_info_bits),
    .valid_in  (tx_valid_in),
    .codeword  (enc_codeword),
    .valid_out (enc_valid_out)
);

// 2. TX Subcarrier mapper + QPSK modulator
//    Streams 2 bits at a time from codeword into QPSK modulator,
//    then builds IFFT input frames with pilot insertion.
tx_subcarrier_map #(
    .N_FFT(N_FFT), .N_DATA(N_DATA), .N_SYM(N_SYM), .N_CW(N_CW),
    .PILOT_A(PILOT_A)
) u_tx_map (
    .clk          (clk),
    .rst_n        (rst_n),
    .codeword     (enc_codeword),
    .codeword_vld (enc_valid_out),
    .ifft_tdata   (ifft_s_tdata),
    .ifft_tvalid  (ifft_s_tvalid),
    .ifft_tready  (ifft_s_tready)
);

// 3. IFFT (Vivado IP xifft_0 — to be instantiated via TCL)
//    Interface: AXI4-Stream, 32-bit {Q[15:0], I[15:0]}
//    Stub instantiation — replace with actual IP in project:
xfft_stub u_ifft (
    .aclk                (clk),
    .aresetn             (rst_n),
    // Config: set to IFFT
    .s_axis_config_tdata (8'b0000_0001),  // bit0=1 → IFFT
    .s_axis_config_tvalid(1'b1),
    .s_axis_config_tready(/* open */),
    .s_axis_data_tdata   (ifft_s_tdata),
    .s_axis_data_tvalid  (ifft_s_tvalid),
    .s_axis_data_tready  (ifft_s_tready),
    .s_axis_data_tlast   (1'b0),          // driven by mapper
    .m_axis_data_tdata   (ifft_m_tdata),
    .m_axis_data_tvalid  (ifft_m_tvalid),
    .m_axis_data_tready  (ifft_m_tready),
    .m_axis_data_tlast   (/* open */)
);

// 4. Cyclic Prefix Insertion
cp_insert #(
    .N_FFT(N_FFT), .N_CP(N_CP)
) u_cp_ins (
    .clk           (clk),
    .rst_n         (rst_n),
    .s_axis_tdata  (ifft_m_tdata),
    .s_axis_tvalid (ifft_m_tvalid),
    .s_axis_tready (ifft_m_tready),
    .m_axis_tdata  (cp_ins_tdata),
    .m_axis_tvalid (cp_ins_tvalid),
    .m_axis_tready (1'b1)   // TX back-to-back, always ready
);

assign tx_iq_i     = cp_ins_tdata[15:0];
assign tx_iq_q     = cp_ins_tdata[31:16];
assign tx_valid_out = cp_ins_tvalid;

// Debug taps - TX
assign dbg_enc_valid  = enc_valid_out;
assign dbg_ifft_valid = ifft_s_tvalid;
// Debug taps - RX
assign dbg_cp_rem_valid = cp_rem_tvalid;
assign dbg_fft_m_valid  = fft_m_tvalid;
assign dbg_eq_valid     = eq_valid_out;
assign dbg_demod_valid  = demod_valid_out;
assign dbg_llr_done     = llr_assemble_done;

// ---------------------------------------------------------------------------
// RX PATH
// ---------------------------------------------------------------------------

// 5. Cyclic Prefix Removal
cp_remove #(
    .N_FFT(N_FFT), .N_CP(N_CP)
) u_cp_rem (
    .clk           (clk),
    .rst_n         (rst_n),
    .frame_start   (rx_frame_start),
    .s_axis_tdata  ({rx_iq_q, rx_iq_i}),
    .s_axis_tvalid (rx_valid_in),
    .m_axis_tdata  (cp_rem_tdata),
    .m_axis_tvalid (cp_rem_tvalid),
    .m_axis_tlast  (cp_rem_tlast)
);

// 6. FFT (Vivado IP xfft_0 — forward FFT)
xfft_stub u_fft (
    .aclk                (clk),
    .aresetn             (rst_n),
    .s_axis_config_tdata (8'b0000_0000),  // bit0=0 → FFT
    .s_axis_config_tvalid(1'b1),
    .s_axis_config_tready(/* open */),
    .s_axis_data_tdata   (cp_rem_tdata),
    .s_axis_data_tvalid  (cp_rem_tvalid),
    .s_axis_data_tready  (/* open */),
    .s_axis_data_tlast   (cp_rem_tlast),
    .m_axis_data_tdata   (fft_m_tdata),
    .m_axis_data_tvalid  (fft_m_tvalid),
    .m_axis_data_tready  (1'b1),
    .m_axis_data_tlast   (/* open */)
);

// 7. Channel Estimator + Equalizer
channel_est #(
    .N_FFT(N_FFT), .A_PIL(PILOT_A)
) u_ch_est (
    .clk          (clk),
    .rst_n        (rst_n),
    .frame_start  (rx_frame_start),
    .fft_in_i     (fft_m_tdata[15:0]),
    .fft_in_q     (fft_m_tdata[31:16]),
    .fft_in_valid (fft_m_tvalid),
    .eq_out_i     (eq_i_out),
    .eq_out_q     (eq_q_out),
    .eq_out_valid (eq_valid_out),
    .H_est_i_flat (/* open */),
    .H_est_q_flat (/* open */)
);

// 8. RX Subcarrier demapper: select data subcarriers, skip pilots
//    Feeds equalized bins to QPSK demodulator
rx_subcarrier_demap #(
    .N_FFT(N_FFT), .N_DATA(N_DATA), .N_SYM(N_SYM)
) u_rx_demap (
    .clk          (clk),
    .rst_n        (rst_n),
    .eq_i         (eq_i_out),
    .eq_q         (eq_q_out),
    .eq_valid     (eq_valid_out),
    .demod_i      (demap_i_out),
    .demod_q      (demap_q_out),
    .demod_valid  (demap_valid_out)
);

// 9. QPSK Demodulator
qpsk_demod #(
    .SCALE(7)
) u_qpsk_demod (
    .clk       (clk),
    .rst_n     (rst_n),
    .I_in      (demap_i_out),
    .Q_in      (demap_q_out),
    .valid_in  (demap_valid_out),
    .llr0      (llr0_out),
    .llr1      (llr1_out),
    .valid_out (demod_valid_out)
);

// 10. LLR Buffer: collect N_CW=1024 LLRs into dual LUTRAM (no wide register)
llr_buffer #(
    .N_CW(N_CW)
) u_llr_buf (
    .clk        (clk),
    .rst_n      (rst_n),
    .llr0       (llr0_out),
    .llr1       (llr1_out),
    .valid_in   (demod_valid_out),
    .valid_out  (llr_assemble_done),
    .rd_addr    (llr_rd_addr),
    .rd_data    (llr_rd_data)
);

// 11. LDPC Decoder
ldpc_decoder #(
    .N(N_CW), .K(K), .Z(64), .MB(8), .NB(16), .MAX_ITER(10), .Q(8)
) u_ldpc_dec (
    .clk         (clk),
    .rst_n       (rst_n),
    .llr_rd_addr (llr_rd_addr),
    .llr_rd_data (llr_rd_data),
    .valid_in    (llr_assemble_done),
    .decoded           (rx_decoded),
    .valid_out         (rx_valid_out),
    .iter_count        (/* open */),
    .dbg_chllr_decoded (dbg_chllr_decoded)
);

endmodule
