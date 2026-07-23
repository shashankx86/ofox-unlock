Removed OrangeFox builtin password/lock.

## Requirements

One of the following is required:

1. **Rooted device** — enable usb debugging, grant root to the shell via `adb root` (or 'adb shell' then 'su'), then run the script.
2. **alt recovery** (like TWRP, PBRP) — boot into recovery, go
   to **Mount** and mount *all* available partitions (system, vendor, data,
   persist, etc.), then run the script.

On Windows, USB drivers for the device must be installed and ADB must be
reachable from `PATH`. (i.e. adb should be installed)

On Linux/Mac, Install adb using your package manager.

## Usage

Connect the device, open a terminal and:

```bash
# Linux / macOS
./ofox_unlock.sh

# Windows (double-click or from cmd)
ofox_unlock.bat
```
