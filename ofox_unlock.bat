@echo off
setlocal enabledelayedexpansion

:: ===========================================================================
::  OrangeFox Recovery lock remover – Windows CMD version
::  Works in recovery and rooted Android boot.
:: ===========================================================================
set "ADB=adb"
set "ROOT_PREFIX="
set "MOUNTED=false"
set "PERSIST_DIR=/persist"

:: ---------------------------------------------------------------------------
::  1. Detect root access
:: ---------------------------------------------------------------------------
echo [*] Checking root access...
set "ROOT_MODE="

:: Try direct adb root (adbd runs as root)
for /f "delims=" %%a in ('%ADB% shell id -u 2^>nul') do (
    if "%%a"=="0" set "ROOT_MODE=direct"
    goto :CHECK_SU
)
:CHECK_SU
if defined ROOT_MODE goto :ROOT_OK

:: Try su
for /f "delims=" %%a in ('%ADB% shell su -c "id -u" 2^>nul') do (
    if "%%a"=="0" (
        set "ROOT_MODE=su"
        set "ROOT_PREFIX=su -c"
    )
    goto :TRY_ADB_ROOT
)
:TRY_ADB_ROOT
if defined ROOT_MODE goto :ROOT_OK

:: Last resort: adb root
echo     [-] Not root and no su. Trying adb root...
timeout /t 2 /nobreak >nul
for /f "delims=" %%a in ('%ADB% root 2^>nul') do echo     %%a
timeout /t 2 /nobreak >nul
for /f "delims=" %%a in ('%ADB% shell id -u 2^>nul') do (
    if "%%a"=="0" set "ROOT_MODE=direct"
    goto :ROOT_OK
)

:ROOT_OK
if not defined ROOT_MODE (
    echo.
    echo [!] ERROR: Cannot gain root access.
    echo     Try: run script from a root shell, or ensure
    echo     the device is in recovery mode.
    exit /b 1
)
if "%ROOT_MODE%"=="direct" (
    echo     [+] Already root (adbd runs as root^).
)
if "%ROOT_MODE%"=="su" (
    echo     [+] su available. Using su -c for all commands.
)

:: ---------------------------------------------------------------------------
::  2. Check if /persist is already accessible
:: ---------------------------------------------------------------------------
echo.
echo [*] Checking if %PERSIST_DIR% is accessible...
set "FOUND="
for /f "delims=" %%a in ('%ADB% shell %ROOT_PREFIX% "ls %PERSIST_DIR%/.foxs 2>/dev/null" 2^>nul') do (
    set "FOUND=1"
    goto :PERSIST_CHECK_DONE
)
:PERSIST_CHECK_DONE
if defined FOUND (
    echo     [+] /persist is mounted and accessible.
) else (
    echo     [-] /persist is NOT accessible.
    echo.
    echo [*] Searching for persist block device...

    set "BLOCK="
    :: Search known paths
    for %%P in (
        "/dev/block/bootdevice/by-name/persist"
        "/dev/block/platform/*/by-name/persist"
        "/dev/block/platform/*/*/by-name/persist"
    ) do (
        echo     Probing: %%P
        for /f "delims=" %%B in ('%ADB% shell %ROOT_PREFIX% "for p in %%P; do [ -e \"\$p\" ] && echo \"\$p\" && break; done" 2^>nul') do (
            set "BLOCK=%%B"
            goto :FOUND_BLOCK
        )
    )
    :FOUND_BLOCK

    :: Fallback: blkid
    if "!BLOCK!"=="" (
        echo     -^> Not found via path patterns. Trying blkid...
        for /f "delims=" %%B in ('%ADB% shell %ROOT_PREFIX% "blkid 2>/dev/null | grep -i '\"persist\"' | cut -d: -f1" 2^>nul') do (
            set "BLOCK=%%B"
        )
    )

    if "!BLOCK!"=="" (
        echo.
        echo [!] ERROR: Could not locate persist partition.
        echo     The password is likely in .foxs files only.
        echo     Trying direct file cleanup instead...
    ) else (
        echo.
        echo     [+] Found persist block device: !BLOCK!

        set "PERSIST_DIR=/tmp/persist"
        echo.
        echo [*] Preparing mountpoint at !PERSIST_DIR! ...
        %ADB% shell %ROOT_PREFIX% "mkdir -p !PERSIST_DIR!" 2>nul

        :: Detect filesystem type
        set "FSTYPE="
        for /f "delims=" %%F in ('%ADB% shell %ROOT_PREFIX% "blkid -o value -s TYPE !BLOCK! 2>/dev/null" 2^>nul') do (
            set "FSTYPE=%%F"
            goto :GOT_FSTYPE
        )
        :GOT_FSTYPE
        if "!FSTYPE!"=="" set "FSTYPE=ext4"

        echo     Mounting !BLOCK! (type !FSTYPE!^) to !PERSIST_DIR! ...
        %ADB% shell %ROOT_PREFIX% "mount -t !FSTYPE! !BLOCK! !PERSIST_DIR!" 2>nul
        :: Verify mount
        for /f "delims=" %%a in ('%ADB% shell %ROOT_PREFIX% "grep -q ' !PERSIST_DIR! ' /proc/mounts && echo yes" 2^>nul') do set "MOUNT_OK=%%a"
        if "!MOUNT_OK!"=="yes" (
            echo     [+] Mount successful.
            set "MOUNTED=true"
        ) else (
            echo     [-] Mount failed. Trying read-only...
            %ADB% shell %ROOT_PREFIX% "mount -t !FSTYPE! -o ro !BLOCK! !PERSIST_DIR!" 2>nul
            for /f "delims=" %%a in ('%ADB% shell %ROOT_PREFIX% "grep -q ' !PERSIST_DIR! ' /proc/mounts && echo yes" 2^>nul') do set "MOUNT_OK=%%a"
            if "!MOUNT_OK!"=="yes" (
                echo     [+] Read-only mount succeeded.
                set "MOUNTED=true"
            ) else (
                echo     [-] Mount still failed. Will skip persist cleanup.
            )
        )
    )
)

:: ---------------------------------------------------------------------------
::  3. Remove lock files from the persist partition
:: ---------------------------------------------------------------------------
if "%MOUNTED%"=="true" (
    echo.
    echo [*] Removing OrangeFox password/lock files from %PERSIST_DIR%...
    for %%F in (.fsec .foxs) do (
        set "path=%PERSIST_DIR%/%%F"
        for /f "delims=" %%a in ('%ADB% shell %ROOT_PREFIX% "ls -la '!path!' 2>/dev/null" 2^>nul') do (
            echo     %%a
            %ADB% shell %ROOT_PREFIX% "rm -f '!path!'" 2>nul
            echo     -^> removed
            goto :NEXT_FILE
        )
        echo     !path! -- not found
        :NEXT_FILE
    )
)

:: ---------------------------------------------------------------------------
::  4. Additional known recovery paths
:: ---------------------------------------------------------------------------
echo.
echo [*] Checking additional known paths...
for %%L in ("/data/recovery/Fox/.foxs" "/data/recovery/Fox/.fsec") do (
    for /f "delims=" %%a in ('%ADB% shell %ROOT_PREFIX% "ls -la %%~L 2>/dev/null" 2^>nul') do (
        echo     %%a
        %ADB% shell %ROOT_PREFIX% "rm -f %%~L" 2>nul
        echo     -^> removed
    )
)

:: ---------------------------------------------------------------------------
::  5. Full filesystem scan for stray .foxs / .fsec
:: ---------------------------------------------------------------------------
echo.
echo [*] Scanning for stray copies across entire filesystem...

echo     Searching for .foxs files...
for /f "delims=" %%a in ('%ADB% shell %ROOT_PREFIX% "find / -name .foxs -type f 2>/dev/null" 2^>nul') do (
    set "fox_path=%%a"
    for /f "delims=" %%b in ('%ADB% shell %ROOT_PREFIX% "ls -la '!fox_path!' 2>/dev/null" 2^>nul') do (
        echo     %%b
        %ADB% shell %ROOT_PREFIX% "rm -f '!fox_path!'" 2>nul
        echo     -^> removed
    )
)

echo     Searching for .fsec files...
for /f "delims=" %%a in ('%ADB% shell %ROOT_PREFIX% "find / -name .fsec -type f 2>/dev/null" 2^>nul') do (
    set "fsec_path=%%a"
    for /f "delims=" %%b in ('%ADB% shell %ROOT_PREFIX% "ls -la '!fsec_path!' 2>/dev/null" 2^>nul') do (
        echo     %%b
        %ADB% shell %ROOT_PREFIX% "rm -f '!fsec_path!'" 2>nul
        echo     -^> removed
    )
)

:: ---------------------------------------------------------------------------
::  6. Unmount and clean up
:: ---------------------------------------------------------------------------
if "%MOUNTED%"=="true" (
    echo.
    echo [*] Unmounting %PERSIST_DIR%...
    %ADB% shell %ROOT_PREFIX% "umount %PERSIST_DIR%" 2>nul
    %ADB% shell %ROOT_PREFIX% "rm -rf %PERSIST_DIR%" 2>nul
    echo     [+] Cleaned up mount point.
)

:: ---------------------------------------------------------------------------
::  7. Final verification
:: ---------------------------------------------------------------------------
echo.
echo [*] Verifying...
set "REMAINING="
for /f "delims=" %%a in ('%ADB% shell %ROOT_PREFIX% "find / \( -name .foxs -o -name .fsec \) -type f 2>/dev/null" 2^>nul') do (
    if not defined REMAINING (set "REMAINING=%%a") else (set "REMAINING=!REMAINING!\n%%a")
)
if not defined REMAINING (
    echo     [+] No remaining OrangeFox lock files found.
    echo.
    echo [*] Done. All OrangeFox lock files removed.
) else (
    echo     [!] The following files still exist:
    for %%L in ("!REMAINING:\n=" "!") do echo         %%~L
)
exit /b 0
