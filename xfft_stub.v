`timescale 1ns/1ps
//-----------------------------------------------------------------------------
// xfft_stub.v — Behavioral 64-pt FFT/IFFT for xsim verification
//-----------------------------------------------------------------------------
// **SIMULATION-ONLY**: Computes the DFT directly (O(N²)) using `real`-typed
// arithmetic via the Verilog system tasks `$cos` / `$sin`. Functionally
// equivalent to numpy.fft.{fft,ifft} with Vivado xfft IP "unscaled" mode:
//
//   Forward FFT  (config bit0=0):  X[k] = sum_n x[n] * exp(-j 2π nk / N) / N
//   Inverse FFT  (config bit0=1):  x[n] = sum_k X[k] * exp(+j 2π nk / N)
//
// The forward direction divides by N to match Path X Python convention
// (`np.fft.fft(rx) / N_FFT`); the inverse direction does not divide, also
// matching Path X (`np.fft.ifft(freq) * N_FFT`).
//
// AXI-Stream double-buffer: while one 64-sample block is being output, the
// next block can be loaded in. This keeps RX-side throughput sustainable
// when cp_remove emits two consecutive 64-sample bursts only 16 cycles apart.
//
// For synthesis to FPGA, replace this module with a wrapper around
// Vivado's xfft_v9.1 IP (Stage 2 of the project).
//-----------------------------------------------------------------------------

module xfft_stub (
    input  wire        aclk,
    input  wire        aresetn,

    // Configuration: 8-bit AXI-S, bit[0] = 1 → IFFT, 0 → forward FFT
    input  wire [7:0]  s_axis_config_tdata,
    input  wire        s_axis_config_tvalid,
    output wire        s_axis_config_tready,

    // Data input (frequency-domain bins for IFFT, time samples for FFT)
    input  wire [31:0] s_axis_data_tdata,        // {Q[15:0], I[15:0]}
    input  wire        s_axis_data_tvalid,
    output wire        s_axis_data_tready,
    input  wire        s_axis_data_tlast,

    // Data output
    output reg  [31:0] m_axis_data_tdata,
    output reg         m_axis_data_tvalid,
    input  wire        m_axis_data_tready,
    output reg         m_axis_data_tlast
);

localparam integer N = 64;

// ---------------------------------------------------------------------------
// Config latching: capture the inverse flag
// ---------------------------------------------------------------------------
reg inverse_q;
assign s_axis_config_tready = 1'b1;
always @(posedge aclk or negedge aresetn) begin
    if (!aresetn)                        inverse_q <= 1'b0;
    else if (s_axis_config_tvalid)       inverse_q <= s_axis_config_tdata[0];
end

// ---------------------------------------------------------------------------
// Double-buffer ping-pong:
//   in_buf  — currently accepting samples
//   out_buf — currently streaming computed result (or idle)
// load_done flips when the input bank has 64 samples ready to compute.
// out_busy is high while output is streaming.
// ---------------------------------------------------------------------------
reg signed [15:0] in_buf_re  [0:N-1];
reg signed [15:0] in_buf_im  [0:N-1];
reg signed [15:0] out_buf_re [0:N-1];
reg signed [15:0] out_buf_im [0:N-1];

reg [6:0] in_cnt;
reg       load_done;     // input bank full, waiting to be processed
reg [6:0] out_cnt;
reg       out_busy;
reg       inv_pending;   // direction captured at load time

assign s_axis_data_tready = !load_done;   // hold off mapper while we wait

// ---------------------------------------------------------------------------
// LOAD path: drop incoming 32-bit samples into in_buf
// ---------------------------------------------------------------------------
always @(posedge aclk or negedge aresetn) begin
    if (!aresetn) begin
        in_cnt    <= 7'd0;
        load_done <= 1'b0;
    end else begin
        // Compute consumes the loaded buffer this cycle
        if (load_done && !out_busy) begin
            load_done <= 1'b0;
        end

        if (s_axis_data_tvalid && !load_done) begin
            in_buf_re[in_cnt] <= $signed(s_axis_data_tdata[15:0]);
            in_buf_im[in_cnt] <= $signed(s_axis_data_tdata[31:16]);
            if (in_cnt == N-1) begin
                in_cnt    <= 7'd0;
                load_done <= 1'b1;
            end else begin
                in_cnt    <= in_cnt + 1'b1;
            end
        end
    end
end

// ---------------------------------------------------------------------------
// COMPUTE + OUTPUT path
// When load_done is high and we are not currently streaming, pull the
// in_buf contents into out_buf via direct DFT, then drive 64 cycles of
// AXI-S output.
// ---------------------------------------------------------------------------
real        pi_const;
initial     pi_const = 3.141592653589793238;

task automatic do_dft;
    input               do_inverse;
    integer             k, n;
    real                ang, sre, sim_acc, ire, iim, scale, val;
    integer             ival;
begin
    // Symmetric 1/sqrt(N) scaling on BOTH directions so neither saturates
    // int16. PAPR-bounded |IFFT/sqrt(64)| <= 5793*sqrt(64)/8 ≈ 5793 for the
    // OFDM symbol pattern in tx_subcarrier_map. Cascade FFT(IFFT(X)) = X/N,
    // QPSK demod is sign-based so LDPC still recovers info bits.
    scale = 1.0 / 8.0;
    for (k = 0; k < N; k = k + 1) begin
        sre     = 0.0;
        sim_acc = 0.0;
        for (n = 0; n < N; n = n + 1) begin
            ang = (do_inverse ? 1.0 : -1.0) * 2.0 * pi_const
                  * k * n / 64.0;
            ire = $itor($signed(in_buf_re[n]));
            iim = $itor($signed(in_buf_im[n]));
            sre     = sre     + ire * $cos(ang) - iim * $sin(ang);
            sim_acc = sim_acc + ire * $sin(ang) + iim * $cos(ang);
        end
        sre     = sre     * scale;
        sim_acc = sim_acc * scale;
        // Saturate to int16
        val = sre;
        if (val >  32767.0) val =  32767.0;
        if (val < -32768.0) val = -32768.0;
        ival = val; out_buf_re[k] = ival[15:0];
        val = sim_acc;
        if (val >  32767.0) val =  32767.0;
        if (val < -32768.0) val = -32768.0;
        ival = val; out_buf_im[k] = ival[15:0];
    end
end
endtask

always @(posedge aclk or negedge aresetn) begin
    if (!aresetn) begin
        out_cnt           <= 7'd0;
        out_busy          <= 1'b0;
        m_axis_data_tdata <= 32'd0;
        m_axis_data_tvalid<= 1'b0;
        m_axis_data_tlast <= 1'b0;
        inv_pending       <= 1'b0;
    end else begin
        if (!out_busy) begin
            m_axis_data_tvalid <= 1'b0;
            m_axis_data_tlast  <= 1'b0;
            if (load_done) begin
                inv_pending = inverse_q;
                do_dft(inv_pending);
                out_busy <= 1'b1;
                out_cnt  <= 7'd0;
            end
        end else begin
            // Drive next sample whenever sink can accept (or we have nothing
            // valid yet)
            if (m_axis_data_tready || !m_axis_data_tvalid) begin
                m_axis_data_tdata  <= {out_buf_im[out_cnt], out_buf_re[out_cnt]};
                m_axis_data_tvalid <= 1'b1;
                m_axis_data_tlast  <= (out_cnt == N-1);
                if (out_cnt == N-1) begin
                    out_cnt  <= 7'd0;
                    out_busy <= 1'b0;
                end else begin
                    out_cnt  <= out_cnt + 1'b1;
                end
            end
        end
    end
end

endmodule
