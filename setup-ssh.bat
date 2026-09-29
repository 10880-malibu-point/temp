@echo off
setlocal EnableExtensions
title SSH server setup - one shot

:: ---------------------------------------------------------------
:: 1. Elevate to Administrator (UAC prompt appears once)
:: ---------------------------------------------------------------
powershell -NoProfile -Command "if (([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { exit 0 } else { exit 1 }"
if %errorlevel% equ 0 goto ADMINTOK
echo Requesting Administrator rights...
powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
exit /b
:ADMINTOK

echo ============================================
echo  SSH server setup - one shot
echo ============================================

:: ---------------------------------------------------------------
:: 2. Install OpenSSH Server if the sshd service is missing
:: ---------------------------------------------------------------
sc query sshd >nul 2>&1
if %errorlevel% equ 0 goto HAVE_SSHD

echo [1/4] Installing OpenSSH Server...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 | Out-Null"
sc query sshd >nul 2>&1
if %errorlevel% equ 0 goto HAVE_SSHD

echo        capability install did not work, trying winget...
winget install --id Microsoft.OpenSSH.Preview --accept-source-agreements --accept-package-agreements --silent >nul 2>&1
sc query sshd >nul 2>&1
if %errorlevel% equ 0 goto HAVE_SSHD

echo.
echo FAILED: the sshd service is still missing.
echo Fix: connect to the internet and run this file again, or add
echo "OpenSSH Server" from Settings ^> Apps ^> Optional features, then run again.
pause
exit /b 1

:HAVE_SSHD
echo [2/4] OpenSSH Server is installed.

:: ---------------------------------------------------------------
:: 3. Host keys (sshd cannot start without them)
:: ---------------------------------------------------------------
if exist "%ProgramData%\ssh\ssh_host_ed25519_key" goto HOSTKEYS_OK
if not exist "%SystemRoot%\System32\OpenSSH\ssh-keygen.exe" goto HOSTKEYS_OK
echo [3/4] Generating host keys...
"%SystemRoot%\System32\OpenSSH\ssh-keygen.exe" -A
:HOSTKEYS_OK
echo [3/4] Host keys ready.

:: ---------------------------------------------------------------
:: 4. Set sshd to automatic and start it
:: ---------------------------------------------------------------
echo [4/4] Starting sshd...
sc config sshd start= auto >nul 2>&1
net start sshd >nul 2>&1
sc query sshd | findstr /i "RUNNING" >nul
if %errorlevel% equ 0 goto SSHD_OK
echo        first start failed, restarting...
net stop sshd >nul 2>&1
net start sshd >nul 2>&1
:SSHD_OK
sc query sshd | findstr /i "RUNNING" >nul
if %errorlevel% neq 0 (
  echo FAILED: sshd is not running. Send me this window's output.
  pause
  exit /b 1
)
echo        sshd is RUNNING.

:: ---------------------------------------------------------------
:: 5. Firewall: allow inbound TCP 22
:: ---------------------------------------------------------------
powershell -NoProfile -ExecutionPolicy Bypass -Command "if (-not (Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue)) { New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null }"
echo Firewall rule in place for inbound TCP 22.

:: ---------------------------------------------------------------
:: 6. Install the agent public key (password login stays ON as fallback)
:: ---------------------------------------------------------------
set "KEYLINE=ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIP7oODZIEid1To0OuDxGepaBFzGxeozbs8Tr7F84jajX hermes-winnode"
set "FINGERPRINT=AAAAIP7oODZIEid1To0OuDxGepaBFzGxeozbs8Tr7F84jajX"
set "ADMINKEYS=%ProgramData%\ssh\administrators_authorized_keys"

if not exist "%ProgramData%\ssh" mkdir "%ProgramData%\ssh"
findstr /c:"%FINGERPRINT%" "%ADMINKEYS%" >nul 2>&1
if %errorlevel% neq 0 echo %KEYLINE%>>"%ADMINKEYS%"
icacls "%ADMINKEYS%" /inheritance:r /grant "SYSTEM:F" /grant "Administrators:F" >nul 2>&1

if not exist "%USERPROFILE%\.ssh" mkdir "%USERPROFILE%\.ssh"
findstr /c:"%FINGERPRINT%" "%USERPROFILE%\.ssh\authorized_keys" >nul 2>&1
if %errorlevel% neq 0 echo %KEYLINE%>>"%USERPROFILE%\.ssh\authorized_keys"

echo Agent public key installed (both admin and user key files).

:: ---------------------------------------------------------------
:: 7. Report what I need to connect
:: ---------------------------------------------------------------
echo.
echo ---------------------------------------------------
sc query sshd | findstr /i "STATE"
echo Computer name  : %COMPUTERNAME%
echo Signed in as   : %USERDOMAIN%\%USERNAME%
echo.
ipconfig | findstr /i "IPv4"
echo.
echo Send me: the IPv4 address, the account name and its password.
echo Password login stays enabled as a fallback until the key is proven.
echo ---------------------------------------------------
pause
endlocal
