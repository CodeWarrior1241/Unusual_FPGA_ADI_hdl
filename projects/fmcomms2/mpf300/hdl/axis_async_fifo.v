// ***************************************************************************
// Asynchronous AXI4-Stream FIFO for the MPF300 FMCOMMS2 design: the CDC
// element between the 125 MHz AXI domain and the AD9361 l_clk domain,
// equivalent of the axau15 axis_data_fifo (FIFO_DEPTH=256, HAS_TLAST=1,
// IS_ACLK_ASYNC=1).
//
// Classic gray-code pointer design, 256 deep, payload = TDATA(32) +
// TKEEP(4) + TSTRB(4) + TLAST(1). Each side has its own active-low reset,
// asserted asynchronously and released synchronously to its clock; hold
// BOTH resets to flush (the pointers on each side reset independently, so
// releasing one side while the other is held keeps the FIFO empty, matching
// how the axau15 design flushes the TX FIFO during power-down).
// ***************************************************************************

`timescale 1ns/100ps

module axis_async_fifo #(

  parameter ADDR_W = 8              // 2**ADDR_W entries
) (

  // write side

  input           s_axis_aclk,
  input           s_axis_aresetn,
  input   [31:0]  s_axis_tdata,
  input   [ 3:0]  s_axis_tkeep,
  input   [ 3:0]  s_axis_tstrb,
  input           s_axis_tlast,
  input           s_axis_tvalid,
  output          s_axis_tready,

  // read side

  input           m_axis_aclk,
  input           m_axis_aresetn,
  output  [31:0]  m_axis_tdata,
  output  [ 3:0]  m_axis_tkeep,
  output  [ 3:0]  m_axis_tstrb,
  output          m_axis_tlast,
  output reg      m_axis_tvalid,
  input           m_axis_tready
);

  localparam DW = 32 + 4 + 4 + 1;

  reg  [DW-1:0]     mem [0:(2**ADDR_W)-1];

  // binary + gray pointers, one extra bit for full/empty

  reg  [ADDR_W:0]   wptr_bin = 'd0;
  reg  [ADDR_W:0]   wptr_gray = 'd0;
  reg  [ADDR_W:0]   rptr_bin = 'd0;
  reg  [ADDR_W:0]   rptr_gray = 'd0;

  reg  [ADDR_W:0]   rptr_gray_w_m1 = 'd0;
  reg  [ADDR_W:0]   rptr_gray_w = 'd0;
  reg  [ADDR_W:0]   wptr_gray_r_m1 = 'd0;
  reg  [ADDR_W:0]   wptr_gray_r = 'd0;

  reg  [DW-1:0]     rd_reg = 'd0;

  wire [ADDR_W:0]   wptr_bin_next = wptr_bin + (s_axis_tvalid & s_axis_tready);
  wire [ADDR_W:0]   wptr_gray_next = (wptr_bin_next >> 1) ^ wptr_bin_next;

  wire              full = (wptr_gray == {~rptr_gray_w[ADDR_W:ADDR_W-1],
                                          rptr_gray_w[ADDR_W-2:0]});

  assign s_axis_tready = ~full;

  // write side

  always @(posedge s_axis_aclk or negedge s_axis_aresetn) begin
    if (!s_axis_aresetn) begin
      wptr_bin  <= 'd0;
      wptr_gray <= 'd0;
      rptr_gray_w_m1 <= 'd0;
      rptr_gray_w    <= 'd0;
    end else begin
      if (s_axis_tvalid && s_axis_tready)
        mem[wptr_bin[ADDR_W-1:0]] <= {s_axis_tdata, s_axis_tkeep,
                                      s_axis_tstrb, s_axis_tlast};
      wptr_bin  <= wptr_bin_next;
      wptr_gray <= wptr_gray_next;
      rptr_gray_w_m1 <= rptr_gray;
      rptr_gray_w    <= rptr_gray_w_m1;
    end
  end

  // read side: registered output stage (rd_reg valid = m_axis_tvalid)

  wire empty = (rptr_gray == wptr_gray_r);
  wire rd_en = ~empty & (~m_axis_tvalid | m_axis_tready);

  wire [ADDR_W:0] rptr_bin_next = rptr_bin + rd_en;
  wire [ADDR_W:0] rptr_gray_next = (rptr_bin_next >> 1) ^ rptr_bin_next;

  always @(posedge m_axis_aclk or negedge m_axis_aresetn) begin
    if (!m_axis_aresetn) begin
      rptr_bin  <= 'd0;
      rptr_gray <= 'd0;
      wptr_gray_r_m1 <= 'd0;
      wptr_gray_r    <= 'd0;
      m_axis_tvalid  <= 1'b0;
      rd_reg <= 'd0;
    end else begin
      wptr_gray_r_m1 <= wptr_gray;
      wptr_gray_r    <= wptr_gray_r_m1;

      if (rd_en) begin
        rd_reg <= mem[rptr_bin[ADDR_W-1:0]];
        m_axis_tvalid <= 1'b1;
      end else if (m_axis_tready) begin
        m_axis_tvalid <= 1'b0;
      end

      rptr_bin  <= rptr_bin_next;
      rptr_gray <= rptr_gray_next;
    end
  end

  assign {m_axis_tdata, m_axis_tkeep, m_axis_tstrb, m_axis_tlast} = rd_reg;

endmodule
