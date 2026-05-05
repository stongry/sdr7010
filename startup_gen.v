// =============================================================================
// startup_gen.v — One-shot pulse after reset de-assertion
// Generates a single-cycle pulse DELAY clocks after rst_n goes high.
// Used to auto-trigger tx_valid_in without PS ARM involvement.
// =============================================================================
`timescale 1ns/1ps

module startup_gen #(
    parameter DELAY = 1000
)(
    input  wire clk,
    input  wire rst_n,
    output reg  pulse_out
);

localparam CNT_W = $clog2(DELAY + 1);

reg [CNT_W-1:0] cnt;
reg done;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        cnt       <= {CNT_W{1'b0}};
        done      <= 1'b0;
        pulse_out <= 1'b0;
    end else begin
        pulse_out <= 1'b0;
        if (!done) begin
            if (cnt == DELAY[CNT_W-1:0] - 1) begin
                pulse_out <= 1'b1;
                done      <= 1'b1;
            end else begin
                cnt <= cnt + 1'b1;
            end
        end
    end
end

endmodule
