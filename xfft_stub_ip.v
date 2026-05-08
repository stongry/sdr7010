`timescale 1ns/1ps
//-----------------------------------------------------------------------------
// xfft_stub_ip.v — Vivado xfft_v9.1 IP wrapper, unscaled + natural_order
//-----------------------------------------------------------------------------
// Same module name `xfft_stub` and same 32-bit AXI-S ports as the xsim
// behavioral DFT, but internally instantiates the Vivado xfft_v9.1 IP in
// **unscaled** mode (preserves full numeric range, no per-stage shift loss)
// with **natural_order** output (so cp_insert/cp_remove see normal time-
// domain index order, not bit-reversed).
//
// IP characteristics in this configuration:
//   - input_width  = 16 (signed)
//   - output_width = 23 (= 16 + log2(64) sign + growth)
//   - m_axis_data_tdata = 48 bit:  {imag[23:0], real[23:0]}
//                                   sign-extended into bit 23
//
// Cascade behaviour:
//   xsim 1/8 double-scale  : FFT(IFFT(X)) = X (sign 100% preserved)
//   IP scaled (1/N each)   : cascade = X / 4096  (sim mismatch)
//   IP BFP                 : adaptive scale (sim mismatch, ~14 bit raw flips)
//   IP unscaled + sat16    : cascade = X * N (saturates to ±32767, sign 100%
//                            preserved on saturation, magnitude clipped)
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

// IP wider output: 48 bit packed {im[23:0], re[23:0]}, each 23 bit signed
// with bit 23 reserved (sign-ext or 0). Unscaled mode has no status channel.
wire [47:0] ip_m_tdata;

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
    .m_axis_data_tdata          (ip_m_tdata),
    .m_axis_data_tvalid         (m_axis_data_tvalid),
    .m_axis_data_tready         (m_axis_data_tready),
    .m_axis_data_tlast          (m_axis_data_tlast),
    .event_frame_started        (),
    .event_tlast_unexpected     (),
    .event_tlast_missing        (),
    .event_status_channel_halt  (),
    .event_data_in_channel_halt (),
    .event_data_out_channel_halt()
);

// Saturate signed 23-bit IP output to signed 16-bit AXI-S output.
// Sign always preserved on saturation (clipped to ±32767), magnitude
// information up to ±32767 retained.  Best of the wrapper variants we
// tried — board cascade leaves only 6 raw bit flips out of 96 LLRs,
// the smallest residual error in this design path.
function automatic signed [15:0] sat16;
    input signed [22:0] v;
    begin
        if (v >  23'sd32767)  sat16 =  16'sd32767;
        else if (v < -23'sd32768) sat16 = -16'sd32768;
        else                  sat16 = v[15:0];
    end
endfunction

wire signed [22:0] re23 = $signed(ip_m_tdata[22:0]);
wire signed [22:0] im23 = $signed(ip_m_tdata[46:24]);

assign m_axis_data_tdata = {sat16(im23), sat16(re23)};

endmodule
