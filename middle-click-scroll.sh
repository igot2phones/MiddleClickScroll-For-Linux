#!/usr/bin/env bash
#
# middle-click-scroll.sh — make the middle mouse button scroll instead of paste
# Target: Ubuntu 26.04 / GNOME on Wayland
#
# What it does:
#   1. Adds a udev hwdb rule so your mouse is classified as a trackball
#      (this is what unlocks GNOME's scroll-wheel-emulation setting)
#   2. Binds the middle button (button 2) to scroll-drag
#   3. Disables middle-click primary-selection paste in GTK apps
#
# Result: hold the middle button and move the mouse to scroll.
# (Not Windows-style click-once-and-glide autoscroll — GNOME/Wayland can't do that.)
#
# Usage:
#   ./middle-click-scroll.sh              # interactive: pick your mouse from a list
#   ./middle-click-scroll.sh --name "Logitech ERGO M575"
#   ./middle-click-scroll.sh --revert     # undo everything

set -euo pipefail

HWDB_FILE=/etc/udev/hwdb.d/70-middle-click-scroll.hwdb

c_red=$'\033[31m'; c_grn=$'\033[32m'; c_cya=$'\033[36m'; c_yel=$'\033[33m'; c_off=$'\033[0m'
info() { printf '%s==>%s %s\n' "$c_cya" "$c_off" "$*"; }
ok()   { printf '%s ok %s %s\n' "$c_grn" "$c_off" "$*"; }
warn() { printf '%s!!!%s %s\n' "$c_yel" "$c_off" "$*"; }
die()  { printf '%serror:%s %s\n' "$c_red" "$c_off" "$*" >&2; exit 1; }

if [[ ${EUID} -eq 0 ]]; then
  die "Run as your normal user, not with sudo. The script calls sudo itself where it needs to.
       (gsettings must run as you, or the settings land in root's profile and do nothing.)"
fi

command -v gsettings >/dev/null || die "gsettings not found — is this a GNOME session?"
command -v systemd-hwdb >/dev/null || die "systemd-hwdb not found."

# ---------------------------------------------------------------- revert ----
revert() {
  info "Removing $HWDB_FILE"
  sudo rm -f "$HWDB_FILE"
  sudo systemd-hwdb update
  sudo udevadm trigger --subsystem-match=input --action=change || true

  info "Resetting GNOME settings to their defaults"
  gsettings reset org.gnome.desktop.peripherals.trackball scroll-wheel-emulation-button
  gsettings reset org.gnome.desktop.interface gtk-enable-primary-paste

  ok "Reverted. Unplug and replug the mouse (or reboot) to finish."
  warn "Note: recent GNOME versions ship gtk-enable-primary-paste=false by default,"
  warn "so 'reset' may leave middle-click paste off. To force it back on:"
  echo "      gsettings set org.gnome.desktop.interface gtk-enable-primary-paste true"
  exit 0
}

# ------------------------------------------------------------ arg parsing ---
MOUSE_NAME=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --revert|-r) revert ;;
    --name|-n)   MOUSE_NAME="${2:-}"; [[ -n $MOUSE_NAME ]] || die "--name needs a value"; shift 2 ;;
    --help|-h)   sed -n '3,18p' "$0"; exit 0 ;;
    *)           die "unknown option: $1" ;;
  esac
done

# ------------------------------------------------------ device detection ----
# Parse /proc/bus/input/devices for anything exposing a mouse handler.
# Deliberately avoids `libinput list-devices` so detection needs no sudo.
detect_devices() {
  awk '
    /^N: Name=/    { name=$0; sub(/^N: Name="/,"",name); sub(/"$/,"",name) }
    /^H: Handlers=/{ h=$0; ev=""; if (match(h, /event[0-9]+/)) ev=substr(h,RSTART,RLENGTH)
                     if (h ~ /mouse[0-9]/ && ev != "" && name != "") print name "\t" ev }
    /^$/           { name=""; }
  ' /proc/bus/input/devices
}

EVENT_NODE=""
if [[ -z $MOUSE_NAME ]]; then
  mapfile -t rows < <(detect_devices)
  [[ ${#rows[@]} -gt 0 ]] || die "No pointing devices found in /proc/bus/input/devices."

  echo
  info "Pointing devices found:"
  for i in "${!rows[@]}"; do
    printf '  %2d) %s  (%s)\n' "$((i+1))" "${rows[$i]%%$'\t'*}" "${rows[$i]##*$'\t'}"
  done
  echo
  read -rp "Which one is your mouse? [1-${#rows[@]}] " choice
  [[ $choice =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#rows[@]} )) || die "Invalid choice."
  sel="${rows[$((choice-1))]}"
  MOUSE_NAME="${sel%%$'\t'*}"
  EVENT_NODE="${sel##*$'\t'}"
else
  while IFS=$'\t' read -r n e; do
    if [[ $n == "$MOUSE_NAME" ]]; then EVENT_NODE="$e"; fi
  done < <(detect_devices)
  [[ -n $EVENT_NODE ]] || warn "Couldn't find '$MOUSE_NAME' plugged in right now — continuing anyway."
fi

case "$MOUSE_NAME" in
  *[\*\?\[]*) warn "Device name contains glob characters; the hwdb match may misbehave." ;;
esac

echo
info "Configuring: ${c_grn}${MOUSE_NAME}${c_off}"

# ------------------------------------------------------------ hwdb rule -----
# The value line MUST be indented by exactly one space — hwdb is picky.
info "Writing $HWDB_FILE (needs sudo)"
sudo tee "$HWDB_FILE" >/dev/null <<EOF
# Written by middle-click-scroll.sh
# Classifies this mouse as a trackball so GNOME applies
# org.gnome.desktop.peripherals.trackball settings to it.
mouse:*:name:${MOUSE_NAME}:*
 ID_INPUT_TRACKBALL=1
EOF

info "Rebuilding the hardware database"
sudo systemd-hwdb update
sudo udevadm trigger --subsystem-match=input --action=change || true

# ------------------------------------------------------------- gsettings ----
info "Binding middle button to scroll"
gsettings set org.gnome.desktop.peripherals.trackball scroll-wheel-emulation-button 2

info "Disabling middle-click paste in GTK apps"
gsettings set org.gnome.desktop.interface gtk-enable-primary-paste false

# ---------------------------------------------------------- verification ----
echo
info "Verifying"
applied=0
if [[ -n $EVENT_NODE ]] && udevadm info "/sys/class/input/$EVENT_NODE" 2>/dev/null | grep -q 'ID_INPUT_TRACKBALL=1'; then
  ok "$MOUSE_NAME is now classified as a trackball"
  applied=1
else
  warn "Trackball classification not live yet — udev won't always re-tag a device in place."
  warn "Unplug and replug the mouse (or reboot), then re-check with:"
  echo "      udevadm info /sys/class/input/${EVENT_NODE:-eventN} | grep TRACKBALL"
fi

btn=$(gsettings get org.gnome.desktop.peripherals.trackball scroll-wheel-emulation-button)
pst=$(gsettings get org.gnome.desktop.interface gtk-enable-primary-paste)
[[ $btn == "uint32 2" || $btn == "2" ]] && ok "scroll-wheel-emulation-button = $btn" || warn "unexpected: $btn"
[[ $pst == "false" ]] && ok "gtk-enable-primary-paste = false" || warn "unexpected: $pst"

echo
if (( applied )); then
  ok "Done. Hold the middle button and move the mouse to scroll."
else
  ok "Done — replug the mouse to activate."
fi
cat <<'NOTES'

Worth knowing:
  * A quick middle-click (press+release, no movement) still registers as a click.
    That's why primary paste is disabled too.
  * Electron apps (VS Code, Slack, Discord) do their own clipboard handling and
    will keep pasting on middle-click regardless.
  * GNOME now treats this mouse as a trackball, so its pointer speed / acceleration
    live under org.gnome.desktop.peripherals.trackball, not .mouse.
  * Firefox does real autoscroll: in about:config set
    general.autoScroll = true  and  middlemouse.paste = false
  * Undo everything with:  ./middle-click-scroll.sh --revert
NOTES
