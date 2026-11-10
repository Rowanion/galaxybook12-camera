#!/bin/bash
# One-shot installer for the Galaxy Book 12 (SM-W720) camera stack:
#   1. kernel modules via DKMS (rear + front sensors, autofocus)  -> survives kernel updates
#   2. patched libcamera (front-camera IMX241 sensor helper)      -> versionlocked
#   3. PipeWire libcamera plugin (so desktop apps see the cameras)
# Run on the target tablet. A reboot is required afterwards.
set -euo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

echo "######## 1/3  Kernel modules (DKMS) ########"
"$HERE/scripts/install-kernel-dkms.sh"

echo "######## 2/3  libcamera (front-camera helper) ########"
"$HERE/scripts/install-libcamera.sh"

echo "######## 3/3  PipeWire plugin ########"
sudo dnf install -y pipewire-plugin-libcamera || true

cat <<'MSG'

================================================================
All three layers installed.

REBOOT NOW — the kernel modules load and the SONY258A<->INT3472
ACPI dependency is built only during device enumeration. PipeWire
picks up both cameras automatically on the fresh session.

After reboot, verify:
  sudo dmesg | grep -E 'Connected .* cameras|DW9806B'
  cam -l                       # -> back camera + front camera
  wpctl status                 # -> Built-in Back/Front Camera under Video
================================================================
MSG
