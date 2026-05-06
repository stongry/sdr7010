@echo off
REM Windows Vivado xsim launcher for Path X simulation.
REM Run this from the simulation\ folder after copying the source tree.
REM Adjust SRC if your fpga_hdl checkout lives elsewhere.

set SRC=%~dp0..
set WORK=%~dp0path_x_sim
if not exist %WORK% mkdir %WORK%
pushd %WORK%

call "C:\Xilinx\Vivado\2024.2\settings64.bat"
xvlog "%SRC%\qpsk_mod.v" "%SRC%\qpsk_demod.v" "%~dp0tb_path_x_simple.v"
if errorlevel 1 goto err
xelab tb_path_x_simple -debug typical -snapshot pxs
if errorlevel 1 goto err
start xsim --gui pxs

popd
exit /b 0
:err
echo BUILD FAILED.
popd
exit /b 1
