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

        // Synchronize on frame_start
        if (frame_start) begin
            sample_cnt <= 7'd0;
            synced     <= 1'b1;
        end else if (synced && s_axis_tvalid) begin
            // Advance counter; wrap at N_SYM
            if (sample_cnt == N_SYM - 1)
                sample_cnt <= 7'd0;
            else
                sample_cnt <= sample_cnt + 1'b1;

            // Pass through only the data portion (after CP)
            if (sample_cnt >= N_CP) begin
                m_axis_tdata  <= s_axis_tdata;
                m_axis_tvalid <= 1'b1;
                // tlast on the last data sample (sample_cnt == N_SYM-1)
                m_axis_tlast  <= (sample_cnt == N_SYM - 1) ? 1'b1 : 1'b0;
            end
        end
    end
end

endmodule
