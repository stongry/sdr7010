`timescale 1ns/1ps
//-----------------------------------------------------------------------------
// xfft_stub_ip.v — Vivado xfft_v9.1 IP wrapper for synthesis (Phase 2)
//-----------------------------------------------------------------------------
// Same module name `xfft_stub` and same port list as the simulation
// behavioral DFT (xfft_stub.v). When the build flow includes this file
// (and excludes xfft_stub.v), every existing instantiation in
// ofdm_ldpc_top is mapped to the real Vivado xfft_v9.1 IP without any
// other RTL change.
//
// IP configuration (see ip_xfft/xfft_64/xfft_64.xci):
//   transform_length     = 64
//   implementation       = pipelined_streaming_io
//   data_format          = fixed_point
//   input_width          = 16
//   scaling_options      = scaled (each stage shifts; total = /N = /64)
//   rounding_modes       = convergent_rounding
//   throttle_scheme      = nonrealtime  (full AXI-S backpressure)
//-----------------------------------------------------------------------------

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

// BFP mode adds an m_axis_status_* AXI-S channel carrying the block
// exponent. We don't need the exponent (QPSK + LDPC are sign-only) so
// we accept it with tready=1 and ignore the data.
wire [7:0] u_status_tdata;
wire       u_status_tvalid;

xfft_64 u_xfft_64 (
    .aclk                       (aclk),
    .aresetn                    (aresetn),
    .s_axis_config_tdata        (s_axis_config_tdata),
    .s_axis_config_tvalid       (s_axis_config_tvalid),
    .s_axis_config_tready       (s_axis_config_tready),
    .s_axis_data_tdata          (s_axis_data_tdata),
    .s_axis_data_tvalid         (s_axis_data_tvalid),
    .s_axis_data_tready         (s_axis_data_tready),
    .s_axis_data_tlast          (s_axis_data_tlast),
    .m_axis_data_tdata          (m_axis_data_tdata),
    .m_axis_data_tvalid         (m_axis_data_tvalid),
    .m_axis_data_tready         (m_axis_data_tready),
    .m_axis_data_tlast          (m_axis_data_tlast),
    .m_axis_status_tdata        (u_status_tdata),
    .m_axis_status_tvalid       (u_status_tvalid),
    .m_axis_status_tready       (1'b1),
    .event_frame_started        (),
    .event_tlast_unexpected     (),
    .event_tlast_missing        (),
    .event_status_channel_halt  (),
    .event_data_in_channel_halt (),
    .event_data_out_channel_halt()
);

endmodule
