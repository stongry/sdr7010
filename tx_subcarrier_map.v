module tx_subcarrier_map #(
    parameter N_FFT  = 64,
    parameter N_DATA = 48,
    parameter N_SYM  = 11,
    parameter N_CW   = 1024,
    parameter PILOT_A = 16'sd5793
)(
    input  wire             clk,
    input  wire             rst_n,
    input  wire [N_CW-1:0]  codeword,
    input  wire             codeword_vld,
    output wire [31:0]      ifft_tdata,
    output wire             ifft_tvalid,
    input  wire             ifft_tready
);

// Data subcarrier positions (48 bins): 1-6, 8-20, 22-26, 38-42, 44-56, 58-63
// Pilot positions: 7, 21, 43, 57
// Null: 0, 27-37

// Simple FSM: when codeword_vld, stream 64 bins per OFDM symbol for N_SYM symbols.
// For each symbol, iterate over 64 bins; output pilot or data or null.

reg [9:0]  bit_ptr;      // Current bit position in codeword (0..1023)
reg [5:0]  bin_ptr;      // Current FFT bin (0..63)
reg [3:0]  sym_cnt;      // Current OFDM symbol (0..10)
reg        active;

// Determine if a bin is a pilot
function is_pilot;
    input [5:0] b;
    begin
        is_pilot = (b == 7) || (b == 21) || (b == 43) || (b == 57);
    end
endfunction

// Determine if a bin is a data bin
function is_data;
    input [5:0] b;
    begin
        is_data = ((b >= 1  && b <= 6)  ||
                   (b >= 8  && b <= 20) ||
                   (b >= 22 && b <= 26) ||
                   (b >= 38 && b <= 42) ||
                   (b >= 44 && b <= 56) ||
                   (b >= 58 && b <= 63));
    end
endfunction

reg [N_CW-1:0] cw_reg;

// BUGFIX: BOTH ifft_tdata AND ifft_tvalid are COMBINATIONAL on the current
// (bin_ptr, bit_ptr, cw_reg, active).  This way the AXI-S handshake at any
// cycle reads the data for the current bin_ptr, with no 1-cycle skew that
// previously dropped the first sample after backpressure released and
// clobbered every new bank's slot 0 with the prior symbol's last bin.
assign ifft_tdata =
    is_pilot(bin_ptr) ? {16'd0, PILOT_A} :
    (is_data(bin_ptr) && bit_ptr < N_CW-1) ?
        { cw_reg[bit_ptr+1] ? 16'hE95F : PILOT_A[15:0],
          cw_reg[bit_ptr]   ? 16'hE95F : PILOT_A[15:0] } :
    32'd0;
assign ifft_tvalid = active;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        active      <= 1'b0;
        bit_ptr     <= 10'd0;
        bin_ptr     <= 6'd0;
        sym_cnt     <= 4'd0;
        cw_reg      <= {N_CW{1'b0}};
    end else begin
        if (codeword_vld && !active) begin
            cw_reg  <= codeword;
            active  <= 1'b1;
            bit_ptr <= 10'd0;
            bin_ptr <= 6'd0;
            sym_cnt <= 4'd0;
        end

        if (active && ifft_tready) begin
            // Advance bit_ptr only when this bin actually consumes 2 cw bits
            if (is_data(bin_ptr) && bit_ptr < N_CW-1)
                bit_ptr <= bit_ptr + 2;

            // Advance bin
            if (bin_ptr == N_FFT - 1) begin
                bin_ptr <= 6'd0;
                if (sym_cnt == N_SYM - 1) begin
                    active <= 1'b0;
                end else begin
                    sym_cnt <= sym_cnt + 1'b1;
                end
            end else begin
                bin_ptr <= bin_ptr + 1'b1;
            end
        end
    end
end

endmodule
