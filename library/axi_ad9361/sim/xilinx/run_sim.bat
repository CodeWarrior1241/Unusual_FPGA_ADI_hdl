@echo off
REM ================================================================================
REM axi_ad9361 Testbench - Questa Prime Simulation Launcher (Windows)
REM ================================================================================
REM This batch file launches Questa Prime simulation for the axi_ad9361 testbench
REM ================================================================================

setlocal enabledelayedexpansion

REM Configuration
set VSIM="C:\Program Files\Mentor_Graphics\Questa_Prime_2025.1\win64\vsim.exe"
set SIM_MODE=gui
set SIM_TIME=100us

REM Change to script directory
cd /d "%~dp0"

REM Parse command line arguments
:parse_args
if "%~1"=="" goto done_args
if "%~1"=="--time" (
    set SIM_TIME=%~2
    shift
    shift
    goto parse_args
)
if "%~1"=="--gui" (
    set SIM_MODE=gui
    shift
    goto parse_args
)
if "%~1"=="--batch" (
    set SIM_MODE=batch
    shift
    goto parse_args
)
if "%~1"=="--clean" (
    echo Cleaning work directories and simulation artifacts...
    if exist work rmdir /s /q work
    if exist *.wlf del /q *.wlf
    if exist *.log del /q *.log
    if exist *.vstf del /q *.vstf
    if exist transcript del /q transcript
    if exist qpsk_bram_data.hex del /q qpsk_bram_data.hex
    echo Done.
    exit /b 0
)
if "%~1"=="--help" (
    echo axi_ad9361 Testbench - Questa Prime Simulation Script
    echo.
    echo Usage: run_sim.bat [options]
    echo.
    echo Options:
    echo   --time TIME    Set simulation time (default: 100us)
    echo   --gui          Run in GUI mode (default)
    echo   --batch        Run in batch/command-line mode
    echo   --clean        Remove work directories and generated files
    echo   --help         Show this help message
    echo.
    echo Environment Variables:
    echo   XILINX_QUESTA_LIBS   Path to pre-compiled Xilinx simulation libraries
    echo                        (required, set before running)
    echo.
    echo Examples:
    echo   run_sim.bat                    Run with defaults (100us, GUI)
    echo   run_sim.bat --time 200us       Run for 200us
    echo   run_sim.bat --batch            Run in batch mode
    echo   run_sim.bat --time 1ms --batch Run 1ms in batch mode
    exit /b 0
)
shift
goto parse_args
:done_args

REM Check if XILINX_QUESTA_LIBS is set
if not defined XILINX_QUESTA_LIBS (
    echo ERROR: XILINX_QUESTA_LIBS environment variable not set!
    echo.
    echo Please set it to point to your pre-compiled Xilinx simulation libraries:
    echo   set XILINX_QUESTA_LIBS=C:\Work\Questa_Libraries_Vivado
    echo.
    echo To compile Xilinx libraries, run in Vivado Tcl Console:
    echo   compile_simlib -simulator questa -simulator_exec_path {path_to_questa} -dir {output_dir}
    exit /b 1
)

REM Check if Questa is available
if not exist %VSIM% (
    echo ERROR: Questa Prime not found at %VSIM%
    echo Please update VSIM path in this script or install Questa Prime
    exit /b 1
)

echo ==========================================
echo axi_ad9361 Questa Simulation
echo ==========================================
echo Simulation time: %SIM_TIME%
echo Simulation mode: %SIM_MODE%
echo Xilinx libs:     %XILINX_QUESTA_LIBS%
echo ==========================================

if "%SIM_MODE%"=="batch" (
    echo Running in batch mode...
    %VSIM% -c -do "set SIM_TIME {%SIM_TIME%}; do simulate.do; quit -f"

    echo.
    echo ==========================================
    echo Simulation complete!
    echo ==========================================
) else (
    echo Running in GUI mode...
    %VSIM% -do "set SIM_TIME {%SIM_TIME%}; do simulate.do"
)

endlocal
