module cp_remove #(
    parameter N_FFT = 64,
    parameter N_CP  = 16
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        frame_start,    // Sync pulse: aligns to symbol boundary

    // Input AXI-Stream (from ADC / RF front-end)
    input  wire [31:0] s_axis_tdata,   // {Q[15:0], I[15:0]}
    input  wire        s_axis_tvalid,

    // Output AXI-Stream (to FFT)
    output reg  [31:0] m_axis_tdata,
    output reg         m_axis_tvalid,
    output reg         m_axis_tlast    // High on last sample of each 64-sample window
);

localparam N_SYM = N_FFT + N_CP;  // 80 samples per OFDM symbol

// ---------------------------------------------------------------------------
// Sample counter within one OFDM symbol (0 .. N_SYM-1)
// ---------------------------------------------------------------------------
reg [6:0]  sample_cnt;   // 0..79
reg        synced;        // 1 after first frame_start received

// BUGFIX: frame_start fires on the SAME cycle as the first valid sample
// (bin48/CP[0] of symbol 0). Previously the if/else-if structure consumed
// the frame_start branch and skipped processing that sample, causing every
// downstream symbol to be off by one bin (demap thinks bin_cnt=N but the
// stream is at bin (N+1) mod 64 — pilot/null bins get treated as data,
// LDPC decoder gets garbage LLRs and pass_flag never fires).
// Fix: derive an effective count where frame_start forces 0, otherwise the
// stored counter; process the sample using that effective count.
wire [6:0] cnt_curr = frame_start ? 7'd0 : sample_cnt;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        sample_cnt    <= 7'd0;
        synced        <= 1'b0;
        m_axis_tdata  <= 32'd0;
        m_axis_tvalid <= 1'b0;
        m_axis_tlast  <= 1'b0;
    end else begin
        m_axis_tvalid <= 1'b0;
        m_axis_tlast  <= 1'b0;

        if (frame_start) synced <= 1'b1;

        if ((frame_start || synced) && s_axis_tvalid) begin
            // Advance counter (wrap at N_SYM)
            if (cnt_curr == N_SYM - 1)
                sample_cnt <= 7'd0;
            else
                sample_cnt <= cnt_curr + 1'b1;

            // Pass through only the data portion (after CP)
            if (cnt_curr >= N_CP) begin
                m_axis_tdata  <= s_axis_tdata;
                m_axis_tvalid <= 1'b1;
                m_axis_tlast  <= (cnt_curr == N_SYM - 1) ? 1'b1 : 1'b0;
            end
        end
    end
end

endmodule
