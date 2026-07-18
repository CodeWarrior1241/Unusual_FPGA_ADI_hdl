// =============================================================================
// FMCOMMS2/AU15P Firmware Debug Testbench — Minimal SPI Responder
// =============================================================================
// Instantiates the full Top_wrapper block design with:
//   - 300 MHz differential clock + active-low reset
//   - AD9361 SPI slave model on SPI pins
//   - 125 MHz free-running clock on rx_clk_in (prevents axi_ad9361 l_clk stall)
//   - UART TX capture to transcript + file
//   - AXI bus monitor with fault detection
//   - SPI transaction logging
//   - GPIO monitoring
// =============================================================================

`timescale 1ns / 1ps

module tb_top;

    // =========================================================================
    // Clock Generation
    // =========================================================================

    // 300 MHz system clock (3.333 ns period)
    reg sys_clk_p;
    initial sys_clk_p = 1'b0;
    always #1.667 sys_clk_p = ~sys_clk_p;
    wire sys_clk_n = ~sys_clk_p;

    // 125 MHz AD9361 data clock (8 ns period) — keeps axi_ad9361 l_clk alive
    reg rx_clk_p;
    initial rx_clk_p = 1'b0;
    always #4.0 rx_clk_p = ~rx_clk_p;
    wire rx_clk_n = ~rx_clk_p;

    // =========================================================================
    // Reset
    // =========================================================================

    reg system_resetn;
    // MMCM lock observed via hierarchical reference — gates any activity that
    // depends on a stable 100 MHz clock (UART RX sampler, STATUS monitor).
    wire pll_locked = dut.Top_i.ECS_Clock_300MHz.locked;

    initial begin
        system_resetn = 1'b0;
        #1_000_000;  // 1 ms reset hold — Clock Wizard resetn low while input clock stabilises
        system_resetn = 1'b1;
        $display("[%0t] system_resetn released — waiting for MMCM lock...", $time);
        wait (pll_locked === 1'b1);
        $display("[%0t] MMCM locked — system ready", $time);
    end

    // =========================================================================
    // DUT — Top_wrapper
    // =========================================================================

    wire        spi_clk_w;
    wire [0:0]  spi_csn_0_w;
    wire        spi_mosi_w;
    wire        spi_miso_w;
    wire        sys_uart_tx;
    wire        enable_w;
    wire        txnrx_w;
    wire [3:0]  gpio_ctl_w;
    wire [0:0]  gpio_resetb_w;
    wire [0:0]  gpio_sync_w;
    wire [0:0]  gpio_en_agc_w;

    // TX outputs (unused, left unconnected)
    wire        tx_frame_out_p, tx_frame_out_n;
    wire [4:0]  tx_data_out_p, tx_data_out_n;
    wire        tx_clk_se_true, tx_clk_se_comp;
    wire [0:0]  tx_d0_se_true, tx_d0_se_comp;

    Top_wrapper dut (
        .ecs_clk_in_clk_p   (sys_clk_p),
        .ecs_clk_in_clk_n   (sys_clk_n),
        .system_resetn       (system_resetn),

        // SPI to AD9361 slave model
        .spi_clk             (spi_clk_w),
        .spi_csn_0           (spi_csn_0_w),
        .spi_mosi            (spi_mosi_w),
        .spi_miso            (spi_miso_w),

        // UART
        .sys_uart_tx         (sys_uart_tx),
        .sys_uart_rx         (1'b1),           // idle high

        // AD9361 LVDS RX — TX loopback per ADI's axi_ad9361_tb pattern
        // (rx_clk stays externally driven at 125 MHz so l_clk is alive even
        // if the chip-side TX is silent; tx_frame/tx_data feed RX inputs so
        // a working DAC produces valid LVDS frames into our own RX pins).
        // Lane 5 stays at 0 -- HD-bank lane has no LVDS receiver in this
        // design, so its single-ended path is held low (just like in the
        // original constant-tie config).
        .rx_clk_in_p         (rx_clk_p),
        .rx_clk_in_n         (rx_clk_n),
        .rx_frame_in_p       (tx_frame_out_p),
        .rx_frame_in_n       (tx_frame_out_n),
        .rx_data_in_p        (tx_data_out_p),
        .rx_data_in_n        (tx_data_out_n),
        .rx_data_5_se        (1'b0),
        .rx_data_5_se_unused (1'b0),

        // GPIO
        .gpio_status         (8'h00),
        .gpio_resetb         (gpio_resetb_w),
        .gpio_sync           (gpio_sync_w),
        .gpio_en_agc         (gpio_en_agc_w),
        .gpio_ctl            (gpio_ctl_w),
        .enable              (enable_w),
        .txnrx               (txnrx_w),

        // TX outputs (unused)
        .tx_frame_out_p      (tx_frame_out_p),
        .tx_frame_out_n      (tx_frame_out_n),
        .tx_data_out_p       (tx_data_out_p),
        .tx_data_out_n       (tx_data_out_n),
        .tx_clk_se_true      (tx_clk_se_true),
        .tx_clk_se_comp      (tx_clk_se_comp),
        .tx_d0_se_true       (tx_d0_se_true),
        .tx_d0_se_comp       (tx_d0_se_comp)
    );

    // =========================================================================
    // Debug Probes — sim-only, $display via hierarchical refs, no BD change
    // =========================================================================

    // Probe 1: CPU release-from-reset timestamp. mb_reset is active-high from
    // proc_sys_reset; goes low when the CPU is released. When dcm_locked is
    // properly wired, this should fire *after* the "MMCM locked" message.
    wire dbg_mb_reset   = dut.Top_i.CPU_Reset.mb_reset;
    wire dbg_cpu_resetn = dut.Top_i.NEORV32_RISC_V.resetn;
    initial begin
        @(negedge dbg_mb_reset);
        $display("[%0t] CPU mb_reset released (pll_locked=%b cpu_resetn=%b)",
                 $time, pll_locked, dbg_cpu_resetn);
    end

    // Probe 2: First UART TX edge — when does the firmware actually start
    // talking? Pre-lock traffic indicates the CPU ran on an unstable clock.
    reg dbg_first_uart_seen;
    initial dbg_first_uart_seen = 1'b0;
    always @(negedge sys_uart_tx) begin
        if (!dbg_first_uart_seen && system_resetn) begin
            dbg_first_uart_seen <= 1'b1;
            $display("[%0t] First UART TX negedge (pll_locked=%b mb_reset=%b)",
                     $time, pll_locked, dbg_mb_reset);
        end
    end

    // =========================================================================
    // AD9361 SPI Slave Model
    // =========================================================================

    ad9361_spi_slave spi_slave (
        .spi_clk  (spi_clk_w),
        .spi_csn  (spi_csn_0_w[0]),
        .spi_mosi (spi_mosi_w),
        .spi_miso (spi_miso_w)
    );

    // =========================================================================
    // UART RX Monitor (115200 baud, 8N1)
    // =========================================================================

    localparam BAUD_PERIOD = 8681;  // 1/115200 * 1e9 = 8680.6 ns

    integer uart_log;
    initial uart_log = $fopen("tb.uart0_rx.log", "w");

    reg [7:0] uart_rx_byte;
    reg [3:0] uart_rx_bit_count;
    reg       uart_active;

    initial begin
        uart_active = 1'b0;
        uart_rx_byte = 8'h00;
        uart_rx_bit_count = 4'd0;
    end

    // Match the validated reference TB (vivado_tb.v): non-blocking state updates
    // and an extra half-bit trailing delay so the sampler doesn't re-arm until
    // the stop bit is fully done. Without the trailing half-bit, an intra-char
    // negedge from near the end of the previous char can re-trigger this always
    // block before the real next start-bit arrives, producing misaligned samples
    // (manifests as dropped leading bytes and NULs in back-to-back bursts).
    always @(negedge sys_uart_tx) begin
        if (!uart_active && system_resetn && pll_locked) begin
            uart_active <= 1'b1;
            uart_rx_bit_count <= 4'd0;
            #(BAUD_PERIOD / 2 + BAUD_PERIOD);  // skip start bit, land mid-D0
            repeat (8) begin
                uart_rx_byte[uart_rx_bit_count] <= sys_uart_tx;
                uart_rx_bit_count <= uart_rx_bit_count + 4'd1;
                #BAUD_PERIOD;
            end
            #(BAUD_PERIOD / 2);  // ride out the stop bit before re-arming
            if (uart_rx_byte >= 8'h20 && uart_rx_byte <= 8'h7E)
                $write("%c", uart_rx_byte);
            else if (uart_rx_byte == 8'h0A)
                $write("\n");
            else if (uart_rx_byte == 8'h0D)
                ;  // ignore CR
            else
                $write("[0x%02h]", uart_rx_byte);
            $fwrite(uart_log, "%c", uart_rx_byte);
            $fflush(uart_log);
            uart_active <= 1'b0;
        end
    end

    // =========================================================================
    // AXI Bus Monitor — watches NEORV32 external bus (XBUS/AXI master)
    // =========================================================================
    // Detects:
    //   - AXI read/write error responses (SLVERR, DECERR)
    //   - Bus timeout (XBUS timeout fires before AXI completes)
    //   - Access to unmapped address ranges
    //   - The exact address and transaction type that causes the fault

    // Internal signals — use hierarchical references into the block design
    // These resolve during elaboration; if paths change, vopt will warn.

    wire        axi_clk = dut.Top_i.ECS_Clock_300MHz.clk_out1;

    // AXI write channel
    wire [31:0] axi_awaddr;
    wire        axi_awvalid;
    wire        axi_awready;
    wire [31:0] axi_wdata;
    wire        axi_wvalid;
    wire        axi_wready;
    wire [1:0]  axi_bresp;
    wire        axi_bvalid;
    wire        axi_bready;

    // AXI read channel
    wire [31:0] axi_araddr;
    wire        axi_arvalid;
    wire        axi_arready;
    wire [31:0] axi_rdata;
    wire [1:0]  axi_rresp;
    wire        axi_rvalid;
    wire        axi_rready;

    // Connect to NEORV32 AXI master port
    assign axi_awaddr  = dut.Top_i.NEORV32_RISC_V.m_axi_awaddr;
    assign axi_awvalid = dut.Top_i.NEORV32_RISC_V.m_axi_awvalid;
    assign axi_awready = dut.Top_i.NEORV32_RISC_V.m_axi_awready;
    assign axi_wdata   = dut.Top_i.NEORV32_RISC_V.m_axi_wdata;
    assign axi_wvalid  = dut.Top_i.NEORV32_RISC_V.m_axi_wvalid;
    assign axi_wready  = dut.Top_i.NEORV32_RISC_V.m_axi_wready;
    assign axi_bresp   = dut.Top_i.NEORV32_RISC_V.m_axi_bresp;
    assign axi_bvalid  = dut.Top_i.NEORV32_RISC_V.m_axi_bvalid;
    assign axi_bready  = dut.Top_i.NEORV32_RISC_V.m_axi_bready;

    assign axi_araddr  = dut.Top_i.NEORV32_RISC_V.m_axi_araddr;
    assign axi_arvalid = dut.Top_i.NEORV32_RISC_V.m_axi_arvalid;
    assign axi_arready = dut.Top_i.NEORV32_RISC_V.m_axi_arready;
    assign axi_rdata   = dut.Top_i.NEORV32_RISC_V.m_axi_rdata;
    assign axi_rresp   = dut.Top_i.NEORV32_RISC_V.m_axi_rresp;
    assign axi_rvalid  = dut.Top_i.NEORV32_RISC_V.m_axi_rvalid;
    assign axi_rready  = dut.Top_i.NEORV32_RISC_V.m_axi_rready;

    // Track last successful AXI addresses
    reg [31:0] last_rd_addr, last_wr_addr;
    reg [31:0] axi_rd_count, axi_wr_count;
    reg [31:0] axi_rd_err_count, axi_wr_err_count;
    initial begin
        last_rd_addr = 0; last_wr_addr = 0;
        axi_rd_count = 0; axi_wr_count = 0;
        axi_rd_err_count = 0; axi_wr_err_count = 0;
    end

    // Monitor AXI read address channel
    always @(posedge axi_clk) begin
        if (axi_arvalid && axi_arready) begin
            last_rd_addr <= axi_araddr;
            axi_rd_count <= axi_rd_count + 1;
        end
    end

    // Monitor AXI write address channel
    always @(posedge axi_clk) begin
        if (axi_awvalid && axi_awready) begin
            last_wr_addr <= axi_awaddr;
            axi_wr_count <= axi_wr_count + 1;
        end
    end

    // Detect AXI read error responses
    always @(posedge axi_clk) begin
        if (axi_rvalid && axi_rready && axi_rresp != 2'b00) begin
            axi_rd_err_count <= axi_rd_err_count + 1;
            $display("[%0t] AXI READ ERROR: addr=0x%08h resp=%b data=0x%08h (total_rd_errs=%0d)",
                     $time, last_rd_addr, axi_rresp, axi_rdata, axi_rd_err_count + 1);
            if (axi_rresp == 2'b11)
                $display("[%0t]   -> DECERR: address 0x%08h is not mapped in SmartConnect", $time, last_rd_addr);
            else if (axi_rresp == 2'b10)
                $display("[%0t]   -> SLVERR: slave at 0x%08h returned error", $time, last_rd_addr);
        end
    end

    // Detect AXI write error responses
    always @(posedge axi_clk) begin
        if (axi_bvalid && axi_bready && axi_bresp != 2'b00) begin
            axi_wr_err_count <= axi_wr_err_count + 1;
            $display("[%0t] AXI WRITE ERROR: addr=0x%08h resp=%b data=0x%08h (total_wr_errs=%0d)",
                     $time, last_wr_addr, axi_bresp, axi_wdata, axi_wr_err_count + 1);
            if (axi_bresp == 2'b11)
                $display("[%0t]   -> DECERR: address 0x%08h is not mapped in SmartConnect", $time, last_wr_addr);
            else if (axi_bresp == 2'b10)
                $display("[%0t]   -> SLVERR: slave at 0x%08h returned error", $time, last_wr_addr);
        end
    end

    // Log first few AXI transactions for debugging
    reg [31:0] axi_log_limit;
    initial axi_log_limit = 50;

    always @(posedge axi_clk) begin
        if (axi_arvalid && axi_arready && axi_rd_count < axi_log_limit) begin
            $display("[%0t] AXI RD  addr=0x%08h (#%0d)", $time, axi_araddr, axi_rd_count + 1);
        end
    end

    always @(posedge axi_clk) begin
        if (axi_awvalid && axi_awready && axi_wr_count < axi_log_limit) begin
            $display("[%0t] AXI WR  addr=0x%08h data=0x%08h (#%0d)", $time, axi_awaddr, axi_wdata, axi_wr_count + 1);
        end
    end

    // =========================================================================
    // SPI Transaction Counter and Logger
    // =========================================================================

    integer spi_txn_count;
    initial spi_txn_count = 0;

    always @(posedge spi_csn_0_w[0]) begin
        spi_txn_count = spi_txn_count + 1;
    end

    // =========================================================================
    // GPIO Monitor
    // =========================================================================

    reg [0:0] prev_gpio_resetb;
    reg       prev_enable, prev_txnrx;
    initial begin
        prev_gpio_resetb = 1'b0;
        prev_enable = 1'b0;
        prev_txnrx = 1'b0;
    end

    always @(posedge axi_clk) begin
        if (gpio_resetb_w !== prev_gpio_resetb) begin
            $display("[%0t] GPIO: gpio_resetb = %b", $time, gpio_resetb_w);
            prev_gpio_resetb <= gpio_resetb_w;
        end
        if (enable_w !== prev_enable) begin
            $display("[%0t] GPIO: enable = %b", $time, enable_w);
            prev_enable <= enable_w;
        end
        if (txnrx_w !== prev_txnrx) begin
            $display("[%0t] GPIO: txnrx = %b", $time, txnrx_w);
            prev_txnrx <= txnrx_w;
        end
    end

    // =========================================================================
    // Simulation Control
    // =========================================================================

    initial begin
        $display("==============================================");
        $display("  FMCOMMS2/AU15P Firmware Debug Testbench");
        $display("  Minimal SPI Responder");
        $display("==============================================");
    end

    // Watchdog — terminate if no SPI activity for 10ms after boot
    reg [63:0] last_spi_time;
    initial last_spi_time = 0;

    always @(negedge spi_csn_0_w[0]) begin
        last_spi_time = $time;
    end

    initial begin
        wait (pll_locked === 1'b1);  // don't start status/watchdog until clock is stable
        #1_000_000;  // allow proc_sys_reset to release mb_reset and CPU to boot
        forever begin
            #1_000_000;  // check every 1 ms
            if (last_spi_time > 0 && ($time - last_spi_time) > 10_000_000) begin
                $display("");
                $display("==============================================");
                $display("[%0t] WATCHDOG: No SPI activity for 10ms", $time);
                $display("  Firmware likely crashed or halted.");
                $display("  SPI transactions completed: %0d", spi_txn_count);
                $display("  AXI reads:  %0d (errors: %0d)", axi_rd_count, axi_rd_err_count);
                $display("  AXI writes: %0d (errors: %0d)", axi_wr_count, axi_wr_err_count);
                $display("  Last AXI read  addr: 0x%08h", last_rd_addr);
                $display("  Last AXI write addr: 0x%08h", last_wr_addr);
                $display("==============================================");
                #100;
                $stop;  // stop, don't exit — allows waveform inspection
            end
            // Periodic status every 5ms
            if (($time % 5_000_000) < 1_000_000 && $time > 2_000_000) begin
                $display("[%0t] STATUS: SPI=%0d AXI_RD=%0d AXI_WR=%0d AXI_ERR=%0d",
                         $time, spi_txn_count, axi_rd_count, axi_wr_count,
                         axi_rd_err_count + axi_wr_err_count);
            end
        end
    end

    // =========================================================================
    // LVDS data-path activity probes (TX-side only -- robust to BD renaming)
    //
    // Now that rx_*_in_p/n are loopbacks of tx_*_out_p/n, watching the TX
    // outputs is equivalent to watching what the FPGA is feeding to its own
    // RX inputs. No hierarchical refs into the BD-wrapped IPs needed.
    //
    // What we want to see if DAC reset is the only blocker:
    //   - tx_clk toggles continuously (FPGA TX clock alive)
    //   - tx_frame_out_p toggles (DAC produces the framing pattern)
    //   - tx_data_out_p[0] toggles (DAC produces data bits)
    //
    // What we'd see with the DAC stuck in reset:
    //   - tx_clk alive (clocking is independent of DAC reset)
    //   - tx_frame_out_p stuck (no frame strobe)
    //   - tx_data_out_p[0] stuck (no data)
    //
    // For deeper internals (adc_valid_i0 pulses, adapter rx_state, bridge
    // rx_sample_count) open the waveform in ModelSim/Questa and add the
    // BD-internal nets manually -- their post-elaboration paths are stable
    // within a Vivado run but not stable across config changes.
    // =========================================================================

    integer dbg_tx_clk_toggles;
    integer dbg_tx_frame_toggles;
    integer dbg_tx_data0_toggles;
    initial begin
        dbg_tx_clk_toggles   = 0;
        dbg_tx_frame_toggles = 0;
        dbg_tx_data0_toggles = 0;
    end

    always @(tx_clk_se_true)   dbg_tx_clk_toggles   = dbg_tx_clk_toggles   + 1;
    always @(tx_frame_out_p)   dbg_tx_frame_toggles = dbg_tx_frame_toggles + 1;
    always @(tx_data_out_p[0]) dbg_tx_data0_toggles = dbg_tx_data0_toggles + 1;

    // Periodic LVDS-activity report (uses its own forever loop so it survives
    // even if the SPI watchdog above triggers $stop on chip-side hangs).
    initial begin
        wait (pll_locked === 1'b1);
        #5_000_000;       // start reporting after CPU has booted (~5 ms)
        forever begin
            #5_000_000;   // every 5 ms of sim time
            $display("[%0t] LVDS_TX: clk_toggles=%0d frame_toggles=%0d data0_toggles=%0d",
                     $time, dbg_tx_clk_toggles, dbg_tx_frame_toggles, dbg_tx_data0_toggles);
        end
    end

endmodule
