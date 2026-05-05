module llr_buffer #(
    parameter N_CW = 1024
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [7:0]  llr0,
    input  wire [7:0]  llr1,
    input  wire        valid_in,
    output reg         valid_out,
    // Async read port for ldpc_decoder (driven by llr_rd_addr = init_cnt)
    input  wire [9:0]  rd_addr,
    output wire [7:0]  rd_data
);

// Two 512×8 LUTRAM arrays.  No async reset on write blocks — required for
// Vivado distributed-RAM inference (same rule as ldpc_decoder's ch/v_llr).
(* ram_style = "distributed" *) reg [7:0] buf_e [0:N_CW/2-1]; // LLR[0,2,4,...,1022]
(* ram_style = "distributed" *) reg [7:0] buf_o [0:N_CW/2-1]; // LLR[1,3,5,...,1023]

reg [8:0] wr_cnt;   // 0 .. N_CW/2-1 = 0..511

// Write ports — posedge only, no reset sensitivity
always @(posedge clk) begin
    if (valid_in) begin
        buf_e[wr_cnt] <= llr0;
        buf_o[wr_cnt] <= llr1;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        wr_cnt    <= 9'd0;
        valid_out <= 1'b0;
    end else begin
        valid_out <= 1'b0;
        if (valid_in) begin
            if (wr_cnt == N_CW/2 - 1) begin
                wr_cnt    <= 9'd0;
                valid_out <= 1'b1;
            end else begin
                wr_cnt <= wr_cnt + 1'b1;
            end
        end
    end
end

// Async read: select even or odd half based on byte-address LSB
assign rd_data = rd_addr[0] ? buf_o[rd_addr[9:1]] : buf_e[rd_addr[9:1]];

endmodule
