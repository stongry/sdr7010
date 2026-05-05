module llr_assembler #(
    parameter N_CW = 1024
)(
    input  wire             clk,
    input  wire             rst_n,
    input  wire [7:0]       llr0,
    input  wire [7:0]       llr1,
    input  wire             valid_in,
    output reg  [N_CW*8-1:0] llr_out,
    output reg              valid_out
);

reg [9:0] cnt;   // 0 .. N_CW/2 - 1 = 511

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        cnt       <= 10'd0;
        valid_out <= 1'b0;
    end else begin
        valid_out <= 1'b0;
        if (valid_in) begin
            llr_out[cnt*8     +: 8] <= llr0;
            llr_out[cnt*8 + 8 +: 8] <= llr1;  // Wait — need to interleave correctly
            // Bit index: bit 2*cnt → llr0, bit 2*cnt+1 → llr1
            // LLR index for LDPC: llr[2*cnt] = llr0, llr[2*cnt+1] = llr1
            if (cnt == N_CW/2 - 1) begin
                cnt       <= 10'd0;
                valid_out <= 1'b1;
            end else begin
                cnt <= cnt + 1'b1;
            end
        end
    end
end

endmodule
