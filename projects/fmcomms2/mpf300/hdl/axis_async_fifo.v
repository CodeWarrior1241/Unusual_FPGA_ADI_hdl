// ***************************************************************************
// Asynchronous AXI4-Stream FIFO for the MPF300 FMCOMMS2 design: the CDC
// element between the 125 MHz AXI domain and the AD9361 l_clk domain,
// equivalent of the axau15 axis_data_fifo (HAS_TLAST=1, IS_ACLK_ASYNC=1).
//
// The FIFO engine is Bedrock-RTL br_cdc_fifo_ctrl_1r1w (deps/bedrock-rtl,
// SystemVerilog): gray-code pointer dual-clock FIFO controller driving the
// external 1R1W RAM below. With Depth 512 x 41 bits the storage maps into
// PolarFire LSRAM (RAM1K20, 512x40 aspect) instead of fabric registers —
// depth 512 is the free depth of one LSRAM block, so nothing shallower
// saves anything. Both sides speak native ready/valid, protocol-identical
// to the AXIS handshake; this wrapper packs the payload word and supplies
// the RAM. (Replaces open-logic olo_base_fifo_async, VHDL — see
// doc/MPF300-Splash-Kit/bedrock_migration_design.md.)
//
// NOTE — BRAM strip candidate: the FIFO word is 41 bits, TDATA(32) +
// TKEEP(4) + TSTRB(4) + TLAST(1), which is one bit over the 40-bit LSRAM
// aspect and therefore costs a SECOND RAM1K20 per FIFO. TKEEP and TSTRB
// are constant 4'hF everywhere in this system (the adapters only move
// full 32-bit words); they are carried through the FIFO purely for
// interface compatibility with the axau15 design. To reclaim one LSRAM
// per FIFO later: narrow the FIFO word to 33 bits (TDATA + TLAST) and
// regenerate m_axis_tkeep/m_axis_tstrb as constant 4'hF on the read side.
//
// Reset: Bedrock's CDC FIFO requires the push and pop resets to overlap
// (br_cdc_fifo_reset_overlap_checks asserts this in simulation), where
// olo_base_fifo_async distributed either side's reset internally. This
// wrapper preserves the olo behavior: each side's LOCAL reset is carried
// into the other domain with br_cdc_rst_sync (async assert, sync release)
// and OR-ed in — asserting EITHER side flushes the whole FIFO, so the
// axau15-style TX flush during power-down still needs only one side held.
// Only the local resets are cross-coupled (cross-coupling the merged
// resets would latch up through the synchronizers). Overlap is guaranteed
// because every reset source in this design holds for >= 8 cycles
// (mpf300_reset_gen) or the whole power-down window.
// ***************************************************************************

`timescale 1ns/100ps

module axis_async_fifo #(

  parameter ADDR_W = 9              // 2**ADDR_W entries; 9 -> 512, one full
                                    // LSRAM (RAM1K20) at 40 bits wide
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
  output          m_axis_tvalid,
  input           m_axis_tready
);

  localparam DW = 32 + 4 + 4 + 1;

  wire [DW-1:0] src_data_s;
  wire [DW-1:0] dst_data_s;

  assign src_data_s = {s_axis_tdata, s_axis_tkeep, s_axis_tstrb, s_axis_tlast};
  assign {m_axis_tdata, m_axis_tkeep, m_axis_tstrb, m_axis_tlast} = dst_data_s;

  // -------------------------------------------------------------------------
  // Reset cross-coupling (either side resets both domains, as olo did)
  // -------------------------------------------------------------------------

  wire push_rst_local = ~s_axis_aresetn;
  wire pop_rst_local  = ~m_axis_aresetn;
  wire push_rst_from_pop;
  wire pop_rst_from_push;

  br_cdc_rst_sync #(
    .NumStages (2)
  ) i_rst_push_to_pop (
    .clk  (m_axis_aclk),
    .arst (push_rst_local),
    .srst (pop_rst_from_push)
  );

  br_cdc_rst_sync #(
    .NumStages (2)
  ) i_rst_pop_to_push (
    .clk  (s_axis_aclk),
    .arst (pop_rst_local),
    .srst (push_rst_from_pop)
  );

  wire push_rst = push_rst_local | push_rst_from_pop;
  wire pop_rst  = pop_rst_local  | pop_rst_from_push;

  // -------------------------------------------------------------------------
  // FIFO controller + LSRAM storage
  // -------------------------------------------------------------------------

  wire              ram_wr_valid;
  wire [ADDR_W-1:0] ram_wr_addr;
  wire [DW-1:0]     ram_wr_data;
  wire              ram_rd_addr_valid;
  wire [ADDR_W-1:0] ram_rd_addr;
  wire              ram_rd_data_valid;
  wire [DW-1:0]     ram_rd_data;

  br_cdc_fifo_ctrl_1r1w #(
    .Depth              (1 << ADDR_W),
    .Width              (DW),
    .RegisterPopOutputs (1),         // pop data from a register (timing)
    .RamWriteLatency    (1),
    .RamReadLatency     (1),
    .NumSyncStages      (2)          // matches olo SyncStages_g=2
  ) i_fifo_ctrl (
    .push_clk              (s_axis_aclk),
    .push_rst              (push_rst),
    .push_ready            (s_axis_tready),
    .push_valid            (s_axis_tvalid),
    .push_data             (src_data_s),
    .push_full             (),
    .push_slots            (),
    .push_ram_wr_valid     (ram_wr_valid),
    .push_ram_wr_addr      (ram_wr_addr),
    .push_ram_wr_data      (ram_wr_data),
    .pop_clk               (m_axis_aclk),
    .pop_rst               (pop_rst),
    .pop_ready             (m_axis_tready),
    .pop_valid             (m_axis_tvalid),
    .pop_data              (dst_data_s),
    .pop_empty             (),
    .pop_items             (),
    .pop_ram_rd_addr_valid (ram_rd_addr_valid),
    .pop_ram_rd_addr       (ram_rd_addr),
    .pop_ram_rd_data_valid (ram_rd_data_valid),
    .pop_ram_rd_data       (ram_rd_data)
  );

  axis_async_fifo_ram #(
    .ADDR_W (ADDR_W),
    .DW     (DW)
  ) i_ram (
    .wclk   (s_axis_aclk),
    .we     (ram_wr_valid),
    .waddr  (ram_wr_addr),
    .wdata  (ram_wr_data),
    .rclk   (m_axis_aclk),
    .re     (ram_rd_addr_valid),
    .raddr  (ram_rd_addr),
    .rvalid (ram_rd_data_valid),
    .rdata  (ram_rd_data)
  );

endmodule

// ***************************************************************************
// 1R1W dual-clock RAM for the FIFO above: inferred simple-dual-port with a
// registered read (RamReadLatency=1). syn_ramstyle="lsram" pins storage to
// PolarFire LSRAM (never registers) — the role olo_base_ram_sdp played.
// The FIFO controller never reads an entry before its write is counted
// (RamWriteLatency), so no read/write collision handling is needed.
// ***************************************************************************

module axis_async_fifo_ram #(

  parameter ADDR_W = 9,
  parameter DW     = 41
) (

  input               wclk,
  input               we,
  input  [ADDR_W-1:0] waddr,
  input  [DW-1:0]     wdata,

  input               rclk,
  input               re,
  input  [ADDR_W-1:0] raddr,
  output reg          rvalid,
  output reg [DW-1:0] rdata
);

  (* syn_ramstyle = "lsram" *)
  reg [DW-1:0] mem [0:(1 << ADDR_W)-1];

  always @(posedge wclk) begin
    if (we)
      mem[waddr] <= wdata;
  end

  initial rvalid = 1'b0;

  always @(posedge rclk) begin
    if (re)
      rdata <= mem[raddr];
    rvalid <= re;
  end

endmodule
