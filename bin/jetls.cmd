@echo off
setlocal

for %%i in ("%~dp0..") do set "PKG_ROOT=%%~fi"

if not defined JULIA_BIN set "JULIA_BIN=julia"
if not defined JETLS_DEPOT set "JETLS_DEPOT=%PKG_ROOT%\store"
set "JULIA_DEPOT_PATH=%JETLS_DEPOT%"

"%JULIA_BIN%" --startup-file=no --history-file=no --threads=auto --sysimage="%PKG_ROOT%\lib\jetls.dll" --project="%PKG_ROOT%\share\jetls" -m JETLS %*
