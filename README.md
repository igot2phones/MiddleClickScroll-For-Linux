# MiddleClickScroll-For-Linux

Because obviously what everyone wants from a middle mouse click is random clipboard paste chaos instead of useful scrolling.

This script configures GNOME on Linux so holding the middle mouse button lets you scroll (instead of pasting primary selection everywhere).

## What this does

`middle-click-scroll.sh`:

1. Adds a udev hwdb rule to classify your mouse as a trackball (`ID_INPUT_TRACKBALL=1`)
2. Sets GNOME trackball middle-button scroll emulation to button `2`
3. Disables GTK middle-click primary paste

Result: hold middle click and move mouse to scroll.

> Note: this is **not** Windows-style "click once and glide" autoscroll. GNOME/Wayland does not provide that globally.

## Requirements

- Linux with GNOME (Wayland/X11)
- `bash`
- `gsettings`
- `systemd-hwdb`
- `sudo` access

## How to run

From the repository root:

```bash
chmod +x ./middle-click-scroll.sh
./middle-click-scroll.sh
```

The script will list pointing devices and ask you to pick your mouse.

### Run non-interactively by mouse name

```bash
./middle-click-scroll.sh --name "Logitech ERGO M575"
```

### Revert all changes

```bash
./middle-click-scroll.sh --revert
```

## Important usage notes

- Run the script as your **normal user** (do **not** run with `sudo`).
- The script uses `sudo` only where needed for `/etc/udev/hwdb.d/...`.
- You may need to unplug/replug the mouse (or reboot) after applying.

## Verify settings

Check GNOME values:

```bash
gsettings get org.gnome.desktop.peripherals.trackball scroll-wheel-emulation-button
gsettings get org.gnome.desktop.interface gtk-enable-primary-paste
```

Expected values:

- `scroll-wheel-emulation-button`: `uint32 2` (or `2`)
- `gtk-enable-primary-paste`: `false`

Check udev tagging (replace `eventX` with your device event node):

```bash
udevadm info /sys/class/input/eventX | grep TRACKBALL
```

Expected output includes:

```text
ID_INPUT_TRACKBALL=1
```

## Known limitations

- A quick middle click (without movement) can still register as a click in some apps.
- Electron apps (VS Code, Slack, Discord, etc.) may still handle middle-click paste themselves.
- Pointer speed/acceleration for this mouse may now live under GNOME trackball settings.
- Firefox supports native autoscroll: set `general.autoScroll=true` and `middlemouse.paste=false` in `about:config`.
