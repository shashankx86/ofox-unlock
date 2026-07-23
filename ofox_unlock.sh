#!/usr/bin/env bash
# Remove OrangeFox recovery lock/password from device.
# Removes .fsec (master config), .foxs (binary config), and verifies.
set -e

echo "[*] Removing OrangeFox password/lock files..."

echo "    Removing /persist/.fsec (master config)..."
adb shell rm -f /persist/.fsec 2>/dev/null || true

echo "    Removing .foxs files..."
adb shell "find / \( -name '.foxs' -o -name '.fsec' \) -type f -exec rm -f {} \;" 2>/dev/null || true

echo ""
echo "[*] Verifying..."
remaining=$(adb shell "find / \( -name '.foxs' -o -name '.fsec' \) -type f 2>/dev/null" 2>/dev/null | tr -d '\r' | grep -v '^$' || true)
if [[ -z "$remaining" ]]; then
    echo "[*] Done. All OrangeFox lock files removed."
else
    echo "[!] Remaining:"
    echo "$remaining"
fi
