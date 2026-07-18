@echo off
REM =============================================================================
REM FMCOMMS2/AU15P Firmware Debug — Questa Launcher (Windows)
REM =============================================================================
REM Reproduces the ad9361_no-os firmware crash in simulation with a minimal
REM AD9361 SPI slave model. Full waveform visibility for debugging.
REM
REM Prerequisites:
REM   1. Vivado project built (build_all.tcl)
REM   2. Firmware built and installed:
REM        cd deps\neorv32\sw\ad9361_no-os && make clean_all exe install
REM   3. Vivado sim scripts exported:
REM        vivado -mode tcl -source sim\export_sim.tcl
REM
REM Usage:
REM   run_sim.bat                     20ms, GUI, fast
REM   run_sim.bat --detailed          20ms, GUI, full waveforms
REM   run_sim.bat --detailed --batch  20ms, headless
REM   run_sim.bat --time 50ms         longer run
REM =============================================================================

setlocal enabledelayedexpansion

set VSIM=vsim
set SIM_MODE=gui
set SIM_TIME=20ms
set DETAILED=no

cd /d "%~dp0"

:parse_args
if "%~1"=="" goto args_done
if /i "%~1"=="--time"     ( set SIM_TIME=%~2& shift & shift & goto parse_args )
if /i "%~1"=="--gui"      ( set SIM_MODE=gui& shift & goto parse_args )
if /i "%~1"=="--batch"    ( set SIM_MODE=batch& shift & goto parse_args )
if /i "%~1"=="--detailed" ( set DETAILED=yes& shift & goto parse_args )
if /i "%~1"=="--clean"    ( goto do_clean )
if /i "%~1"=="--help"     ( goto do_help )
echo Unknown option: %~1
exit /b 1

:do_clean
echo Cleaning...
if exist questa_lib rd /s /q questa_lib
if exist work rd /s /q work
del /q *.wlf *.log *.vstf transcript modelsim.ini 2>nul
echo Done.
exit /b 0

:do_help
echo FMCOMMS2/AU15P Firmware Debug — Questa Simulation
echo.
echo Usage: run_sim.bat [options]
echo.
echo   --time TIME    Simulation time (default: 20ms)
echo   --gui          GUI mode (default)
echo   --batch        Batch/headless mode
echo   --detailed     Full signal visibility with waveforms
echo   --clean        Remove generated files
echo   --help         Show this help
exit /b 0

:args_done

REM Check Questa is available
where %VSIM% >nul 2>nul
if errorlevel 1 (
    echo ERROR: Questa ^(vsim^) not found in PATH
    exit /b 1
)

REM Check Vivado sim scripts exist
set QUESTA_SCRIPTS=..\fmcomms2_au15p.ip_user_files\sim_scripts\questa
if not exist "%QUESTA_SCRIPTS%" (
    echo ERROR: Vivado simulation scripts not found.
    echo        Run in Vivado Tcl console:
    echo          source [file normalize sim/export_sim.tcl]
    exit /b 1
)

REM Sync NEORV32 IMEM image to ipshared locations
set NEORV32_HOME=..\..\..\..\neorv32
set IMEM_SRC=%NEORV32_HOME%\rtl\core\neorv32_imem_image.vhd

if exist "%IMEM_SRC%" (
    echo Syncing IMEM image...
    for /r "..\fmcomms2_au15p.ip_user_files" %%F in (neorv32_imem_image.vhd) do (
        copy /y "%IMEM_SRC%" "%%F" >nul
        echo   -^> %%~dpF
    )
    for /r "..\fmcomms2_au15p.gen" %%F in (neorv32_imem_image.vhd) do (
        copy /y "%IMEM_SRC%" "%%F" >nul
        echo   -^> %%~dpF
    )
) else (
    echo WARNING: IMEM image not found at %IMEM_SRC%
    echo   Build firmware: cd deps\neorv32\sw\ad9361_no-os ^&^& make clean_all exe install
)

echo ==========================================
echo   FMCOMMS2/AU15P Firmware Debug Sim
echo ==========================================
echo   Sim time: %SIM_TIME%
echo   Mode:     %SIM_MODE%
echo   Detailed: %DETAILED%
echo ==========================================

set SIM_VARS=set SIM_TIME {%SIM_TIME%}; set DETAILED {%DETAILED%}

if /i "%SIM_MODE%"=="batch" (
    %VSIM% -c -do "%SIM_VARS%; source simulate.do; quit -f"
) else (
    %VSIM% -do "%SIM_VARS%; source simulate.do"
)

endlocal
