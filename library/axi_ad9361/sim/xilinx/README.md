# axi_ad9361 Testbench Simulation

This directory contains a TX-to-RX loopback testbench for the ADI axi_ad9361 IP core.
The testbench verifies the DAC-to-ADC datapath using LVDS loopback, feeding QPSK samples
through the DAC interface and capturing them at the ADC output.

## Test Description

The testbench:
1. Loads 1024 QPSK samples from `qpsk_bram_init.coe`
2. Configures the axi_ad9361 for DMA mode via AXI-Lite
3. Feeds samples through the DAC interface
4. Loops TX LVDS outputs back to RX LVDS inputs
5. Verifies ADC output matches expected values (DAC/16 due to 12-bit resolution)

## Simulation Methods

Two simulation methods are supported:

### Method 1: Vivado XSim

Run directly from Vivado's TCL console.

```tcl
cd {C:/Work/Sandbox/QPSK_Triple_Comparison/deps/hdl/library/axi_ad9361/sim/xilinx}
source run_sim.tcl
```

This method:
- Creates a Vivado project in memory
- Compiles all sources
- Launches XSim with waveform viewer
- Runs for 100us (testbench self-terminates)

### Method 2: Questa Prime / ModelSim

Run from command line or Questa GUI.

#### Prerequisites

1. **Pre-compiled Xilinx simulation libraries** are required. Compile them once using Vivado:

   ```tcl
   # In Vivado TCL Console:
   compile_simlib -simulator questa \
     -simulator_exec_path {C:/Program Files/Mentor_Graphics/Questa_Prime_2025.1/win64} \
     -family all -language all -library all \
     -dir {C:/Work/Questa_Libraries_Vivado}
   ```

   This takes 30-60 minutes but only needs to be done once per Vivado version.

2. **Set the environment variable** pointing to the compiled libraries:

   **Windows:**
   ```cmd
   set XILINX_QUESTA_LIBS=C:\Work\Questa_Libraries_Vivado
   ```

   **Linux/macOS:**
   ```bash
   export XILINX_QUESTA_LIBS=/path/to/Questa_Libraries_Vivado
   ```

#### Running the Simulation

**Windows:**
```cmd
cd deps\hdl\library\axi_ad9361\sim\xilinx
run_sim.bat
```

**Linux/macOS:**
```bash
cd deps/hdl/library/axi_ad9361/sim/xilinx
./run_sim.sh
```

#### Command Line Options

```
Options:
  --time TIME    Set simulation time (default: 100us)
  --gui          Run in GUI mode (default)
  --batch        Run in batch/command-line mode
  --clean        Remove work directories and generated files
  --help         Show help message

Examples:
  run_sim.bat                    Run with defaults (100us, GUI)
  run_sim.bat --time 200us       Run for 200us
  run_sim.bat --batch            Run in batch mode
  run_sim.bat --time 1ms --batch Run 1ms in batch mode
```

#### Manual Questa Commands

You can also run directly from Questa's TCL console:

```tcl
cd {C:/Work/Sandbox/QPSK_Triple_Comparison/deps/hdl/library/axi_ad9361/sim/xilinx}
do simulate.do
```

Or compile and simulate separately:

```tcl
do compile.do
# ... then later ...
do simulate.do
```

## Files

| File | Description |
|------|-------------|
| `axi_ad9361_tb.v` | Main testbench (Verilog) |
| `qpsk_bram_init.coe` | QPSK sample data (Xilinx COE format) |
| `run_sim.tcl` | Vivado XSim simulation script |
| `add_waves.tcl` | XSim waveform configuration |
| `compile.do` | Questa compilation script |
| `simulate.do` | Questa simulation script |
| `run_sim.bat` | Windows launcher for Questa |
| `run_sim.sh` | Linux/macOS launcher for Questa |

## Expected Output

The testbench prints status messages showing:
- Configuration steps via AXI-Lite
- DAC and ADC sample counts
- Loopback data verification

A working interface will print this, showing that the 1024 sample set was sent through 3 cycles (1024*3=3072 samples):

```
========================================
   Test Complete - Statistics
========================================
   Total ADC samples captured: 3072
   Total DAC requests served:  3072
   Complete buffer cycles:     3
   ADC R1 mode:                0
   DAC R1 mode:                0
========================================
```

A successful run ends with:

```
========================================
  LOOPBACK TEST PASSED
  Data flows correctly through:
    DAC -> TX LVDS -> RX LVDS -> ADC
========================================

Simulation complete.
```

## Data Scaling

The AD9361 has 12-bit data resolution. The testbench demonstrates this scaling:
- DAC input: 16-bit signed (~±16384)
- ADC output: 16-bit signed (~±1024)
- Ratio: ADC = DAC / 16 (4-bit shift due to 12-bit interface)