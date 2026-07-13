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

iverilog -I include -g2012 -s tb_m_ext -o m_ext.vvp -f scripts\m_ext_files.f
if errorlevel 1 exit /b 1

vvp m_ext.vvp
if errorlevel 1 exit /b 1

if exist m_ext_result.txt type m_ext_result.txt

