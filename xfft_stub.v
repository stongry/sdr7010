`timescale 1ns/1ps
module xfft_stub (
    input  wire        aclk,
    input  wire        aresetn,
    input  wire [7:0]  s_axis_config_tdata,
    input  wire        s_axis_config_tvalid,
    output wire        s_axis_config_tready,
    input  wire [31:0] s_axis_data_tdata,
    input  wire        s_axis_data_tvalid,
    output wire        s_axis_data_tready,
    input  wire        s_axis_data_tlast,
    output wire [31:0] m_axis_data_tdata,
    output wire        m_axis_data_tvalid,
    input  wire        m_axis_data_tready,
    output wire        m_axis_data_tlast
);
    // Combinatorial pass-through (no latency, proper AXI-S backpressure)
    assign s_axis_config_tready = 1'b1;
    assign s_axis_data_tready   = m_axis_data_tready;
    assign m_axis_data_tdata    = s_axis_data_tdata;
    assign m_axis_data_tvalid   = s_axis_data_tvalid;
    assign m_axis_data_tlast    = s_axis_data_tlast;
endmodule
