// =============================================================================
// system_top.v — pluto_ldsdr top wrapper (LVDS mode, xc7z010clg400-2)
//
// Diff from pluto: rx/tx data are LVDS differential pairs (6 pairs each
// vs pluto's 12 single-ended).  axi_ad9361 IP CMOS_OR_LVDS_N=0 handles
// LVDS internally (IBUFDS/OBUFDS infer at IO).  External GPIOs follow
// LDSDR clg400 pinout.
// =============================================================================
`timescale 1ns/100ps

module system_top (
  inout   [14:0]  ddr_addr,
  inout   [ 2:0]  ddr_ba,
  inout           ddr_cas_n,
  inout           ddr_ck_n,
  inout           ddr_ck_p,
  inout           ddr_cke,
  inout           ddr_cs_n,
  inout   [ 1:0]  ddr_dm,
  inout   [15:0]  ddr_dq,
  inout   [ 1:0]  ddr_dqs_n,
  inout   [ 1:0]  ddr_dqs_p,
  inout           ddr_odt,
  inout           ddr_ras_n,
  inout           ddr_reset_n,
  inout           ddr_we_n,

  inout           fixed_io_ddr_vrn,
  inout           fixed_io_ddr_vrp,
  inout   [53:0]  fixed_io_mio,
  inout           fixed_io_ps_clk,
  inout           fixed_io_ps_porb,
  inout           fixed_io_ps_srstb,

  // LVDS RX (6 pairs DDR data + clk + frame)
  input           rx_clk_in_p,
  input           rx_clk_in_n,
  input           rx_frame_in_p,
  input           rx_frame_in_n,
  input   [ 5:0]  rx_data_in_p,
  input   [ 5:0]  rx_data_in_n,

  // LVDS TX
  output          tx_clk_out_p,
  output          tx_clk_out_n,
  output          tx_frame_out_p,
  output          tx_frame_out_n,
  output  [ 5:0]  tx_data_out_p,
  output  [ 5:0]  tx_data_out_n,

  // AD9363 control (LVCMOS25 on LDSDR clg400)
  output          enable,
  output          txnrx,
  output          en_agc,
  output          resetb,

  // SPI
  output          spi_csn,
  output          spi_clk,
  output          spi_mosi,
  input           spi_miso
);

  // GPIO bus internal (mirror pluto layout but reduced - we don't need
  // gpio_status[7:0]/gpio_ctl[3:0] going to pins; they go to internal DEBUG)
  wire [17:0] gpio_i;
  wire [17:0] gpio_o;
  wire [17:0] gpio_t;

  // bit map (matches axi_ad9361 expectation):
  //  [13]=resetb, [12]=en_agc, [11:8]=ctrl_in unused, [7:0]=status unused
  wire gpio_resetb_o;
  wire gpio_en_agc_o;
  wire gpio_resetb_t;
  wire gpio_en_agc_t;
  assign gpio_resetb_o = gpio_o[13];
  assign gpio_en_agc_o = gpio_o[12];
  assign gpio_resetb_t = gpio_t[13];
  assign gpio_en_agc_t = gpio_t[12];

  // ad_iobuf for resetb / en_agc (Linux ad9361 driver toggles via EMIO)
  ad_iobuf #(
    .DATA_WIDTH(2)
  ) i_iobuf_ctl (
    .dio_t ({gpio_resetb_t, gpio_en_agc_t}),
    .dio_i ({gpio_resetb_o, gpio_en_agc_o}),
    .dio_o ({gpio_i[13],     gpio_i[12]}),
    .dio_p ({resetb,         en_agc}));

  // Tie remaining GPIO bits to their out values (loopback)
  assign gpio_i[11:0]  = gpio_o[11:0];
  assign gpio_i[17:14] = gpio_o[17:14];

  system_wrapper i_system_wrapper (
    .ddr_addr(ddr_addr), .ddr_ba(ddr_ba),
    .ddr_cas_n(ddr_cas_n), .ddr_ck_n(ddr_ck_n), .ddr_ck_p(ddr_ck_p),
    .ddr_cke(ddr_cke), .ddr_cs_n(ddr_cs_n),
    .ddr_dm(ddr_dm), .ddr_dq(ddr_dq),
    .ddr_dqs_n(ddr_dqs_n), .ddr_dqs_p(ddr_dqs_p),
    .ddr_odt(ddr_odt), .ddr_ras_n(ddr_ras_n),
    .ddr_reset_n(ddr_reset_n), .ddr_we_n(ddr_we_n),
    .enable(enable), .txnrx(txnrx),
    .fixed_io_ddr_vrn(fixed_io_ddr_vrn), .fixed_io_ddr_vrp(fixed_io_ddr_vrp),
    .fixed_io_mio(fixed_io_mio),
    .fixed_io_ps_clk(fixed_io_ps_clk),
    .fixed_io_ps_porb(fixed_io_ps_porb), .fixed_io_ps_srstb(fixed_io_ps_srstb),
    .gpio_i(gpio_i), .gpio_o(gpio_o), .gpio_t(gpio_t),
    // LVDS RX/TX  (axi_ad9361 with LVDS=1 will infer IBUFDS/OBUFDS)
    .rx_clk_in_p(rx_clk_in_p), .rx_clk_in_n(rx_clk_in_n),
    .rx_frame_in_p(rx_frame_in_p), .rx_frame_in_n(rx_frame_in_n),
    .rx_data_in_p(rx_data_in_p), .rx_data_in_n(rx_data_in_n),
    .tx_clk_out_p(tx_clk_out_p), .tx_clk_out_n(tx_clk_out_n),
    .tx_frame_out_p(tx_frame_out_p), .tx_frame_out_n(tx_frame_out_n),
    .tx_data_out_p(tx_data_out_p), .tx_data_out_n(tx_data_out_n),
    // SPI
    .spi0_clk_i(1'b0), .spi0_clk_o(spi_clk),
    .spi0_csn_0_o(spi_csn), .spi0_csn_1_o(), .spi0_csn_2_o(),
    .spi0_csn_i(1'b1),
    .spi0_sdi_i(spi_miso),
    .spi0_sdo_i(1'b0), .spi0_sdo_o(spi_mosi),
    // Unused phaser SPI tied off
    .spi_clk_i(1'b0), .spi_clk_o(),
    .spi_csn_i(1'b1), .spi_csn_o(),
    .spi_sdi_i(1'b0),
    .spi_sdo_i(1'b0), .spi_sdo_o(),
    .tdd_ext_sync(1'b0),
    .txdata_o(),
    .up_enable(gpio_o[15]),
    .up_txnrx(gpio_o[16]));

endmodule
