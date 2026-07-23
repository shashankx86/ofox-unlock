#!/usr/bin/env bash
# Remove OrangeFox recovery lock/password from device.
# Works in recovery and on rooted system boot (Android 5.1+).
set -e

# --- Root detection (unchanged) ---
echo "[*] Checking root access..."
UID_OUT=$(adb shell id -u 2>/dev/null | tr -d '\r' | head -1)
if [[ "$UID_OUT" == "0" ]]; then
    echo "    [+] Already root (adbd runs as root)."
    ADB() { adb shell "$@"; }
elif adb shell su -c id -u 2>/dev/null | tr -d '\r' | grep -q '^0$'; then
    echo "    [+] su available. Using su -c for all commands."
    ADB() { adb shell su -c "$*"; }
else
    echo "    [-] Not root and no su. Trying adb root..."
    timeout 5 adb root 2>/dev/null || true
    sleep 2
    UID_OUT=$(adb shell id -u 2>/dev/null | tr -d '\r' | head -1)
    if [[ "$UID_OUT" == "0" ]]; then
        echo "    [+] adb root succeeded."
        ADB() { adb shell "$@"; }
    else
        echo ""
        echo "[!] ERROR: Cannot gain root access."
        echo "    Try: run script from a root shell, or ensure"
        echo "    the device is in recovery mode."
        exit 1
    fi
fi

# --- Main logic ---
MOUNTED=false
PERSIST_DIR="/persist"

echo ""
echo "[*] Checking if $PERSIST_DIR is accessible..."
if ADB ls "$PERSIST_DIR/.foxs" 2>/dev/null | grep -q . 2>/dev/null; then
    echo "    [+] /persist is mounted and accessible."
else
    echo "    [-] /persist is NOT accessible."

    echo ""
    echo "[*] Searching for persist block device..."
    BLOCK=""
    for probe in \
        "/dev/block/bootdevice/by-name/persist" \
        "/dev/block/platform/*/by-name/persist" \
        "/dev/block/platform/*/*/by-name/persist"
    do
        echo "    Probing: $probe"
        BLOCK=$(ADB "for p in $probe; do [ -e \"\$p\" ] && echo \"\$p\" && break; done" 2>/dev/null | tr -d '\r' | head -1)
        [[ -n "$BLOCK" ]] && break
    done

    if [[ -z "$BLOCK" ]]; then
        echo "    -> Not found via path patterns. Trying blkid..."
        BLOCK=$(ADB "blkid 2>/dev/null | grep -i '\"persist\"' | cut -d: -f1" 2>/dev/null | tr -d '\r' | head -1)
    fi

    if [[ -z "$BLOCK" ]]; then
        echo ""
        echo "[!] ERROR: Could not locate persist partition."
        echo "    The password is likely in .foxs files only."
        echo "    Trying direct file cleanup instead..."
    else
        echo ""
        echo "    [+] Found persist block device: $BLOCK"

        # --- choose a safe mountpoint ---
        # Prefer /tmp because it always exists in both recovery and Android.
        PERSIST_DIR="/tmp/persist"
        echo ""
        echo "[*] Preparing mountpoint at $PERSIST_DIR ..."
        ADB "mkdir -p $PERSIST_DIR" 2>/dev/null || true

        # detect filesystem (ext4 is typical, but be robust)
        FSTYPE=$(ADB "blkid -o value -s TYPE $BLOCK 2>/dev/null" 2>/dev/null | tr -d '\r' | head -1)
        [[ -z "$FSTYPE" ]] && FSTYPE="ext4"   # fallback

        echo "    Mounting $BLOCK (type $FSTYPE) to $PERSIST_DIR ..."
        ADB "mount -t $FSTYPE $BLOCK $PERSIST_DIR" 2>/dev/null && RC=0 || RC=1

        # verify mount
        if ADB "grep -q ' $PERSIST_DIR ' /proc/mounts" 2>/dev/null; then
            echo "    [+] Mount successful."
            MOUNTED=true
        else
            echo "    [-] Mount failed. Trying with 'mount -o ro' ..."
            ADB "mount -t $FSTYPE -o ro $BLOCK $PERSIST_DIR" 2>/dev/null || true
            if ADB "grep -q ' $PERSIST_DIR ' /proc/mounts" 2>/dev/null; then
                echo "    [+] Read-only mount succeeded."
                MOUNTED=true
            else
                echo "    [-] Mount still failed. Will skip persist cleanup."
            fi
        fi
    fi
fi

if $MOUNTED; then
    echo ""
    echo "[*] Removing OrangeFox password/lock files from $PERSIST_DIR..."
    for f in .fsec .foxs; do
        path="$PERSIST_DIR/$f"
        line=$(ADB "ls -la '$path' 2>/dev/null" 2>/dev/null | tr -d '\r' | grep -v '^$' | head -1)
        if [[ -n "$line" ]]; then
            echo "    $line"
            ADB "rm -f '$path'" 2>/dev/null || true
            echo "    -> removed"
        else
            echo "    $path -- not found"
        fi
    done
fi

echo ""
echo "[*] Checking additional known paths..."
for loc in "/data/recovery/Fox/.foxs" "/data/recovery/Fox/.fsec"; do
    line=$(ADB "ls -la '$loc' 2>/dev/null" 2>/dev/null | tr -d '\r' | grep -v '^$' | head -1)
    if [[ -n "$line" ]]; then
        echo "    $line"
        ADB "rm -f '$loc'" 2>/dev/null || true
        echo "    -> removed"
    fi
done

echo ""
echo "[*] Scanning for stray copies across entire filesystem..."
echo "    Searching for .foxs files..."
while IFS= read -r path; do
    [[ -z "$path" ]] && continue
    line=$(ADB "ls -la '$path' 2>/dev/null" 2>/dev/null | tr -d '\r' | grep -v '^$' | head -1)
    if [[ -n "$line" ]]; then
        echo "    $line"
    else
        echo "    $path"
    fi
    ADB "rm -f '$path'" 2>/dev/null || true
    echo "    -> removed"
done < <(ADB "find / -name '.foxs' -type f 2>/dev/null" 2>/dev/null | tr -d '\r' | grep -v '^$' || true)

echo "    Searching for .fsec files..."
while IFS= read -r path; do
    [[ -z "$path" ]] && continue
    line=$(ADB "ls -la '$path' 2>/dev/null" 2>/dev/null | tr -d '\r' | grep -v '^$' | head -1)
    if [[ -n "$line" ]]; then
        echo "    $line"
    else
        echo "    $path"
    fi
    ADB "rm -f '$path'" 2>/dev/null || true
    echo "    -> removed"
done < <(ADB "find / -name '.fsec' -type f 2>/dev/null" 2>/dev/null | tr -d '\r' | grep -v '^$' || true)

# --- cleanup ---
if $MOUNTED; then
    echo ""
    echo "[*] Unmounting $PERSIST_DIR..."
    ADB "umount $PERSIST_DIR" 2>/dev/null || true
    ADB "rm -rf $PERSIST_DIR" 2>/dev/null || true
    echo "    [+] Cleaned up mount point."
fi

echo ""
echo "[*] Verifying..."
remaining=$(ADB "find / \( -name '.foxs' -o -name '.fsec' \) -type f 2>/dev/null" 2>/dev/null | tr -d '\r' | grep -v '^$' || true)
if [[ -z "$remaining" ]]; then
    echo "    [+] No remaining OrangeFox lock files found."
    echo ""
    echo "[*] Done. All OrangeFox lock files removed."
else
    echo "    [!] The following files still exist:"
    while IFS= read -r line; do
        echo "        $line"
    done <<< "$remaining"
fi
