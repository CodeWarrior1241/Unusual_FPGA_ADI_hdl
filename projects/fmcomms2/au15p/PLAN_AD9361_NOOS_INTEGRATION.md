# Plan: NEORV32 + AD9361 no-os Integration

This document outlines the plan to integrate the Analog Devices no-os AD9361 driver with the NEORV32 RISC-V processor on the AU15P + FMCOMMS2/4 platform.

## Executive Summary

The design has the **data path** (LVDS TX/RX via `axi_ad9361` + HLS adapter) and now the **control path HDL** (SPI and GPIO exports in `build_all.tcl`). The remaining work is the **software layer**: no-os platform wrappers and the AD9361 driver application.

### Current State vs. Target State

| Feature | Status | Notes |
|---------|--------|-------|
| LVDS Data Path | **DONE** | axi_ad9361 + axi_ad9361_adapter v3.0 |
| `axi_ad9361` FPGA IP | **DONE** | Configured for LVDS, 2R2T |
| CPU (NEORV32 RV32IMC) | **DONE** | 100 MHz, 32KB IMEM, 16KB DMEM |
| SPI Master (HDL routing) | **DONE** | Pins exported in build_all.tcl (spi_clk, spi_mosi, spi_miso, spi_csn_0) |
| GPIO (Reset, Enable, Status) | **DONE** | Full mapping in build_all.tcl (resetb, sync, en_agc, ctl[3:0], status[7:0]) |
| UART | **DONE** | 115200 baud |
| no-os Platform Wrappers | **TODO** | SPI, GPIO, Delay, Alloc, Mutex |
| no-os AD9361 Driver App | **SKELETON** | `ad9361_no-os` placeholder (UART banner + WFI loop) |
| AD9361 Chip Model (SPI) | **FUTURE** | For simulation testing |
| DMA Engine | **FUTURE** | Not required for SPI control testing |

---

## Phase 1: Hardware Changes (HDL) — DONE

### 1.1 SPI Interface — DONE

Implemented in `build_all.tcl` (lines 351-361):

```tcl
# Create the external SPI signals for AD9361
startgroup
    make_bd_pins_external [get_bd_pins $neorv32_cpu/spi_clk_o]
    set_property name spi_clk [get_bd_ports spi_clk_o_0]
    make_bd_pins_external [get_bd_pins $neorv32_cpu/spi_dat_o]
    set_property name spi_mosi [get_bd_ports spi_dat_o_0]
    make_bd_pins_external [get_bd_pins $neorv32_cpu/spi_dat_i]
    set_property name spi_miso [get_bd_ports spi_dat_i_0]
    make_bd_pins_external [get_bd_pins $neorv32_cpu/spi_csn_o]
    set_property name spi_csn_0 [get_bd_ports spi_csn_o_0]
endgroup
```

**Pin Mapping (FMCOMMS2 FMC, verified against system_constr.xdc):**

| Signal | FMC Pin | Package Pin | IOSTANDARD | NEORV32 Pin |
|--------|---------|-------------|------------|-------------|
| `spi_clk` | LA26_N (D27) | AG34 | LVCMOS18 | `spi_clk_o` |
| `spi_csn_0` | LA26_P (D26) | AF33 | LVCMOS18 PULLUP | `spi_csn_o[0]` |
| `spi_mosi` | LA27_P (C26) | AG31 | LVCMOS18 | `spi_dat_o` |
| `spi_miso` | LA27_N (C27) | AG32 | LVCMOS18 | `spi_dat_i` |

**Note:** `spi_csn_o` is a multi-bit bus (8 chip selects). When exported via `make_bd_pins_external`, Vivado creates a bus port. The XDC constrains `spi_csn_0` as a scalar. This may need an `xlslice` to extract bit 0 — verify when running Vivado.

### 1.2 GPIO Signals — DONE

Implemented in `build_all.tcl` (lines 461-509) using xlslice cells:

| GPIO Bit | Signal | Direction | Purpose | build_all.tcl |
|----------|--------|-----------|---------|---------------|
| `gpio_o[0]` | `up_enable` | Output | TX/RX enable | lines 461-469 |
| `gpio_o[1]` | `up_txnrx` | Output | TX/RX mode | lines 463-469 |
| `gpio_o[2]` | `gpio_resetb` | Output | AD9361 hard reset | lines 473-477 |
| `gpio_o[3]` | `gpio_sync` | Output | Multi-chip sync | lines 480-484 |
| `gpio_o[4]` | `gpio_en_agc` | Output | AGC enable | lines 487-491 |
| `gpio_o[7:5]` | `gpio_ctl[2:0]` | Output | Control signals | lines 493-505 (padded to [3:0]) |
| `gpio_i[7:0]` | `gpio_status[7:0]` | Input | Status readback | lines 508-509 |

---

## Phase 2: AD9361 Chip Model (For Simulation) — FUTURE

**Current State:**
- Design uses TX-to-RX loopback within FPGA (no chip model)
- `deps/testbenches/testbenches/chip/ad9361/ad9361_tb.sv` - LVDS model started (no SPI)

**Required:**
The AD9361 chip model needs to be extended with an SPI slave interface:

```systemverilog
module ad9361_tb #(...) (
    // Existing LVDS interface ...
    // SPI Slave Interface (new)
    input  wire        spi_clk,
    input  wire        spi_csn,
    input  wire        spi_mosi,
    output wire        spi_miso,
    // Control signals (directly from GPIO)
    input  wire        gpio_resetb,
    input  wire        gpio_sync,
    input  wire        gpio_en_agc,
    input  wire [3:0]  gpio_ctl,
    output wire [7:0]  gpio_status
);
// SPI register map (minimal set for ENSM control)
reg [7:0] registers [0:511];
// Key registers: 0x017 State/Status, 0x05A ENSM Mode, 0x244-0x287 Synthesizer
```

---

## Phase 3: Integrated Vivado Project — IN PROGRESS

**Current State:**
- `build_all.tcl` is partially complete — block design automation, AXI interconnect, SPI/GPIO pin exports, and constraint sourcing are implemented
- Skeleton C application created at `deps/neorv32/sw/ad9361_no-os/` (main.c + makefile)
- `build_all.tcl` updated to reference `ad9361_no-os` instead of `ad9361_loopback`
- Single-command build (`vivado -mode batch -source build_all.tcl`) has not been tested end-to-end

### 3.1 C Project Placeholder — DONE

Created a minimal C application in `deps/neorv32/sw/ad9361_no-os/` that compiles and links successfully against the NEORV32 build system, without yet including the no-os AD9361 driver. This ensures the Vivado flow can generate a bitstream with valid firmware BRAM initialisation.

**Files created:**

| File | Purpose |
|------|---------|
| `main.c` | Minimal NEORV32 startup: UART banner print, WFI loop |
| `makefile` | NEORV32 `common.mk` integration, `rv32imc_zicsr_zifencei`, 64KB IMEM, 16KB DMEM |

**`main.c`:**

```c
#include <neorv32.h>

#define BAUD_RATE 115200

int main(void) {
    neorv32_rte_setup();
    neorv32_uart0_setup(BAUD_RATE, 0);
    neorv32_uart0_puts("[ad9361_no-os] Placeholder -- build OK\n");

    while (1) {
        __asm__ volatile ("wfi");
    }
    return 0;
}
```

**`makefile`:**

```makefile
MARCH = rv32imc_zicsr_zifencei
EFFORT = -Os
USER_FLAGS += -ggdb -gdwarf-3
USER_FLAGS += -Wl,--defsym,__neorv32_rom_size=64k
USER_FLAGS += -Wl,--defsym,__neorv32_ram_size=16k

NEORV32_HOME ?= ../..
include $(NEORV32_HOME)/sw/common/common.mk

ifeq ($(OS),Windows_NT)
SET   = echo
MKDIR = mkdir
endif
```

**Key differences from `ad9361_loopback`:**
- `MARCH = rv32imc_zicsr_zifencei` (adds M extension for hardware multiply, C for code density — required by AD9361 driver frequency math)
- `__neorv32_rom_size=64k` (doubled from 32k — AD9361 driver is ~30KB .text alone)

### 3.2 build_all.tcl Completion

Complete the remaining items in `build_all.tcl` for a fully automated Vivado project build:

- [x] Verify `sw_app_dir` points to `ad9361_no-os` placeholder project
- [ ] Verify IMEM size is set to 65536 (64KB)
- [ ] Ensure firmware `.mem` file generation and BRAM init path are correct
- [ ] Confirm XDC constraint sourcing for all SPI/GPIO pins

### 3.3 Single-Command Build Test

Validate that the entire flow runs unattended:

```bash
cd deps/hdl/projects/fmcomms2/au15p
vivado -mode batch -source build_all.tcl -tclargs --build
```

**Success criteria:**
- RISC-V toolchain cross-compiles placeholder firmware without errors
- Vivado synthesis and implementation complete without critical warnings
- Bitstream is generated with BRAM initialised from placeholder firmware
- UART banner message prints on hardware boot (if board available)

---

## Phase 4: no-os SW Application (`ad9361_no-os`) — TODO

### 4.1 Architecture

```
main.c  →  ad9361_api.c / ad9361.c  (unmodified no-os AD9361 driver)
               ↓
           no_os_spi.c / no_os_gpio.c  (unmodified no-os API dispatchers)
               ↓
           neorv32_no_os_spi.c / gpio.c / delay.c  (NEW platform wrappers)
               ↓
           NEORV32 HAL  (neorv32_spi.h, neorv32_gpio.h, neorv32_clint.h)
```

### 4.2 Files to Create

All new files in `deps/neorv32/sw/ad9361_no-os/`:

| File | Purpose |
|------|---------|
| `makefile` | Build config: NEORV32 common.mk + no-os sources via APP_SRC |
| `app_config.h` | AD9361 compile-time config (required by `ad9361_util.h` line 42) |
| `parameters.h` | Hardware addresses, GPIO pins, SPI config (matches build_all.tcl) |
| `neorv32_no_os_spi.c` | `no_os_spi_platform_ops` → NEORV32 SPI HAL |
| `neorv32_no_os_spi.h` | Header: exports `neorv32_spi_ops` |
| `neorv32_no_os_gpio.c` | `no_os_gpio_platform_ops` → NEORV32 GPIO HAL |
| `neorv32_no_os_gpio.h` | Header: exports `neorv32_gpio_ops` |
| `neorv32_no_os_delay.c` | `no_os_udelay/mdelay/get_time` → NEORV32 CLINT MTIME |
| `neorv32_no_os_alloc.c` | `no_os_malloc/calloc/free` → stdlib malloc/calloc/free |
| `neorv32_no_os_mutex.c` | No-op mutex functions (bare-metal, no RTOS) |
| `main.c` | Init AD9361 via `ad9361_init()`, set frequency, status monitoring loop |

### 4.3 Makefile Design

Build with NEORV32 `common.mk`. Reference no-os sources in-place (no copying).

```makefile
MARCH = rv32imc_zicsr_zifencei
EFFORT = -Os
USER_FLAGS += -ggdb -gdwarf-3
USER_FLAGS += -Wl,--defsym,__neorv32_rom_size=64k
USER_FLAGS += -Wl,--defsym,__neorv32_ram_size=16k
USER_FLAGS += -Wl,--defsym,__neorv32_heap_size=4k
USER_FLAGS += -DAXI_ADC_NOT_PRESENT

NOOS_HOME ?= ../../../no-OS
AD9361_DRV = $(NOOS_HOME)/drivers/rf-transceiver/ad9361

APP_SRC += $(AD9361_DRV)/ad9361.c
APP_SRC += $(AD9361_DRV)/ad9361_api.c
APP_SRC += $(AD9361_DRV)/ad9361_util.c
APP_SRC += $(NOOS_HOME)/drivers/api/no_os_spi.c
APP_SRC += $(NOOS_HOME)/drivers/api/no_os_gpio.c
APP_SRC += $(NOOS_HOME)/util/no_os_util.c
APP_SRC += $(NOOS_HOME)/util/no_os_clk.c

APP_INC += -I .
APP_INC += -I $(NOOS_HOME)/include
APP_INC += -I $(AD9361_DRV)

NEORV32_HOME ?= ../..
include $(NEORV32_HOME)/sw/common/common.mk

ifeq ($(OS),Windows_NT)
SET   = echo
MKDIR = mkdir
endif
```

**Key decisions:**
- **`rv32imc`**: M extension for hardware multiply (critical for AD9361 frequency math). C extension for ~25% code density improvement.
- **64KB IMEM**: AD9361 driver is ~30KB .text alone. 32KB is too small.
- **4KB heap**: AD9361 driver allocates `ad9361_rf_phy` (~400+ bytes), `ad9361_phy_platform_data` (~1KB), clock descriptors, SPI/GPIO descriptors.
- **`-DAXI_ADC_NOT_PRESENT`**: Excludes `axi_adc_core.h`/`axi_dac_core.h` dependencies. The axi_ad9361 IP is programmed separately via its own AXI interface; the no-os AXI ADC/DAC drivers are not needed.
- **`ad9361_conv.c` excluded**: Requires axi_adc_core.h (guarded out by `AXI_ADC_NOT_PRESENT`).
- **VPATH mechanism**: `common.mk` line 96 (`VPATH = $(sort $(dir $(SRC)))`) resolves sources across directories.

### 4.4 app_config.h

Required by `ad9361_util.h` line 42 (`#include "app_config.h"`). Controls compile-time features:

```c
#ifndef CONFIG_H_
#define CONFIG_H_

#define HAVE_SPLIT_GAIN_TABLE   1
#define HAVE_TDD_SYNTH_TABLE    1
#define AD9361_DEVICE           1
#define AXI_ADC_NOT_PRESENT
/* Disable verbose messages to save ~5-10KB code size: */
/* #define HAVE_VERBOSE_MESSAGES */

#endif
```

Without `HAVE_VERBOSE_MESSAGES`, `dev_err`/`dev_warn`/`dev_dbg` in `ad9361_util.h` (lines 47-60) compile to no-ops, eliminating thousands of bytes of format strings. Enable during debugging with 128KB IMEM.

### 4.5 parameters.h

```c
#define SPI_DEVICE_ID       0
#define SPI_CS              0       /* AD9361 on spi_csn_o[0] */

/* GPIO pin numbers (NEORV32 gpio_o bit positions) */
#define GPIO_UP_ENABLE_PIN  0       /* gpio_o[0] = up_enable */
#define GPIO_UP_TXNRX_PIN  1       /* gpio_o[1] = up_txnrx */
#define GPIO_RESET_PIN      2       /* gpio_o[2] = gpio_resetb */
#define GPIO_SYNC_PIN       3       /* gpio_o[3] = gpio_sync */
#define GPIO_EN_AGC_PIN     4       /* gpio_o[4] = gpio_en_agc */
#define GPIO_CTL0_PIN       5       /* gpio_o[5] = gpio_ctl[0] */

/* AXI peripheral base addresses (from build_all.tcl) */
#define AXI_AD9361_BASE         0x44A00000UL
#define AXI_AD9361_ADAPTER_BASE 0x44A10000UL
#define BRAM_BASE               0xC0000000UL

#define CPU_CLOCK_HZ        100000000UL
#define BAUD_RATE           115200
```

### 4.6 SPI Wrapper Design (`neorv32_no_os_spi.c`)

Implements `struct no_os_spi_platform_ops` (defined in `deps/no-os/include/no_os_spi.h` lines 210-232):

- **`init`**: Allocate `no_os_spi_desc` via `no_os_calloc`. Call `neorv32_spi_setup(prsc, cdiv, clk_phase=1, clk_polarity=0)` for SPI Mode 1. Calculate prsc/cdiv to achieve ~2.5 MHz from 100 MHz CPU clock: `PRSC=0` (prescaler=2), `CDIV=9` → `100M / (2*2*(1+9)) = 2.5 MHz`.
- **`write_and_read`**: `neorv32_spi_cs_en(desc->chip_select)` → loop `data[i] = neorv32_spi_transfer(data[i])` for each byte → `neorv32_spi_cs_dis()`. Full-duplex, blocking, byte-at-a-time.
- **`remove`**: `neorv32_spi_disable()` + `no_os_free(desc)`.
- **`transfer`**: NULL — `no_os_spi.c` line 200-210 provides fallback using `write_and_read`.
- **`transfer_dma*`**: NULL.

AD9361 SPI protocol: 3-byte transactions (byte 0 = command with R/W bit + address high, byte 1 = address low, byte 2+ = data). The `write_and_read` function handles this transparently.

The `no_os_spi.c` API dispatcher (line 65-81) manages a bus table (`spi_table[]`) and allocates a `no_os_spibus_desc` with a mutex. Our `init` is called after the bus is set up. The mutex calls (`no_os_mutex_lock/unlock` in `write_and_read` at line 171-173) need the no-op mutex implementation.

### 4.7 GPIO Wrapper Design (`neorv32_no_os_gpio.c`)

Implements `struct no_os_gpio_platform_ops` (defined in `deps/no-os/include/no_os_gpio.h` lines 115-134):

- **`gpio_ops_get`**: Allocate `no_os_gpio_desc` via `no_os_calloc`, copy `number`, `port`, `platform_ops` from init param.
- **`gpio_ops_get_optional`**: If `param->number < 0`, set `*desc = NULL`, return 0 (GPIO not connected). Otherwise call `gpio_ops_get`.
- **`gpio_ops_direction_input/output`**: Return 0 (direction fixed in HDL; no software direction register in NEORV32 GPIO).
- **`gpio_ops_set_value`**: `neorv32_gpio_pin_set(desc->number, value)`.
- **`gpio_ops_get_value`**: `*value = (neorv32_gpio_pin_get(desc->number)) ? 1 : 0`. Note: `neorv32_gpio_pin_get` returns a bitmask, not 0/1.
- **`gpio_ops_remove`**: `no_os_free(desc)`.

### 4.8 Delay Wrapper Design (`neorv32_no_os_delay.c`)

Implements functions from `deps/no-os/include/no_os_delay.h` (lines 48-54):

Uses NEORV32 CLINT MTIME — a 64-bit free-running counter at CPU clock rate (100 MHz = 10 ns per tick):

```c
void no_os_udelay(uint32_t usecs) {
    uint64_t start = neorv32_clint_time_get();
    uint64_t ticks = (uint64_t)usecs * (CPU_CLOCK_HZ / 1000000UL);
    while ((neorv32_clint_time_get() - start) < ticks);
}
```

AD9361 reset sequence requires precise timing (>1 us after reset deassertion before first SPI access). MTIME-based delays provide microsecond accuracy vs. the imprecise `neorv32_aux_delay_ms` busy loop.

### 4.9 main.c Outline

1. `neorv32_rte_setup()` — exception handlers
2. Check UART0, GPIO, SPI availability
3. `neorv32_uart0_setup(BAUD_RATE, 0)` — init UART
4. Populate `AD9361_InitParam` with FMCOMMS2 defaults (copy from `deps/no-os/projects/ad9361/src/main.c` lines 176-448, adapt platform ops)
5. `ad9361_init(&phy, &default_init_param)` — full AD9361 initialization via SPI
6. `ad9361_set_en_state_machine_mode(phy, ENSM_MODE_FDD)` — enable FDD
7. Set `up_enable` + `up_txnrx` via GPIO
8. Status monitoring loop (read AXI AD9361 status register periodically)

**AD9361_InitParam adaptation:**
- `gpio_resetb.number = GPIO_RESET_PIN` (= 2), `.platform_ops = &neorv32_gpio_ops`
- `gpio_sync.number = -1` (not used for single-chip)
- `gpio_cal_sw1.number = -1`, `gpio_cal_sw2.number = -1`
- `spi_param.mode = NO_OS_SPI_MODE_1`, `.chip_select = SPI_CS`, `.platform_ops = &neorv32_spi_ops`
- `reference_clk_rate = 40000000UL` (40 MHz FMCOMMS2/4 XTAL)

### 4.10 build_all.tcl Changes

Two edits to `deps/hdl/projects/fmcomms2/au15p/build_all.tcl`:

1. **Line 188**: `set sw_app_dir "$neorv32_home/sw/ad9361_no-os"` — DONE (updated from `ad9361_loopback` in Phase 3)
2. **Line 258**: `CONFIG.IMEM_SIZE {65536}` (was `32768`)

### 4.11 Memory Budget

**IMEM (.text + .rodata) — 64KB:**

| Component | Estimated Size |
|-----------|---------------|
| NEORV32 core library (sw/lib/source/*.c + crt0.S) | ~12 KB |
| AD9361 driver (ad9361.c + ad9361_api.c + ad9361_util.c) | ~30-35 KB |
| no-os API + util (no_os_spi.c, no_os_gpio.c, no_os_util.c, no_os_clk.c) | ~4 KB |
| Platform wrappers (SPI, GPIO, delay, alloc, mutex) | ~1 KB |
| Application main.c + AD9361_InitParam rodata | ~2 KB |
| C library (printf, malloc, memcpy, etc. from newlib-nano) | ~5-8 KB |
| **Total estimated** | **~54-62 KB** |

**DMEM (.data + .bss + heap + stack) — 16KB:**

| Component | Estimated Size |
|-----------|---------------|
| .data (initialized globals) | ~1-2 KB |
| .bss (uninitialized globals) | ~1 KB |
| Heap (ad9361_rf_phy + clocks + descriptors) | 4 KB |
| Stack | ~8-10 KB |
| **Total estimated** | **~14-16 KB** |

If 64KB IMEM is insufficient, increase to 128KB. If 16KB DMEM is insufficient, increase to 32KB.

---

## Phase 5: no-os Sources Reference

### no-os Sources Compiled into ad9361_no-os

| Source File | Location (relative to deps/no-os/) | Purpose |
|-------------|-------------------------------------|---------|
| `ad9361.c` | `drivers/rf-transceiver/ad9361/` | Core driver (SPI register access, calibration, frequency synthesis) |
| `ad9361_api.c` | `drivers/rf-transceiver/ad9361/` | High-level API (init, set_freq, etc.) |
| `ad9361_util.c` | `drivers/rf-transceiver/ad9361/` | Utility functions (clk_get_rate, int_sqrt, ilog2) |
| `no_os_spi.c` | `drivers/api/` | SPI API dispatcher (bus table, mutex management) |
| `no_os_gpio.c` | `drivers/api/` | GPIO API dispatcher |
| `no_os_util.c` | `util/` | Math utilities (find_first_set_bit, rational_best_approx, do_div) |
| `no_os_clk.c` | `util/` | Clock descriptor management |

### no-os Sources Excluded

| Source File | Reason |
|-------------|--------|
| `ad9361_conv.c` | Requires `axi_adc_core.h` — guarded out by `AXI_ADC_NOT_PRESENT` |
| `iio_ad9361.c` | IIO subsystem not needed |
| `no_os_alloc.c` | Replaced by local implementation (avoids weak symbol complexity) |
| `no_os_mutex.c` | Replaced by local no-op implementation (bare-metal, no RTOS) |

### no-os Header Include Paths

- `deps/no-os/include/` — `no_os_spi.h`, `no_os_gpio.h`, `no_os_delay.h`, `no_os_alloc.h`, `no_os_mutex.h`, `no_os_error.h`, `no_os_util.h`, `no_os_clk.h`
- `deps/no-os/drivers/rf-transceiver/ad9361/` — `ad9361.h`, `ad9361_api.h`, `ad9361_util.h`, `common.h`

---

## Phase 6: DMA Engine — FUTURE

Not required for SPI control testing. Current `axi_ad9361_adapter` provides CPU-polled BRAM access.

---

## Potential Issues & Mitigations

1. **`strsep` missing on RISC-V newlib** — `ad9361_util.h` has a `#ifdef WIN32` stub. If RISC-V newlib lacks `strsep`, add a local implementation.
2. **`spi_csn_o` bus width** — NEORV32 exposes 8-bit CS bus. XDC expects scalar `spi_csn_0`. May need `xlslice` in build_all.tcl to extract bit 0. Verify when running Vivado.
3. **64-bit division** — AD9361 driver uses `uint64_t` division for frequency calculations. libgcc provides `__udivdi3`/`__umoddi3`. Hardware M extension accelerates the 32-bit operations these use internally.
4. **Binary too large for 64KB** — Enable `HAVE_VERBOSE_MESSAGES` only after confirming fit; if still too large, increase to 128KB IMEM.
5. **`printf` redirection** — NEORV32 newlib-nano provides `printf` via UART0 (crt0 provides `_write` syscall). The AD9361 driver's `dev_err` macros use `printf` when `HAVE_VERBOSE_MESSAGES` is enabled. No float printf (`-u _printf_float`) to keep code size down.
6. **Heap fragmentation** — AD9361 driver allocates during `ad9361_init()` and never frees. No fragmentation concern for single init.

---

## Address Map

| Peripheral | Base Address | Size | Status |
|------------|--------------|------|--------|
| NEORV32 Internal | `0x00000000` | 64KB IMEM + 16KB DMEM | Existing (IMEM to increase to 64KB) |
| QPSK BRAM | `0xC0000000` | 32KB | Existing |
| axi_ad9361 | `0x44A00000` | 64KB | Existing |
| axi_ad9361_adapter | `0x44A10000` | 16KB | Existing |

---

## Block Diagram: Target Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           FPGA Design                                        │
│                                                                              │
│  ┌──────────────┐     ┌─────────────────┐     ┌─────────────────────────┐   │
│  │   NEORV32    │     │  AXI Interconnect│     │      axi_ad9361         │   │
│  │   RV32IMC    │────▶│                 │────▶│   (ADC/DAC datapath)    │   │
│  │              │     │                 │     └──────────┬──────────────┘   │
│  │  ┌────────┐  │     │                 │                │ LVDS            │
│  │  │  SPI   │──┼─────┼───────────────────────┐          │                 │
│  │  └────────┘  │     │                 │     │          ▼                 │
│  │  ┌────────┐  │     │                 │     │   ┌──────────────┐         │
│  │  │  GPIO  │──┼─────┼───────────────────────┼──▶│  AD9361 Chip │         │
│  │  └────────┘  │     │                 │     │   │   (Model or  │         │
│  │  ┌────────┐  │     │                 │     └──▶│    Real HW)  │         │
│  │  │  UART  │──┼─────┼──▶ Console      │  SPI    └──────────────┘         │
│  │  └────────┘  │     │                 │                                   │
│  └──────────────┘     └─────────────────┘                                   │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘

Legend:
  ─────▶  AXI bus
  ──SPI── SPI signals (sclk, mosi, miso, cs)
  ──GPIO─ GPIO signals (reset, enable, txnrx, ctl, status)
  ─LVDS─  LVDS differential pairs (clk, frame, data)
```

---

## NEORV32 HAL Reference

Key NEORV32 HAL functions used by the platform wrappers:

### SPI (`sw/lib/source/neorv32_spi.c`)
- `neorv32_spi_setup(int prsc, int cdiv, int clk_phase, int clk_polarity)` — Enable & configure
- `neorv32_spi_transfer(uint8_t tx_data)` → `uint8_t` — Single byte, blocking, full-duplex
- `neorv32_spi_cs_en(int cs)` — Activate chip select (active low), blocking
- `neorv32_spi_cs_dis()` — Deactivate all chip selects, blocking
- Clock: `clk = cpu_clock / (2 * PRSC_LUT[prsc] * (1 + cdiv))`
- FIFO depth: 4 (configured in build_all.tcl)
- 8 chip select lines (`spi_csn_o[7:0]`)

### GPIO (`sw/lib/source/neorv32_gpio.c`)
- `neorv32_gpio_pin_set(int pin, int value)` — Set single pin (0-31)
- `neorv32_gpio_pin_get(int pin)` → `uint32_t` — Read single pin (returns bitmask, NOT 0/1)
- `neorv32_gpio_port_set(uint32_t mask)` — Set entire port
- `neorv32_gpio_port_get()` → `uint32_t` — Read entire port
- No direction register (direction fixed in HDL)

### Timer/Delay (`sw/lib/source/neorv32_clint.c`)
- `neorv32_clint_time_get()` → `uint64_t` — Get MTIME (atomic 64-bit read)
- MTIME increments at CPU clock rate (100 MHz = 10 ns/tick)

### System Info (`sw/lib/include/neorv32_sysinfo.h`)
- `neorv32_sysinfo_get_clk()` → `uint32_t` — Get CPU clock frequency in Hz

---

## Files Reference

### Current NEORV32 Design
- `deps/hdl/projects/fmcomms2/au15p/build_all.tcl` — AU15P synthesis build script
- `deps/hdl/projects/fmcomms2/au15p/system_constr.xdc` — Pin constraints
- `deps/neorv32/setups/neorv32_sw_ad9361_datapath_sim/build_all.tcl` — Simulation build (reference)
- `deps/neorv32/sw/ad9361_no-os/main.c` — Skeleton no-os app (placeholder, Phase 3.1)
- `deps/neorv32/sw/ad9361_no-os/makefile` — Build config: rv32imc, 64KB IMEM, 16KB DMEM
- `deps/neorv32/sw/ad9361_loopback/main.c` — Existing loopback monitor app (reference, used by datapath sim)
- `deps/neorv32/sw/common/common.mk` — NEORV32 build system

### no-os AD9361 Driver
- `deps/no-os/drivers/rf-transceiver/ad9361/ad9361.c` — Core driver
- `deps/no-os/drivers/rf-transceiver/ad9361/ad9361_api.h` — High-level API
- `deps/no-os/drivers/rf-transceiver/ad9361/ad9361_util.h` — Includes `app_config.h`, defines `dev_err` macros
- `deps/no-os/drivers/rf-transceiver/ad9361/common.h` — Defines `no_os_clk` struct
- `deps/no-os/projects/ad9361/src/main.c` — Reference project (AD9361_InitParam at lines 176-448)
- `deps/no-os/include/no_os_spi.h` — SPI platform ops definition (lines 210-232)
- `deps/no-os/include/no_os_gpio.h` — GPIO platform ops definition (lines 115-134)
- `deps/no-os/include/no_os_delay.h` — Delay function signatures
- `deps/no-os/include/no_os_alloc.h` — Alloc function signatures
- `deps/no-os/include/no_os_mutex.h` — Mutex function signatures
- `deps/no-os/include/no_os_error.h` — Error codes (uses `<errno.h>`)

### ADI FMCOMMS2 Reference
- `deps/hdl/projects/fmcomms2/kcu105/system_top.v`
- `deps/hdl/projects/fmcomms2/common/fmcomms2_bd.tcl`
