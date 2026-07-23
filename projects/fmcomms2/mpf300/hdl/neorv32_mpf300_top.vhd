-- ***************************************************************************
-- NEORV32 configuration wrapper for the MPF300 FMCOMMS2 design.
--
-- Libero HDL+ cores cannot expose VHDL boolean generics as configurable
-- parameters, so the axau15 NEORV32 configuration (Vivado CONFIG.* list in
-- projects/fmcomms2/axau15/build_all.tcl) is fixed here in a generic map
-- instead: RV32IMC + Zicntr, fast mul/shift, 128 KB IMEM (ad9361_no-os
-- image), 32 KB DMEM, UART0 with 32-deep FIFOs, 8-in/16-out GPIO, SPI,
-- CLINT, XBUS enabled. The only intentional difference from axau15 is
-- CLOCK_FREQUENCY = 125 MHz (this design's fabric clock; axau15 ran
-- 150 MHz) so the software's UART baud and delays stay correct without
-- modification.
--
-- Unused peripheral inputs of neorv32_vivado_ip are left at their entity
-- defaults; only the interfaces this design uses are brought to ports.
-- ***************************************************************************

library ieee;
use ieee.std_logic_1164.all;

entity neorv32_mpf300_top is
  port (
    clk            : in  std_logic;
    resetn         : in  std_logic;

    -- AXI4 master (XBUS bridge)
    m_axi_awaddr   : out std_logic_vector(31 downto 0);
    m_axi_awlen    : out std_logic_vector(7 downto 0);
    m_axi_awsize   : out std_logic_vector(2 downto 0);
    m_axi_awburst  : out std_logic_vector(1 downto 0);
    m_axi_awprot   : out std_logic_vector(2 downto 0);
    m_axi_awvalid  : out std_logic;
    m_axi_awready  : in  std_logic;
    m_axi_wdata    : out std_logic_vector(31 downto 0);
    m_axi_wstrb    : out std_logic_vector(3 downto 0);
    m_axi_wlast    : out std_logic;
    m_axi_wvalid   : out std_logic;
    m_axi_wready   : in  std_logic;
    m_axi_bresp    : in  std_logic_vector(1 downto 0);
    m_axi_bvalid   : in  std_logic;
    m_axi_bready   : out std_logic;
    m_axi_araddr   : out std_logic_vector(31 downto 0);
    m_axi_arlen    : out std_logic_vector(7 downto 0);
    m_axi_arsize   : out std_logic_vector(2 downto 0);
    m_axi_arburst  : out std_logic_vector(1 downto 0);
    m_axi_arprot   : out std_logic_vector(2 downto 0);
    m_axi_arvalid  : out std_logic;
    m_axi_arready  : in  std_logic;
    m_axi_rdata    : in  std_logic_vector(31 downto 0);
    m_axi_rresp    : in  std_logic_vector(1 downto 0);
    m_axi_rlast    : in  std_logic;
    m_axi_rvalid   : in  std_logic;
    m_axi_rready   : out std_logic;

    -- GPIO
    gpio_o         : out std_logic_vector(15 downto 0);
    gpio_i         : in  std_logic_vector(7 downto 0);

    -- UART0 console
    uart0_txd_o    : out std_logic;
    uart0_rxd_i    : in  std_logic;

    -- SPI (AD9361 control)
    spi_clk_o      : out std_logic;
    spi_dat_o      : out std_logic;
    spi_dat_i      : in  std_logic;
    spi_csn_o      : out std_logic_vector(7 downto 0)
  );
end entity neorv32_mpf300_top;

architecture rtl of neorv32_mpf300_top is
begin

  neorv32_inst : entity work.neorv32_vivado_ip
    generic map (
      CLOCK_FREQUENCY   => 125_000_000,
      BOOT_MODE_SELECT  => 2,
      IMEM_EN           => true,
      IMEM_SIZE         => 131072,
      DMEM_EN           => true,
      DMEM_SIZE         => 32768,
      RISCV_ISA_C       => true,
      RISCV_ISA_M       => true,
      RISCV_ISA_Zicntr  => true,
      CPU_FAST_MUL_EN   => true,
      CPU_FAST_MUL_REG  => true,  -- pipeline the DSP multiplier: closes 125 MHz on PolarFire (see README)
      CPU_FAST_SHIFT_EN => true,
      IO_UART0_EN       => true,
      IO_UART0_RX_FIFO  => 32,
      IO_UART0_TX_FIFO  => 32,
      IO_GPIO_EN        => true,
      IO_GPIO_IN_NUM    => 8,
      IO_GPIO_OUT_NUM   => 16,
      IO_SPI_EN         => true,
      IO_SPI_FIFO       => 4,
      XBUS_EN           => true,
      -- 32768, not 255: the SmartHLS streaming adapter serves its single
      -- pipeline's TX burst ahead of AXI beats, so a status READ issued
      -- during SEND_AND_RECEIVE can legitimately stall for the burst
      -- duration (~10 us at 125 MHz = ~1250 cycles). 255 turns that into
      -- an XBUS load-access fault.
      XBUS_TIMEOUT      => 32768,
      IO_CLINT_EN       => true
    )
    port map (
      clk           => clk,
      resetn        => resetn,
      m_axi_awaddr  => m_axi_awaddr,
      m_axi_awlen   => m_axi_awlen,
      m_axi_awsize  => m_axi_awsize,
      m_axi_awburst => m_axi_awburst,
      m_axi_awprot  => m_axi_awprot,
      m_axi_awvalid => m_axi_awvalid,
      m_axi_awready => m_axi_awready,
      m_axi_wdata   => m_axi_wdata,
      m_axi_wstrb   => m_axi_wstrb,
      m_axi_wlast   => m_axi_wlast,
      m_axi_wvalid  => m_axi_wvalid,
      m_axi_wready  => m_axi_wready,
      m_axi_bresp   => m_axi_bresp,
      m_axi_bvalid  => m_axi_bvalid,
      m_axi_bready  => m_axi_bready,
      m_axi_araddr  => m_axi_araddr,
      m_axi_arlen   => m_axi_arlen,
      m_axi_arsize  => m_axi_arsize,
      m_axi_arburst => m_axi_arburst,
      m_axi_arprot  => m_axi_arprot,
      m_axi_arvalid => m_axi_arvalid,
      m_axi_arready => m_axi_arready,
      m_axi_rdata   => m_axi_rdata,
      m_axi_rresp   => m_axi_rresp,
      m_axi_rlast   => m_axi_rlast,
      m_axi_rvalid  => m_axi_rvalid,
      m_axi_rready  => m_axi_rready,
      gpio_o        => gpio_o,
      gpio_i        => gpio_i,
      uart0_txd_o   => uart0_txd_o,
      uart0_rxd_i   => uart0_rxd_i,
      spi_clk_o     => spi_clk_o,
      spi_dat_o     => spi_dat_o,
      spi_dat_i     => spi_dat_i,
      spi_csn_o     => spi_csn_o
    );

end architecture rtl;
