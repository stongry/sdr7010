module rx_subcarrier_demap #(
    parameter N_FFT  = 64,
    parameter N_DATA = 48,
    parameter N_SYM  = 11
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [15:0] eq_i,
    input  wire [15:0] eq_q,
    input  wire        eq_valid,
    output reg  [15:0] demod_i,
    output reg  [15:0] demod_q,
    output reg         demod_valid
);

// Channel estimator outputs all 64 bins; track bin index and pass data only.
reg [5:0] bin_cnt;

function is_data_bin;
    input [5:0] b;
    begin
        is_data_bin = ((b >= 1  && b <= 6)  ||
                       (b >= 8  && b <= 20) ||
                       (b >= 22 && b <= 26) ||
                       (b >= 38 && b <= 42) ||
                       (b >= 44 && b <= 56) ||
                       (b >= 58 && b <= 63));
    end
endfunction

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        bin_cnt     <= 6'd0;
        demod_i     <= 16'd0;
        demod_q     <= 16'd0;
        demod_valid <= 1'b0;
    end else begin
        demod_valid <= 1'b0;
        if (eq_valid) begin
            if (is_data_bin(bin_cnt)) begin
                demod_i     <= eq_i;
                demod_q     <= eq_q;
                demod_valid <= 1'b1;
            end
            bin_cnt <= (bin_cnt == N_FFT-1) ? 6'd0 : bin_cnt + 1'b1;
        end
    end
end

endmodule
