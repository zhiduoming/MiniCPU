@echo off
setlocal
cd /d "%~dp0\.."

where iverilog >nul 2>nul
if errorlevel 1 (
  echo iverilog not found in PATH.
  exit /b 1
)

where vvp >nul 2>nul
if errorlevel 1 (
  echo vvp not found in PATH.
  exit /b 1
)

iverilog -I include -g2012 -s tb_selfcheck -o sim.vvp -f scripts\rtl_files.f sim\tb_selfcheck.v
if errorlevel 1 exit /b 1

vvp sim.vvp
if errorlevel 1 exit /b 1

if exist sim_result.txt type sim_result.txt
