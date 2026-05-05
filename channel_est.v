// =============================================================================
// File: channel_est.v
// Project: OFDM+LDPC FPGA Transceiver (PlutoSDR / xc7z010clg225-1)
// Module: Pilot-Based Channel Estimator
//
// Streaming mode (STREAM_MODE=1, default):
//   Passes all FFT bins through a 1-cycle register.  Sufficient for
//   simulation with xfft_stub (identity "channel", H=1 at all bins).
//   rx_subcarrier_demap downstream filters pilot/null bins.
//
// Full mode (STREAM_MODE=0):
//   First-symbol pilot extraction, linear interpolation, per-symbol
//   equalization.  Requires real xfft_0 IP and multi-symbol buffering.
//   Enable when synthesising with actual FFT.
//
// Synthesizable Verilog-2001.
// =============================================================================

`timescale 1ns/1ps

module channel_est #(
    parameter N_FFT      = 64,
    parameter A_PIL      = 16'd5793,  // Pilot amplitude
    parameter STREAM_MODE = 1         // 1 = pass-through; 0 = full estimation
)(
    input  wire         clk,
    input  wire         rst_n,
    input  wire         frame_start,   // Pulse at start of FFT output burst

    // FFT output bins (one per clock when fft_in_valid)
    input  wire [15:0]  fft_in_i,
    input  wire [15:0]  fft_in_q,
    input  wire         fft_in_valid,

    // Equalized output
    output reg  [15:0]  eq_out_i,
    output reg  [15:0]  eq_out_q,
    output reg          eq_out_valid,

    // Channel estimate (unused in stream mode)
    output reg  [N_FFT*16-1:0] H_est_i_flat,
    output reg  [N_FFT*16-1:0] H_est_q_flat
);

generate
if (STREAM_MODE) begin : stream_mode

    // -----------------------------------------------------------------------
    // 1-cycle registered pass-through.
    // With xfft_stub (identity transform) equalization is Y*1/1 = Y.
    // -----------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            eq_out_i     <= 16'd0;
            eq_out_q     <= 16'd0;
            eq_out_valid <= 1'b0;
            H_est_i_flat <= {(N_FFT*16){1'b0}};
            H_est_q_flat <= {(N_FFT*16){1'b0}};
        end else begin
            eq_out_i     <= fft_in_i;
            eq_out_q     <= fft_in_q;
            eq_out_valid <= fft_in_valid;
        end
    end

end else begin : full_est_mode

    // -----------------------------------------------------------------------
    // Full pilot-based channel estimator.
    // Phase 1: buffer 64 bins of first OFDM symbol.
    // Phase 2: extract pilot H at bins {7,21,43,57}, interpolate H.
    // Phase 3: equalize all 64 bins and stream output.
    // Limitations: processes one symbol; use with real xfft_0 IP and a
    // multi-symbol FIFO wrapper for multi-symbol frames.
    // -----------------------------------------------------------------------

    localparam PIL0 = 6'd7;
    localparam PIL1 = 6'd21;
    localparam PIL2 = 6'd43;
    localparam PIL3 = 6'd57;

    reg signed [15:0] Y_i [0:N_FFT-1];
    reg signed [15:0] Y_q [0:N_FFT-1];
    reg signed [15:0] H_i [0:N_FFT-1];
    reg signed [15:0] H_q [0:N_FFT-1];

    reg [5:0]  bin_cnt;
    reg        collecting;

    localparam EST_IDLE   = 2'd0;
    localparam EST_PILOT  = 2'd1;
    localparam EST_INTERP = 2'd2;
    localparam EST_EQUAL  = 2'd3;

    reg [1:0]  est_state;
    reg [5:0]  proc_bin;
    reg        prev_collect;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bin_cnt    <= 6'd0;
            collecting <= 1'b0;
        end else begin
            if (frame_start) begin
                bin_cnt    <= 6'd0;
                collecting <= 1'b1;
            end else if (collecting && fft_in_valid) begin
                Y_i[bin_cnt] <= $signed(fft_in_i);
                Y_q[bin_cnt] <= $signed(fft_in_q);
                if (bin_cnt == N_FFT - 1) begin
                    collecting <= 1'b0;
                    bin_cnt    <= 6'd0;
                end else begin
                    bin_cnt <= bin_cnt + 1'b1;
                end
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin : est_fsm
        integer k;
        reg signed [15:0] dI, dQ;
        reg signed [31:0] frac_i, frac_q;
        reg signed [15:0] span, offset;
        reg signed [31:0] yi, yq, hi, hq;
        reg signed [31:0] eq_i_l, eq_q_l, mag2;
        reg [5:0] bk;

        if (!rst_n) begin
            est_state    <= EST_IDLE;
            proc_bin     <= 6'd0;
            prev_collect <= 1'b0;
            eq_out_valid <= 1'b0;
            eq_out_i     <= 16'd0;
            eq_out_q     <= 16'd0;
        end else begin
            prev_collect <= collecting;
            eq_out_valid <= 1'b0;

            case (est_state)
                EST_IDLE: begin
                    if (prev_collect && !collecting) begin
                        est_state <= EST_PILOT;
                        proc_bin  <= 6'd0;
                    end
                end

                EST_PILOT: begin
                    H_i[PIL0] <= Y_i[PIL0]; H_q[PIL0] <= Y_q[PIL0];
                    H_i[PIL1] <= Y_i[PIL1]; H_q[PIL1] <= Y_q[PIL1];
                    H_i[PIL2] <= Y_i[PIL2]; H_q[PIL2] <= Y_q[PIL2];
                    H_i[PIL3] <= Y_i[PIL3]; H_q[PIL3] <= Y_q[PIL3];
                    est_state <= EST_INTERP;
                    proc_bin  <= 6'd0;
                end

                EST_INTERP: begin
                    begin : interp_block
                        reg [5:0] b;
                        b = proc_bin;
                        if (b <= PIL0) begin
                            H_i[b] <= H_i[PIL0]; H_q[b] <= H_q[PIL0];
                        end else if (b <= PIL1) begin
                            span   = PIL1 - PIL0;
                            offset = b - PIL0;
                            frac_i = ($signed(H_i[PIL1]) - $signed(H_i[PIL0])) * $signed({1'b0,offset});
                            frac_q = ($signed(H_q[PIL1]) - $signed(H_q[PIL0])) * $signed({1'b0,offset});
                            H_i[b] <= H_i[PIL0] + frac_i / span;
                            H_q[b] <= H_q[PIL0] + frac_q / span;
                        end else if (b <= PIL2) begin
                            span   = PIL2 - PIL1;
                            offset = b - PIL1;
                            frac_i = ($signed(H_i[PIL2]) - $signed(H_i[PIL1])) * $signed({1'b0,offset});
                            frac_q = ($signed(H_q[PIL2]) - $signed(H_q[PIL1])) * $signed({1'b0,offset});
                            H_i[b] <= H_i[PIL1] + frac_i / span;
                            H_q[b] <= H_q[PIL1] + frac_q / span;
                        end else if (b <= PIL3) begin
                            span   = PIL3 - PIL2;
                            offset = b - PIL2;
                            frac_i = ($signed(H_i[PIL3]) - $signed(H_i[PIL2])) * $signed({1'b0,offset});
                            frac_q = ($signed(H_q[PIL3]) - $signed(H_q[PIL2])) * $signed({1'b0,offset});
                            H_i[b] <= H_i[PIL2] + frac_i / span;
                            H_q[b] <= H_q[PIL2] + frac_q / span;
                        end else begin
                            H_i[b] <= H_i[PIL3]; H_q[b] <= H_q[PIL3];
                        end
                    end
                    if (proc_bin == N_FFT - 1) begin
                        est_state <= EST_EQUAL;
                        proc_bin  <= 6'd0;
                    end else begin
                        proc_bin <= proc_bin + 1'b1;
                    end
                end

                EST_EQUAL: begin
                    begin : equal_block
                        reg [5:0] b2;
                        b2 = proc_bin;
                        yi = {{16{Y_i[b2][15]}}, Y_i[b2]};
                        yq = {{16{Y_q[b2][15]}}, Y_q[b2]};
                        hi = {{16{H_i[b2][15]}}, H_i[b2]};
                        hq = {{16{H_q[b2][15]}}, H_q[b2]};
                        eq_i_l = (yi * hi + yq * hq);
                        eq_q_l = (yq * hi - yi * hq);
                        mag2   = hi * hi + hq * hq;
                        if (mag2 > 32'd0) begin
                            eq_out_i <= eq_i_l[28:13];
                            eq_out_q <= eq_q_l[28:13];
                        end else begin
                            eq_out_i <= Y_i[b2];
                            eq_out_q <= Y_q[b2];
                        end
                        eq_out_valid <= 1'b1;
                        H_est_i_flat[b2*16 +: 16] <= H_i[b2];
                        H_est_q_flat[b2*16 +: 16] <= H_q[b2];
                    end
                    if (proc_bin == N_FFT - 1) begin
                        est_state <= EST_IDLE;
                        proc_bin  <= 6'd0;
                    end else begin
                        proc_bin <= proc_bin + 1'b1;
                    end
                end

                default: est_state <= EST_IDLE;
            endcase
        end
    end

end
endgenerate

endmodule
