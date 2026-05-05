module qpsk_mod (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [1:0]  bits_in,   // {b1, b0} — b0 = bits_in[0], b1 = bits_in[1]
    input  wire        valid_in,
    output reg  [15:0] I_out,     // Signed 16-bit I component
    output reg  [15:0] Q_out,     // Signed 16-bit Q component
    output reg         valid_out
);

// A = floor(32767 / sqrt(2)) = 23170  — full 16-bit range version
// For consistency with demodulator SCALE=7: 23170 >> 7 = 181 ≈ not ideal.
// Use A = 5793 = round(8192 / sqrt(2)) so that after demod shift-right-7
// we get a reasonable LLR range.  2^13 = 8192, 8192/sqrt(2) ≈ 5792.6
localparam signed [15:0] A_POS =  16'sd5793;
localparam signed [15:0] A_NEG = -16'sd5793;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        I_out     <= 16'sd0;
        Q_out     <= 16'sd0;
        valid_out <= 1'b0;
    end else begin
        valid_out <= valid_in;
        if (valid_in) begin
            // b0 = bits_in[0] controls I (real)
            // b1 = bits_in[1] controls Q (imaginary)
            // Mapping: 0 → +A, 1 → -A
            I_out <= bits_in[0] ? A_NEG : A_POS;
            Q_out <= bits_in[1] ? A_NEG : A_POS;
        end
    end
end

endmodule
