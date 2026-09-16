@echo off
setlocal

for %%i in ("%~dp0..") do set "PKG_ROOT=%%~fi"

if not defined JULIA_BIN set "JULIA_BIN=julia"
if not defined JETLS_DEPOT set "JETLS_DEPOT=%PKG_ROOT%\store"
set "JULIA_DEPOT_PATH=%JETLS_DEPOT%"

rem The sysimage links against libjulia.<major>.<minor> and loads on nothing
rem else. Left to Julia, a mismatch surfaces as a raw load error naming a
rem library the reader has no reason to connect to their Julia version, so name
rem it here instead. This goes to stderr: stdout carries the LSP stream.
rem Only major.minor is compared, since that is what the binding pins. A missing
rem file, or a Julia that could not be run at all, means something other than a
rem known-bad pairing, so those cases are left to Julia to report.
set "VERSION_FILE=%PKG_ROOT%\share\jetls\JULIA_VERSION"
if not exist "%VERSION_FILE%" goto :run
set /p BUILT_WITH=<"%VERSION_FILE%"
for /f "usebackq tokens=3" %%v in (`"%JULIA_BIN%" --version`) do set "HAVE=%%v"
if not defined HAVE goto :run
for /f "tokens=1,2 delims=." %%a in ("%BUILT_WITH%") do set "WANT_MM=%%a.%%b"
for /f "tokens=1,2 delims=." %%a in ("%HAVE%") do set "HAVE_MM=%%a.%%b"
if "%WANT_MM%"=="%HAVE_MM%" goto :run
echo jetls: this build needs Julia %WANT_MM%, but '%JULIA_BIN%' is %HAVE_MM% 1>&2
echo jetls: install Julia %WANT_MM%, or point JULIA_BIN at it 1>&2
exit /b 1

:run
"%JULIA_BIN%" --startup-file=no --history-file=no --threads=auto --sysimage="%PKG_ROOT%\lib\jetls.dll" --project="%PKG_ROOT%\share\jetls" -m JETLS %*
