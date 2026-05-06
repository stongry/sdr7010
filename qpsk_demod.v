`timescale 1ns/1ps
module qpsk_demod #(
    parameter SCALE = 7   // Right-shift for LLR normalization
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [15:0] I_in,      // Equalized I (signed 16-bit)
    input  wire [15:0] Q_in,      // Equalized Q (signed 16-bit)
    input  wire        valid_in,
    output reg  [7:0]  llr0,      // LLR for b0 (from I), signed 8-bit
    output reg  [7:0]  llr1,      // LLR for b1 (from Q), signed 8-bit
    output reg         valid_out
);

// Arithmetic right-shift (sign-extending) of signed 16-bit by SCALE bits
// Verilog-2001: use $signed for arithmetic shift
wire signed [15:0] I_s = $signed(I_in);
wire signed [15:0] Q_s = $signed(Q_in);

// Shifted values (still 16-bit signed, upper bits are sign extension)
wire signed [15:0] I_sh = I_s >>> SCALE;
wire signed [15:0] Q_sh = Q_s >>> SCALE;

// Saturation to [-127, +127]
function [7:0] sat8;
    input signed [15:0] x;
    begin
        if (x > 16'sd127)       sat8 = 8'sd127;
        else if (x < -16'sd127) sat8 = -8'sd127;
        else                    sat8 = x[7:0];
    end
endfunction

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        llr0      <= 8'h00;
        llr1      <= 8'h00;
        valid_out <= 1'b0;
    end else begin
        valid_out <= valid_in;
        if (valid_in) begin
            llr0 <= sat8(I_sh);   // b0 LLR from I
            llr1 <= sat8(Q_sh);   // b1 LLR from Q
        end
    end
end

endmodule
