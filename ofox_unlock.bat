@echo off
REM Remove OrangeFox recovery lock/password from device.
setlocal enabledelayedexpansion

echo [*] Removing OrangeFox password/lock files...
echo.

echo     Removing /persist/.fsec (master config)...
adb shell rm -f /persist/.fsec 2>nul

echo     Removing .foxs and .fsec files...
adb shell "find / ( -name '.foxs' -o -name '.fsec' ) -type f -exec rm -f {} \;" 2>nul

echo.
echo [*] Verifying...
adb shell "find / ( -name '.foxs' -o -name '.fsec' ) -type f 2>/dev/null" 2>nul | findstr /r /c:"." >nul
if errorlevel 1 (
    echo [*] Done. All OrangeFox lock files removed.
) else (
    echo [!] Some files remain. Try rebooting and running again.
    adb shell "find / ( -name '.foxs' -o -name '.fsec' ) -type f 2>/dev/null" 2>nul
)
