// ***************************************************************************
// Asynchronous AXI4-Stream FIFO for the MPF300 FMCOMMS2 design: the CDC
// element between the 125 MHz AXI domain and the AD9361 l_clk domain,
// equivalent of the axau15 axis_data_fifo (HAS_TLAST=1, IS_ACLK_ASYNC=1).
//
// The FIFO engine is open-logic olo_base_fifo_async (deps/open-logic,
// VHDL): gray-code pointer dual-clock FIFO whose storage is an inferred
// dual-port RAM. With Depth 512 x 41 bits and RamStyle_g "block" it maps
// into PolarFire LSRAM (RAM1K20, 512x40 aspect) instead of fabric
// registers — depth 512 is the free depth of one LSRAM block, so nothing
// shallower saves anything. Both sides speak native valid/ready, which is
// protocol-identical to the AXIS handshake; this wrapper only packs the
// payload word.
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
// Reset: olo_base_fifo_async distributes reset across both domains
// internally (olo_base_cc_reset), so asserting EITHER side's reset
// flushes the whole FIFO — the axau15-style TX flush during power-down
// needs only the l_clk-side reset held (the PULP cdc_fifo_gray this
// replaces required both).
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

  // VHDL entity (deps/open-logic/src/base/vhdl/olo_base_fifo_async.vhd) in
  // synthesis; the Verilator datapath sim binds the behavioral SV model in
  // deps/neorv32/setups/neorv32_sw_ad9361_datapath_sim/verilator_sim_microchip.
  // Unused status/level outputs are left open.
  olo_base_fifo_async #(
    .Width_g       (DW),
    .Depth_g       (1 << ADDR_W),
    .RamStyle_g    ("block"),        // pin storage to LSRAM (never registers)
    .RamBehavior_g ("RBW"),
    .SyncStages_g  (2)
  ) i_fifo (
    .In_Clk   (s_axis_aclk),
    .In_Rst   (~s_axis_aresetn),
    .In_Data  (src_data_s),
    .In_Valid (s_axis_tvalid),
    .In_Ready (s_axis_tready),
    .Out_Clk  (m_axis_aclk),
    .Out_Rst  (~m_axis_aresetn),
    .Out_Data (dst_data_s),
    .Out_Valid (m_axis_tvalid),
    .Out_Ready (m_axis_tready)
  );

endmodule
