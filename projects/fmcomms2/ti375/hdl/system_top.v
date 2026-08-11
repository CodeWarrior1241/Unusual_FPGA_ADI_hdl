// ***************************************************************************
// FMCOMMS2/3 on Efinix Titanium Ti375C529 Development Kit - top level.
//
// Efinix port of the MPF300 SmartDesign "Top" (build_all.tcl:594-894) /
// the axau15 Vivado block design: NEORV32 RISC-V CPU + axi_ad9361 +
// SmartHLS adapters + Bedrock CDC FIFOs + QPSK snapshot BRAM, same AXI
// address map and GPIO map, so the ad9361_no-os software in
// deps/neorv32/sw/ad9361_no-os runs unmodified.
//
// On Efinix there is no SmartDesign/IPI canvas: this file IS the top
// level. All I/O primitives live in the configured periphery
// (scripts/gen_interface.py); the ports below are the core-periphery
// boundary, by pin name:
//
//   clk_125mhz       sys_pll CLKOUT0 (125 MHz from the 25 MHz OSC1 pad)
//   sys_pll_locked   sys_pll LOCKED (async)
//   l_clk            lvds_pll CLKOUT0: 61.44 MHz, 0 deg, from the AD9361
//                    DATA_CLK (rx_clk enters on GCLK CLK7 and references
//                    PLL BR0 through the core clock tree, see README).
//                    The +90 deg CLKOUT1 (l_clk_90) exists only inside
//                    the periphery: it launches the FB_CLK TX lane.
//   lvds_pll_locked  lvds_pll LOCKED (async; folded into adc_status
//                    inside the efinix axi_ad9361_lvds_if)
//   rx_frame, rx_data_*   LVDS RX x2 half-rate deserializer words
//                    (bit 0 = first captured bit, bit 1 = second)
//   tx_frame, tx_data_*   LVDS TX x2 half-rate serializer words
//                    (bit 0 transmitted first, bit 1 second)
//
// The PolarFire PF_INIT_MONITOR has no analog here: Efinity bakes RAM
// init into the bitstream and user logic starts after it completes, so
// sys_ctrl's init_done/sram_init_done inputs are tied high.
// ***************************************************************************

`timescale 1ns/100ps

module system_top (

  // clocks and locks from the periphery PLLs

  input           clk_125mhz,
  input           sys_pll_locked,
  input           rx_clk,           // AD9361 DATA_CLK on GCLK CLK7; consumed
                                    // only by the periphery lvds_pll (core-
                                    // tree reference) -- unused in the core
  input           l_clk,
  input           lvds_pll_locked,

  // board

  input           sys_resetn_pin,   // SW3 pushbutton, active low
  input           sys_uart_rx,      // FT4232H channel C
  output          sys_uart_tx,

  // AD9361 SPI + control/status (FMC LA singles, 1.8 V LVCMOS)

  output          spi_clk,
  output          spi_mosi,
  input           spi_miso,
  output          spi_csn_0,
  output          gpio_resetb,
  output          gpio_sync,
  output          gpio_en_agc,
  output  [ 3:0]  gpio_ctl,
  input   [ 7:0]  gpio_status,
  output          enable,
  output          txnrx,

  // AD9361 LVDS interface: x2 half-rate SERDES words at the core boundary

  input   [ 1:0]  rx_frame,
  input   [ 1:0]  rx_data_0,
  input   [ 1:0]  rx_data_1,
  input   [ 1:0]  rx_data_2,
  input   [ 1:0]  rx_data_3,
  input   [ 1:0]  rx_data_4,
  input   [ 1:0]  rx_data_5,
  output  [ 1:0]  tx_frame,
  output  [ 1:0]  tx_data_0,
  output  [ 1:0]  tx_data_1,
  output  [ 1:0]  tx_data_2,
  output  [ 1:0]  tx_data_3,
  output  [ 1:0]  tx_data_4,
  output  [ 1:0]  tx_data_5,

  // per-lane LVDS SERDES controls. The periphery requires one uniquely
  // named INRST/RST/OE pin per lane (sharing one core pin across lanes
  // is rejected by the Interface Designer); all are driven from the one
  // internal serdes_rst_s / constant-1 below.

  output          rx_frame_lane_RX_RST,
  output          rx_data_0_lane_RX_RST,
  output          rx_data_1_lane_RX_RST,
  output          rx_data_2_lane_RX_RST,
  output          rx_data_3_lane_RX_RST,
  output          rx_data_4_lane_RX_RST,
  output          rx_data_5_lane_RX_RST,
  output          tx_frame_lane_TX_RST,
  output          tx_data_0_lane_TX_RST,
  output          tx_data_1_lane_TX_RST,
  output          tx_data_2_lane_TX_RST,
  output          tx_data_3_lane_TX_RST,
  output          tx_data_4_lane_TX_RST,
  output          tx_data_5_lane_TX_RST,
  output          tx_clk_out_lane_TX_RST,
  output          tx_frame_lane_TX_OE,
  output          tx_data_0_lane_TX_OE,
  output          tx_data_1_lane_TX_OE,
  output          tx_data_2_lane_TX_OE,
  output          tx_data_3_lane_TX_OE,
  output          tx_data_4_lane_TX_OE,
  output          tx_data_5_lane_TX_OE,
  output          tx_clk_out_lane_TX_OE
);

  // system control / resets (125 MHz domain)

  wire            sys_resetn;
  wire            sys_reset;
  wire            aresetn_gated;
  wire            pwr_dn;
  wire            up_enable_s;
  wire            up_txnrx_s;

  // l_clk domain (from the axi_ad9361 l_clk passthrough, same topology
  // as the other two ports)

  wire            l_clk_s;
  wire            lclk_reset;
  wire            lclk_resetn;

  // NEORV32 <-> decoder AXI4 (single-beat)

  wire    [31:0]  m_axi_awaddr;
  wire    [ 7:0]  m_axi_awlen;
  wire    [ 2:0]  m_axi_awsize;
  wire    [ 1:0]  m_axi_awburst;
  wire    [ 2:0]  m_axi_awprot;
  wire            m_axi_awvalid;
  wire            m_axi_awready;
  wire    [31:0]  m_axi_wdata;
  wire    [ 3:0]  m_axi_wstrb;
  wire            m_axi_wlast;
  wire            m_axi_wvalid;
  wire            m_axi_wready;
  wire    [ 1:0]  m_axi_bresp;
  wire            m_axi_bvalid;
  wire            m_axi_bready;
  wire    [31:0]  m_axi_araddr;
  wire    [ 7:0]  m_axi_arlen;
  wire    [ 2:0]  m_axi_arsize;
  wire    [ 1:0]  m_axi_arburst;
  wire    [ 2:0]  m_axi_arprot;
  wire            m_axi_arvalid;
  wire            m_axi_arready;
  wire    [31:0]  m_axi_rdata;
  wire    [ 1:0]  m_axi_rresp;
  wire            m_axi_rlast;
  wire            m_axi_rvalid;
  wire            m_axi_rready;

  // decoder M0 <-> QPSK snapshot BRAM

  wire    [31:0]  m0_awaddr;
  wire            m0_awvalid;
  wire            m0_awready;
  wire    [31:0]  m0_wdata;
  wire    [ 3:0]  m0_wstrb;
  wire            m0_wvalid;
  wire            m0_wready;
  wire    [ 1:0]  m0_bresp;
  wire            m0_bvalid;
  wire            m0_bready;
  wire    [31:0]  m0_araddr;
  wire            m0_arvalid;
  wire            m0_arready;
  wire    [31:0]  m0_rdata;
  wire    [ 1:0]  m0_rresp;
  wire            m0_rvalid;
  wire            m0_rready;

  // decoder M1 <-> axi_ad9361 s_axi (AXI4-Lite)

  wire    [15:0]  m1_awaddr;
  wire    [ 2:0]  m1_awprot;
  wire            m1_awvalid;
  wire            m1_awready;
  wire    [31:0]  m1_wdata;
  wire    [ 3:0]  m1_wstrb;
  wire            m1_wvalid;
  wire            m1_wready;
  wire    [ 1:0]  m1_bresp;
  wire            m1_bvalid;
  wire            m1_bready;
  wire    [15:0]  m1_araddr;
  wire    [ 2:0]  m1_arprot;
  wire            m1_arvalid;
  wire            m1_arready;
  wire    [31:0]  m1_rdata;
  wire    [ 1:0]  m1_rresp;
  wire            m1_rvalid;
  wire            m1_rready;

  // decoder M2 <-> streaming adapter (SmartHLS AXI4 subset)

  wire    [31:0]  m2_awaddr;
  wire    [ 7:0]  m2_awlen;
  wire    [ 2:0]  m2_awsize;
  wire    [ 1:0]  m2_awburst;
  wire            m2_awvalid;
  wire            m2_awready;
  wire    [31:0]  m2_wdata;
  wire    [ 3:0]  m2_wstrb;
  wire            m2_wlast;
  wire            m2_wvalid;
  wire            m2_wready;
  wire    [ 1:0]  m2_bresp;
  wire            m2_bvalid;
  wire            m2_bready;
  wire    [31:0]  m2_araddr;
  wire    [ 7:0]  m2_arlen;
  wire    [ 2:0]  m2_arsize;
  wire    [ 1:0]  m2_arburst;
  wire            m2_arvalid;
  wire            m2_arready;
  wire    [31:0]  m2_rdata;
  wire    [ 1:0]  m2_rresp;
  wire            m2_rlast;
  wire            m2_rvalid;
  wire            m2_rready;

  // NEORV32 GPIO / SPI

  wire    [15:0]  gpio_o_s;
  wire    [ 7:0]  spi_csn_s;

  // axi_ad9361 <-> HLS adapter datapath (l_clk domain)

  wire            adc_enable_i0, adc_valid_i0;
  wire    [15:0]  adc_data_i0;
  wire            adc_enable_q0, adc_valid_q0;
  wire    [15:0]  adc_data_q0;
  wire            adc_enable_i1, adc_valid_i1;
  wire    [15:0]  adc_data_i1;
  wire            adc_enable_q1, adc_valid_q1;
  wire    [15:0]  adc_data_q1;
  wire            dac_enable_i0, dac_valid_i0;
  wire    [15:0]  dac_data_i0;
  wire            dac_enable_q0, dac_valid_q0;
  wire    [15:0]  dac_data_q0;
  wire            dac_enable_i1, dac_valid_i1;
  wire    [15:0]  dac_data_i1;
  wire            dac_enable_q1, dac_valid_q1;
  wire    [15:0]  dac_data_q1;
  wire            dac_dunf;

  wire            dac_data_i0_write_en;
  wire    [15:0]  dac_data_i0_write_data;
  wire            dac_data_q0_write_en;
  wire    [15:0]  dac_data_q0_write_data;
  wire            dac_data_i1_write_en;
  wire    [15:0]  dac_data_i1_write_data;
  wire            dac_data_q1_write_en;
  wire    [15:0]  dac_data_q1_write_data;
  wire            dac_dunf_write_en;
  wire            dac_dunf_write_data;

  wire            dac_sync_s;

  // AXI-Stream paths through the CDC FIFOs

  wire    [31:0]  tx_up_data,  tx_lclk_data;
  wire    [ 3:0]  tx_up_keep,  tx_lclk_keep;
  wire    [ 3:0]  tx_up_strb,  tx_lclk_strb;
  wire            tx_up_last,  tx_lclk_last;
  wire            tx_up_valid, tx_lclk_valid;
  wire            tx_up_ready, tx_lclk_ready;
  wire    [31:0]  rx_up_data,  rx_lclk_data;
  wire    [ 3:0]  rx_up_keep,  rx_lclk_keep;
  wire    [ 3:0]  rx_up_strb,  rx_lclk_strb;
  wire            rx_up_last,  rx_lclk_last;
  wire            rx_up_valid, rx_lclk_valid;
  wire            rx_up_ready, rx_lclk_ready;

  // LVDS SERDES controls: hold the (de)serializers in reset while the
  // l_clk domain is in reset or the lvds_pll is unlocked, so the x2
  // word alignment re-forms cleanly on every power_up relock (the same
  // moment the MPF300 design re-verified PLL lock before resuming)

  reg lvds_locked_m1 = 1'b0;
  reg lvds_locked_m2 = 1'b0;

  always @(posedge l_clk) begin
    lvds_locked_m1 <= lvds_pll_locked;
    lvds_locked_m2 <= lvds_locked_m1;
  end

  wire serdes_rst_s = lclk_reset | ~lvds_locked_m2;

  assign rx_frame_lane_RX_RST  = serdes_rst_s;
  assign rx_data_0_lane_RX_RST = serdes_rst_s;
  assign rx_data_1_lane_RX_RST = serdes_rst_s;
  assign rx_data_2_lane_RX_RST = serdes_rst_s;
  assign rx_data_3_lane_RX_RST = serdes_rst_s;
  assign rx_data_4_lane_RX_RST = serdes_rst_s;
  assign rx_data_5_lane_RX_RST = serdes_rst_s;
  assign tx_frame_lane_TX_RST  = serdes_rst_s;
  assign tx_data_0_lane_TX_RST = serdes_rst_s;
  assign tx_data_1_lane_TX_RST = serdes_rst_s;
  assign tx_data_2_lane_TX_RST = serdes_rst_s;
  assign tx_data_3_lane_TX_RST = serdes_rst_s;
  assign tx_data_4_lane_TX_RST = serdes_rst_s;
  assign tx_data_5_lane_TX_RST = serdes_rst_s;
  assign tx_clk_out_lane_TX_RST = serdes_rst_s;

  assign tx_frame_lane_TX_OE  = 1'b1;
  assign tx_data_0_lane_TX_OE = 1'b1;
  assign tx_data_1_lane_TX_OE = 1'b1;
  assign tx_data_2_lane_TX_OE = 1'b1;
  assign tx_data_3_lane_TX_OE = 1'b1;
  assign tx_data_4_lane_TX_OE = 1'b1;
  assign tx_data_5_lane_TX_OE = 1'b1;
  assign tx_clk_out_lane_TX_OE = 1'b1;

  // system control / resets

  sys_ctrl sys_ctrl_0 (
    .clk (clk_125mhz),
    .pll_lock (sys_pll_locked),
    .init_done (1'b1),                // bitstream init is atomic on Efinix
    .sram_init_done (1'b1),
    .ext_resetn (sys_resetn_pin),
    .gpio_o (gpio_o_s),
    .spi_csn_i (spi_csn_s),
    .sys_resetn (sys_resetn),
    .sys_reset (sys_reset),
    .aresetn_gated (aresetn_gated),
    .pwr_dn (pwr_dn),
    .up_enable (up_enable_s),
    .up_txnrx (up_txnrx_s),
    .gpio_resetb (gpio_resetb),
    .gpio_sync (gpio_sync),
    .gpio_en_agc (gpio_en_agc),
    .gpio_ctl (gpio_ctl),
    .spi_csn_0 (spi_csn_0));

  lclk_reset_sync lclk_reset_sync_0 (
    .l_clk (l_clk_s),
    .clk_125 (clk_125mhz),
    .ext_resetn (sys_resetn),
    .pwr_dn (pwr_dn),
    .lclk_resetn (lclk_resetn),
    .lclk_reset (lclk_reset));

  // NEORV32 (identical configuration to axau15/mpf300, 125 MHz)

  neorv32_ti375_top neorv32_risc_v (
    .clk (clk_125mhz),
    .resetn (sys_resetn),
    .m_axi_awaddr (m_axi_awaddr),
    .m_axi_awlen (m_axi_awlen),
    .m_axi_awsize (m_axi_awsize),
    .m_axi_awburst (m_axi_awburst),
    .m_axi_awprot (m_axi_awprot),
    .m_axi_awvalid (m_axi_awvalid),
    .m_axi_awready (m_axi_awready),
    .m_axi_wdata (m_axi_wdata),
    .m_axi_wstrb (m_axi_wstrb),
    .m_axi_wlast (m_axi_wlast),
    .m_axi_wvalid (m_axi_wvalid),
    .m_axi_wready (m_axi_wready),
    .m_axi_bresp (m_axi_bresp),
    .m_axi_bvalid (m_axi_bvalid),
    .m_axi_bready (m_axi_bready),
    .m_axi_araddr (m_axi_araddr),
    .m_axi_arlen (m_axi_arlen),
    .m_axi_arsize (m_axi_arsize),
    .m_axi_arburst (m_axi_arburst),
    .m_axi_arprot (m_axi_arprot),
    .m_axi_arvalid (m_axi_arvalid),
    .m_axi_arready (m_axi_arready),
    .m_axi_rdata (m_axi_rdata),
    .m_axi_rresp (m_axi_rresp),
    .m_axi_rlast (m_axi_rlast),
    .m_axi_rvalid (m_axi_rvalid),
    .m_axi_rready (m_axi_rready),
    .gpio_o (gpio_o_s),
    .gpio_i (gpio_status),
    .uart0_txd_o (sys_uart_tx),
    .uart0_rxd_i (sys_uart_rx),
    .spi_clk_o (spi_clk),
    .spi_dat_o (spi_mosi),
    .spi_dat_i (spi_miso),
    .spi_csn_o (spi_csn_s));

  // AXI fabric + QPSK snapshot BRAM

  axi_1to3_decoder axi_cpu_interconnect (
    .aclk (clk_125mhz),
    .aresetn (sys_resetn),
    .s_awaddr (m_axi_awaddr),
    .s_awlen (m_axi_awlen),
    .s_awsize (m_axi_awsize),
    .s_awburst (m_axi_awburst),
    .s_awprot (m_axi_awprot),
    .s_awvalid (m_axi_awvalid),
    .s_awready (m_axi_awready),
    .s_wdata (m_axi_wdata),
    .s_wstrb (m_axi_wstrb),
    .s_wlast (m_axi_wlast),
    .s_wvalid (m_axi_wvalid),
    .s_wready (m_axi_wready),
    .s_bresp (m_axi_bresp),
    .s_bvalid (m_axi_bvalid),
    .s_bready (m_axi_bready),
    .s_araddr (m_axi_araddr),
    .s_arlen (m_axi_arlen),
    .s_arsize (m_axi_arsize),
    .s_arburst (m_axi_arburst),
    .s_arprot (m_axi_arprot),
    .s_arvalid (m_axi_arvalid),
    .s_arready (m_axi_arready),
    .s_rdata (m_axi_rdata),
    .s_rresp (m_axi_rresp),
    .s_rlast (m_axi_rlast),
    .s_rvalid (m_axi_rvalid),
    .s_rready (m_axi_rready),
    .m0_awaddr (m0_awaddr),
    .m0_awvalid (m0_awvalid),
    .m0_awready (m0_awready),
    .m0_wdata (m0_wdata),
    .m0_wstrb (m0_wstrb),
    .m0_wvalid (m0_wvalid),
    .m0_wready (m0_wready),
    .m0_bresp (m0_bresp),
    .m0_bvalid (m0_bvalid),
    .m0_bready (m0_bready),
    .m0_araddr (m0_araddr),
    .m0_arvalid (m0_arvalid),
    .m0_arready (m0_arready),
    .m0_rdata (m0_rdata),
    .m0_rresp (m0_rresp),
    .m0_rvalid (m0_rvalid),
    .m0_rready (m0_rready),
    .m1_awaddr (m1_awaddr),
    .m1_awprot (m1_awprot),
    .m1_awvalid (m1_awvalid),
    .m1_awready (m1_awready),
    .m1_wdata (m1_wdata),
    .m1_wstrb (m1_wstrb),
    .m1_wvalid (m1_wvalid),
    .m1_wready (m1_wready),
    .m1_bresp (m1_bresp),
    .m1_bvalid (m1_bvalid),
    .m1_bready (m1_bready),
    .m1_araddr (m1_araddr),
    .m1_arprot (m1_arprot),
    .m1_arvalid (m1_arvalid),
    .m1_arready (m1_arready),
    .m1_rdata (m1_rdata),
    .m1_rresp (m1_rresp),
    .m1_rvalid (m1_rvalid),
    .m1_rready (m1_rready),
    .m2_awaddr (m2_awaddr),
    .m2_awlen (m2_awlen),
    .m2_awsize (m2_awsize),
    .m2_awburst (m2_awburst),
    .m2_awvalid (m2_awvalid),
    .m2_awready (m2_awready),
    .m2_wdata (m2_wdata),
    .m2_wstrb (m2_wstrb),
    .m2_wlast (m2_wlast),
    .m2_wvalid (m2_wvalid),
    .m2_wready (m2_wready),
    .m2_bresp (m2_bresp),
    .m2_bvalid (m2_bvalid),
    .m2_bready (m2_bready),
    .m2_araddr (m2_araddr),
    .m2_arlen (m2_arlen),
    .m2_arsize (m2_arsize),
    .m2_arburst (m2_arburst),
    .m2_arvalid (m2_arvalid),
    .m2_arready (m2_arready),
    .m2_rdata (m2_rdata),
    .m2_rresp (m2_rresp),
    .m2_rlast (m2_rlast),
    .m2_rvalid (m2_rvalid),
    .m2_rready (m2_rready));

  axi_bram_32k qpsk_snapshot_bram (
    .aclk (clk_125mhz),
    .aresetn (sys_resetn),
    .awaddr (m0_awaddr),
    .awvalid (m0_awvalid),
    .awready (m0_awready),
    .wdata (m0_wdata),
    .wstrb (m0_wstrb),
    .wvalid (m0_wvalid),
    .wready (m0_wready),
    .bresp (m0_bresp),
    .bvalid (m0_bvalid),
    .bready (m0_bready),
    .araddr (m0_araddr),
    .arvalid (m0_arvalid),
    .arready (m0_arready),
    .rdata (m0_rdata),
    .rresp (m0_rresp),
    .rvalid (m0_rvalid),
    .rready (m0_rready));

  // AD9361 core (axau15/mpf300 parameters; the lvds_if resolves to
  // library/axi_ad9361/efinix/axi_ad9361_lvds_if.v via the file list)

  axi_ad9361 #(
    .ID (0),
    .CMOS_OR_LVDS_N (0),
    .TDD_DISABLE (1),
    .DAC_DDS_TYPE (1),
    .DAC_DDS_CORDIC_DW (14),
    .ADC_INIT_DELAY (11)
  ) axi_ad9361_0 (
    // efinix lvds_if boundary (see the port-repurposing note there):
    // rx_clk_in_p carries l_clk, delay_clk carries the PLL lock
    .rx_clk_in_p (l_clk),
    .rx_clk_in_n (1'b0),
    .rx_frame_in_p (rx_frame[1]),
    .rx_frame_in_n (rx_frame[0]),
    .rx_data_in_p ({rx_data_5[1], rx_data_4[1], rx_data_3[1],
                    rx_data_2[1], rx_data_1[1], rx_data_0[1]}),
    .rx_data_in_n ({rx_data_5[0], rx_data_4[0], rx_data_3[0],
                    rx_data_2[0], rx_data_1[0], rx_data_0[0]}),
    .rx_clk_in (1'b0),
    .rx_frame_in (1'b0),
    .rx_data_in (12'd0),
    .tx_clk_out_p (),                 // FB_CLK is a periphery CLKOUT lane
    .tx_clk_out_n (),
    .tx_frame_out_p (tx_frame[1]),
    .tx_frame_out_n (tx_frame[0]),
    .tx_data_out_p ({tx_data_5[1], tx_data_4[1], tx_data_3[1],
                     tx_data_2[1], tx_data_1[1], tx_data_0[1]}),
    .tx_data_out_n ({tx_data_5[0], tx_data_4[0], tx_data_3[0],
                     tx_data_2[0], tx_data_1[0], tx_data_0[0]}),
    .tx_clk_out (),
    .tx_frame_out (),
    .tx_data_out (),
    .enable (enable),
    .txnrx (txnrx),
    .dac_sync_in (dac_sync_s),
    .dac_sync_out (dac_sync_s),
    .tdd_sync (1'b0),
    .tdd_sync_cntr (),
    .gps_pps (1'b0),
    .gps_pps_irq (),
    .delay_clk (lvds_pll_locked),
    .l_clk (l_clk_s),
    .clk (l_clk_s),
    .rst (),
    .adc_enable_i0 (adc_enable_i0),
    .adc_valid_i0 (adc_valid_i0),
    .adc_data_i0 (adc_data_i0),
    .adc_enable_q0 (adc_enable_q0),
    .adc_valid_q0 (adc_valid_q0),
    .adc_data_q0 (adc_data_q0),
    .adc_enable_i1 (adc_enable_i1),
    .adc_valid_i1 (adc_valid_i1),
    .adc_data_i1 (adc_data_i1),
    .adc_enable_q1 (adc_enable_q1),
    .adc_valid_q1 (adc_valid_q1),
    .adc_data_q1 (adc_data_q1),
    .adc_dovf (1'b0),
    .adc_r1_mode (),
    .dac_enable_i0 (dac_enable_i0),
    .dac_valid_i0 (dac_valid_i0),
    .dac_data_i0 (dac_data_i0),
    .dac_enable_q0 (dac_enable_q0),
    .dac_valid_q0 (dac_valid_q0),
    .dac_data_q0 (dac_data_q0),
    .dac_enable_i1 (dac_enable_i1),
    .dac_valid_i1 (dac_valid_i1),
    .dac_data_i1 (dac_data_i1),
    .dac_enable_q1 (dac_enable_q1),
    .dac_valid_q1 (dac_valid_q1),
    .dac_data_q1 (dac_data_q1),
    .dac_dunf (dac_dunf),
    .dac_r1_mode (),
    .s_axi_aclk (clk_125mhz),
    .s_axi_aresetn (aresetn_gated),
    .s_axi_awvalid (m1_awvalid),
    .s_axi_awaddr (m1_awaddr),
    .s_axi_awprot (m1_awprot),
    .s_axi_awready (m1_awready),
    .s_axi_wvalid (m1_wvalid),
    .s_axi_wdata (m1_wdata),
    .s_axi_wstrb (m1_wstrb),
    .s_axi_wready (m1_wready),
    .s_axi_bvalid (m1_bvalid),
    .s_axi_bresp (m1_bresp),
    .s_axi_bready (m1_bready),
    .s_axi_arvalid (m1_arvalid),
    .s_axi_araddr (m1_araddr),
    .s_axi_arprot (m1_arprot),
    .s_axi_arready (m1_arready),
    .s_axi_rvalid (m1_rvalid),
    .s_axi_rdata (m1_rdata),
    .s_axi_rresp (m1_rresp),
    .s_axi_rready (m1_rready),
    .up_enable (up_enable_s),
    .up_txnrx (up_txnrx_s),
    .up_dac_gpio_in (32'd0),
    .up_dac_gpio_out (),
    .up_adc_gpio_in (32'd0),
    .up_adc_gpio_out ());

  // SmartHLS adapters + DAC holding registers (l_clk domain)

  axi_ad9361_adapter_top axi_ad9361_adapter_0 (
    .clk (l_clk_s),
    .reset (lclk_reset),
    .start (1'b1),
    .ready (),
    .finish (),
    .adc_data_i0 (adc_data_i0),
    .adc_data_q0 (adc_data_q0),
    .adc_data_i1 (adc_data_i1),
    .adc_data_q1 (adc_data_q1),
    .adc_valid_i0 (adc_valid_i0),
    .adc_valid_q0 (adc_valid_q0),
    .adc_valid_i1 (adc_valid_i1),
    .adc_valid_q1 (adc_valid_q1),
    .adc_enable_i0 (adc_enable_i0),
    .adc_enable_q0 (adc_enable_q0),
    .adc_enable_i1 (adc_enable_i1),
    .adc_enable_q1 (adc_enable_q1),
    .dac_valid_i0 (dac_valid_i0),
    .dac_valid_q0 (dac_valid_q0),
    .dac_valid_i1 (dac_valid_i1),
    .dac_valid_q1 (dac_valid_q1),
    .dac_enable_i0 (dac_enable_i0),
    .dac_enable_q0 (dac_enable_q0),
    .dac_enable_i1 (dac_enable_i1),
    .dac_enable_q1 (dac_enable_q1),
    .adc_dovf (1'b0),
    .tx_stream_data (tx_lclk_data),
    .tx_stream_ready (tx_lclk_ready),
    .tx_stream_valid (tx_lclk_valid),
    .tx_stream_keep (tx_lclk_keep),
    .tx_stream_strb (tx_lclk_strb),
    .tx_stream_last (tx_lclk_last),
    .dac_data_i0_write_en (dac_data_i0_write_en),
    .dac_data_i0_write_data (dac_data_i0_write_data),
    .dac_data_q0_write_en (dac_data_q0_write_en),
    .dac_data_q0_write_data (dac_data_q0_write_data),
    .dac_data_i1_write_en (dac_data_i1_write_en),
    .dac_data_i1_write_data (dac_data_i1_write_data),
    .dac_data_q1_write_en (dac_data_q1_write_en),
    .dac_data_q1_write_data (dac_data_q1_write_data),
    .dac_dunf_write_en (dac_dunf_write_en),
    .dac_dunf_write_data (dac_dunf_write_data),
    .rx_stream_data (rx_lclk_data),
    .rx_stream_ready (rx_lclk_ready),
    .rx_stream_valid (rx_lclk_valid),
    .rx_stream_keep (rx_lclk_keep),
    .rx_stream_strb (rx_lclk_strb),
    .rx_stream_last (rx_lclk_last));

  dac_hold dac_hold_0 (
    .clk (l_clk_s),
    .dac_data_i0_write_en (dac_data_i0_write_en),
    .dac_data_i0_write_data (dac_data_i0_write_data),
    .dac_data_q0_write_en (dac_data_q0_write_en),
    .dac_data_q0_write_data (dac_data_q0_write_data),
    .dac_data_i1_write_en (dac_data_i1_write_en),
    .dac_data_i1_write_data (dac_data_i1_write_data),
    .dac_data_q1_write_en (dac_data_q1_write_en),
    .dac_data_q1_write_data (dac_data_q1_write_data),
    .dac_dunf_write_en (dac_dunf_write_en),
    .dac_dunf_write_data (dac_dunf_write_data),
    .dac_data_i0 (dac_data_i0),
    .dac_data_q0 (dac_data_q0),
    .dac_data_i1 (dac_data_i1),
    .dac_data_q1 (dac_data_q1),
    .dac_dunf (dac_dunf));

  // AXI-Lite to streaming adapter bridge (125 MHz domain)

  axi_lite_to_streaming_adapter_top axi_streaming_adapter_0 (
    .clk (clk_125mhz),
    .reset (sys_reset),
    .start (1'b1),
    .ready (),
    .finish (),
    .axi_aw_addr (m2_awaddr),
    .axi_aw_ready (m2_awready),
    .axi_aw_valid (m2_awvalid),
    .axi_aw_burst (m2_awburst),
    .axi_aw_size (m2_awsize),
    .axi_aw_len (m2_awlen),
    .axi_ar_addr (m2_araddr),
    .axi_ar_ready (m2_arready),
    .axi_ar_valid (m2_arvalid),
    .axi_ar_burst (m2_arburst),
    .axi_ar_size (m2_arsize),
    .axi_ar_len (m2_arlen),
    .axi_w_data (m2_wdata),
    .axi_w_ready (m2_wready),
    .axi_w_valid (m2_wvalid),
    .axi_w_strb (m2_wstrb),
    .axi_w_last (m2_wlast),
    .axi_b_resp (m2_bresp),
    .axi_b_resp_ready (m2_bready),
    .axi_b_resp_valid (m2_bvalid),
    .axi_r_data (m2_rdata),
    .axi_r_ready (m2_rready),
    .axi_r_valid (m2_rvalid),
    .axi_r_resp (m2_rresp),
    .axi_r_last (m2_rlast),
    .tx_stream_data (tx_up_data),
    .tx_stream_ready (tx_up_ready),
    .tx_stream_valid (tx_up_valid),
    .tx_stream_keep (tx_up_keep),
    .tx_stream_strb (tx_up_strb),
    .tx_stream_last (tx_up_last),
    .rx_stream_data (rx_up_data),
    .rx_stream_ready (rx_up_ready),
    .rx_stream_valid (rx_up_valid),
    .rx_stream_keep (rx_up_keep),
    .rx_stream_strb (rx_up_strb),
    .rx_stream_last (rx_up_last));

  // CDC FIFOs: TX 125 MHz -> l_clk, RX l_clk -> 125 MHz

  axis_async_fifo ad9361_cdc_tx_fifo (
    .s_axis_aclk (clk_125mhz),
    .s_axis_aresetn (aresetn_gated),
    .s_axis_tdata (tx_up_data),
    .s_axis_tkeep (tx_up_keep),
    .s_axis_tstrb (tx_up_strb),
    .s_axis_tlast (tx_up_last),
    .s_axis_tvalid (tx_up_valid),
    .s_axis_tready (tx_up_ready),
    .m_axis_aclk (l_clk_s),
    .m_axis_aresetn (lclk_resetn),
    .m_axis_tdata (tx_lclk_data),
    .m_axis_tkeep (tx_lclk_keep),
    .m_axis_tstrb (tx_lclk_strb),
    .m_axis_tlast (tx_lclk_last),
    .m_axis_tvalid (tx_lclk_valid),
    .m_axis_tready (tx_lclk_ready));

  axis_async_fifo ad9361_cdc_rx_fifo (
    .s_axis_aclk (l_clk_s),
    .s_axis_aresetn (lclk_resetn),
    .s_axis_tdata (rx_lclk_data),
    .s_axis_tkeep (rx_lclk_keep),
    .s_axis_tstrb (rx_lclk_strb),
    .s_axis_tlast (rx_lclk_last),
    .s_axis_tvalid (rx_lclk_valid),
    .s_axis_tready (rx_lclk_ready),
    .m_axis_aclk (clk_125mhz),
    .m_axis_aresetn (sys_resetn),
    .m_axis_tdata (rx_up_data),
    .m_axis_tkeep (rx_up_keep),
    .m_axis_tstrb (rx_up_strb),
    .m_axis_tlast (rx_up_last),
    .m_axis_tvalid (rx_up_valid),
    .m_axis_tready (rx_up_ready));

endmodule
