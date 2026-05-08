`timescale 1ns/1ps
module cp_insert #(
    parameter N_FFT = 64,
    parameter N_CP  = 16
)(
    input  wire        clk,
    input  wire        rst_n,

    // Input AXI-Stream (from IFFT)
    input  wire [31:0] s_axis_tdata,    // {Q[15:0], I[15:0]}
    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,

    // Output AXI-Stream (to DAC / RF)
    output reg  [31:0] m_axis_tdata,    // {Q[15:0], I[15:0]}
    output reg         m_axis_tvalid,
    input  wire        m_axis_tready
);

localparam N_OUT = N_FFT + N_CP;  // 80

// ---------------------------------------------------------------------------
// Ping-pong buffer: 2 banks × N_FFT=64 entries × 32 bits
// ---------------------------------------------------------------------------
reg [31:0] buf_a [0:N_FFT-1];
reg [31:0] buf_b [0:N_FFT-1];

// Write side state
(* KEEP = "TRUE" *) reg wr_bank;       // 0=write to A, 1=write to B
(* KEEP = "TRUE" *) reg [6:0]  wr_ptr;        // 0..63
(* KEEP = "TRUE" *) reg wr_full;       // Write bank is full, block input

// Read side state
(* KEEP = "TRUE" *) reg rd_bank;       // 0=read from A, 1=read from B
(* KEEP = "TRUE" *) reg [6:0]  rd_ptr;        // 0..79 (0..15=CP, 16..79=data)
(* KEEP = "TRUE" *) reg rd_active;     // Read bank has data to send
reg        rd_bank_valid; // A ready-to-read bank is waiting

// ---------------------------------------------------------------------------
// Input side: accept samples into write bank
// ---------------------------------------------------------------------------
assign s_axis_tready = !wr_full;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        wr_bank  <= 1'b0;
        wr_ptr   <= 7'd0;
        wr_full  <= 1'b0;
    end else begin
        // Release full flag when reader switches to this bank
        if (wr_full && (rd_bank == wr_bank) && rd_active) begin
            // Reader has taken the bank; swap writer to other bank
            wr_bank  <= ~wr_bank;
            wr_ptr   <= 7'd0;
            wr_full  <= 1'b0;
        end

        if (s_axis_tvalid && !wr_full) begin
            if (wr_bank == 1'b0)
                buf_a[wr_ptr] <= s_axis_tdata;
            else
                buf_b[wr_ptr] <= s_axis_tdata;

            if (wr_ptr == N_FFT - 1) begin
                wr_ptr  <= 7'd0;
                wr_full <= 1'b1;  // Bank is full, signal reader
            end else begin
                wr_ptr <= wr_ptr + 1'b1;
            end
        end
    end
end

// ---------------------------------------------------------------------------
// Output side: read CP then data from read bank
// ---------------------------------------------------------------------------
// CP = last N_CP samples of the buffer = indices [N_FFT-N_CP .. N_FFT-1]
// Output order: rd_ptr 0..15 → buf[N_FFT-N_CP+rd_ptr], rd_ptr 16..79 → buf[rd_ptr-N_CP]

wire [6:0] rd_buf_idx = (rd_ptr < N_CP) ?
                        (N_FFT - N_CP + rd_ptr[5:0]) :
                        (rd_ptr - N_CP);

wire [31:0] rd_data = (rd_bank == 1'b0) ?
                       buf_a[rd_buf_idx] :
                       buf_b[rd_buf_idx];

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        // BUGFIX: rd_bank starts at 0 (same as wr_bank), so initial fill of
        // bank A (wr_full=1, wr_bank=0) immediately satisfies activation
        // condition wr_bank==rd_bank. Original 1'b1 caused permanent deadlock.
        rd_bank       <= 1'b0;
        rd_ptr        <= 7'd0;
        rd_active     <= 1'b0;
        m_axis_tvalid <= 1'b0;
        m_axis_tdata  <= 32'd0;
    end else begin
        // Activate reader when writer finishes a bank
        if (!rd_active && wr_full && (wr_bank == rd_bank)) begin
            rd_active <= 1'b1;
            rd_ptr    <= 7'd0;
        end

        if (rd_active) begin
            m_axis_tvalid <= 1'b1;
            m_axis_tdata  <= rd_data;

            if (m_axis_tready) begin
                if (rd_ptr == N_OUT - 1) begin
                    rd_ptr    <= 7'd0;
                    rd_active <= 1'b0;
                    rd_bank   <= ~rd_bank;  // Switch to other bank next
                    // BUGFIX: Do NOT set m_axis_tvalid<=0 here. The last
                    // sample of the burst (rd_ptr=79) needs tvalid=1 in
                    // the same cycle. Previously the second NBA assignment
                    // overrode the first, dropping 1 valid every 80 cycles
                    // — causing each burst to emit only 79 valids and the
                    // fifo content in the testbench to lose 1 sample per
                    // symbol, mis-aligning every subsequent symbol on RX.
                end else begin
                    rd_ptr <= rd_ptr + 1'b1;
                end
            end
        end else begin
            m_axis_tvalid <= 1'b0;
        end
    end
end

endmodule
