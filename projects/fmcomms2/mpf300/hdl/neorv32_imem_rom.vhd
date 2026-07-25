-- ================================================================================ --
-- NEORV32 SoC - Instruction Memory (IMEM) - ROM Wrapper, Microchip PolarFire      --
-- -------------------------------------------------------------------------------- --
-- mpf300-only override of rtl/core/neorv32_imem_rom.vhd (staged over the mainline --
-- file by build_all.tcl; the entity and read behavior are identical).             --
--                                                                                 --
-- The mainline wrapper reads the package-constant image array directly, which    --
-- Synplify's automatic-compile-point mapper re-elaborates as a LUT mux tree      --
-- (~57k 4LUTs, -17 ns) inside compile-point context jobs and then retimes for    --
-- 30+ minutes, even though the winning top-level mapping extracts LSRAM. This    --
-- wrapper declares the memory as a zero-padded, full-window SIGNAL pinned with   --
-- syn_romstyle = "lsram", so every mapping context extracts RAM1K20 blocks up    --
-- front and there is never a logic-ROM netlist to grind on.                      --
--                                                                                 --
-- Contents are loaded at power-up by the design-initialization flow              --
-- (GENERATE_INIT_DATA / PF_INIT_MONITOR), same as the mainline inference path.   --
-- -------------------------------------------------------------------------------- --
-- The NEORV32 RISC-V Processor - https://github.com/stnolting/neorv32              --
-- Copyright (c) NEORV32 contributors.                                              --
-- Copyright (c) 2020 - 2026 Stephan Nolting. All rights reserved.                  --
-- Licensed under the BSD-3-Clause license, see LICENSE for details.                --
-- SPDX-License-Identifier: BSD-3-Clause                                            --
-- ================================================================================ --

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library neorv32;
use neorv32.neorv32_package.all;
use neorv32.neorv32_imem_image.all;

entity neorv32_imem_rom is
  generic (
    AWIDTH : natural; -- address width (byte address)
    OUTREG : natural  -- add output register stage when 1
  );
  port (
    clk_i  : in  std_ulogic;                     -- clock, rising-edge
    en_i   : in  std_ulogic;                     -- access-enable
    addr_i : in  std_ulogic_vector(31 downto 0); -- full byte address
    data_o : out std_ulogic_vector(31 downto 0)  -- read data, sync
  );
end neorv32_imem_rom;

architecture neorv32_imem_rom_mpf300 of neorv32_imem_rom is

  constant depth_c : natural := 2**(AWIDTH-2); -- full IMEM window in 32-bit words

  type mem_t is array (0 to depth_c-1) of std_ulogic_vector(31 downto 0);

  -- copy the application image into a full-window memory, zero-padding the tail
  -- (reads beyond the image return zero instead of aliasing)
  function init_f return mem_t is
    variable v : mem_t := (others => (others => '0'));
  begin
    for i in image_data_c'range loop
      exit when (i >= depth_c);
      v(i) := image_data_c(i);
    end loop;
    return v;
  end function;

  -- signal (not constant) declaration: RAM-with-initial-content pattern
  signal rom : mem_t := init_f;

  attribute syn_romstyle : string;
  attribute syn_romstyle of rom : signal is "lsram";

  signal rdata : std_ulogic_vector(31 downto 0);

begin

  -- notifier --
  assert false report
    "[NEORV32] Using mpf300 LSRAM IMEM ROM component (" &
    natural'image(4*depth_c) & " bytes)." severity note;

  -- size check --
  assert (image_size_c <= 2**AWIDTH) report
    "[NEORV32] IMEM image (" & natural'image(image_size_c) & " bytes) " &
    "overflows IMEM size (" & natural'image(2**AWIDTH) & " bytes)!" severity error;

  -- ROM --
  rom_access: process(clk_i)
  begin
    if rising_edge(clk_i) then
      if (en_i = '1') then
        rdata <= rom(to_integer(unsigned(addr_i(AWIDTH-1 downto 2))));
      end if;
    end if;
  end process rom_access;

  -- output register stage --
  rom_output_register_enabled:
  if (OUTREG = 1) generate
    rom_outreg: process(clk_i)
    begin
      if rising_edge(clk_i) then
        data_o <= rdata;
      end if;
    end process rom_outreg;
  end generate;

  -- no output register stage --
  rom_output_register_disabled:
  if (OUTREG = 0) generate
    data_o <= rdata;
  end generate;

end neorv32_imem_rom_mpf300;
