# Samsung Galaxy Book 12 (SM-W720) — Camera enablement on Fedora

Enables **both** internal cameras on the Samsung Galaxy Book 12 under Linux:

| Position | Sensor | ACPI ID | I²C addr | Notes |
|---|---|---|---|---|
| Rear  | Sony IMX258 (13 MP) + DW9806B AF | `SONY258A` | `2-001a` (AF `2-000c`) | works on stock libcamera |
| Front | Sony IMX241 (5 MP) | `INT347F` | `3-0037` | needs libcamera patch `0004` |

The imaging pipeline is **Intel IPU3** (CIO2 + ImgU). Tested on Fedora 44,
kernels `7.2.15` and `7.3.3`, libcamera `0.7.1`, GNOME/Wayland.

The fixes are ported from
[fxjosemi/Samsung-Galaxy-Book-12-Linux](https://github.com/fxjosemi/Samsung-Galaxy-Book-12-Linux).
> **Model note:** earlier versions of this repo said "Galaxy Book 10.6
> (SM-W620)". The development unit is in fact an **SM-W720 (Galaxy Book 12)**:
> 11.9″ 2160×1440 panel, Core i5-7200U, 39 Wh battery, 13 MP rear camera,
> codec `144d:c14f`, board `SM-W720`. Nothing here has been tested on a 10.6.

This repo
packages them for Fedora: the kernel side as a **DKMS** module so it survives
kernel updates, and the userspace side as a **rebuilt libcamera RPM**.

## Layout
```
install.sh  one-shot: kernel DKMS + patched libcamera + PipeWire plugin
kernel/     DKMS package: dkms.conf, dkms-make.sh, 5 patches (+ 7.3+ variant), dw9806b.c, imx241.c, imx241-regs.h
common/     shared with the audio/accel repos: kernel-source helper, DKMS (un)installer,
            galaxybook-dkms-catchup service (rebuilds after kernel updates)
libcamera/  0004-libipa-add-imx241-sensor-helper.patch + build guide (front-camera sensor helper)
scripts/    install-kernel-dkms.sh, install-libcamera.sh, uninstall-kernel-dkms.sh
```

## Quick start
```bash
./install.sh        # all three layers (asks for sudo); several minutes (libcamera compiles)
sudo reboot
```
Then `cam -l` lists both cameras. The individual steps are below if you prefer to
run them one at a time.

**What persists:**
- **Kernel modules** survive reboots *and* kernel updates — DKMS rebuilds them
  for each new kernel automatically (needs `kernel-devel`; Secure Boot off or
  MOK enrolled). If the build can't run at that moment (no network yet at
  early boot, offline `dnf system-upgrade`), `galaxybook-dkms-catchup.service`
  builds it once the network is up and asks for a reboot via a notification.
- **Patched libcamera** survives reboots and kernel updates (it's userspace), and
  is **versionlocked** so a `dnf update` can't revert it. It is a point-in-time
  rebuild — when you want a newer libcamera, unlock, update, and re-run
  `scripts/install-libcamera.sh`.
- The **rear** camera needs only the kernel layer (stock libcamera works); the
  **front** camera additionally needs the patched libcamera.

## Prerequisites
- Secure Boot **disabled** (`mokutil --sb-state`), or enroll the DKMS MOK key.
- `sudo dnf install -y dkms kernel-devel-$(uname -r) make patch gcc binutils elfutils-libelf-devel curl`
- Internet once per new kernel version — the build fetches the matching
  mainline kernel source from kernel.org (cached in
  `/var/cache/galaxybook-kernel-src` afterwards).

## Part 1 — Kernel modules (DKMS)
```bash
./scripts/install-kernel-dkms.sh
sudo reboot
```
Installs DKMS module `galaxybook12-camera/2.0` for **every** installed kernel
that has `kernel-devel`. For each kernel it takes the matching
`linux-<ver>.tar.xz`, extracts the stock `imx258`, `ipu-bridge` and `int3472`
sources, applies the five patches **with zero fuzz** (so upstream drift fails
loudly instead of patching the wrong spot), and builds five modules into
`/lib/modules/<ver>/extra/`: `imx258`, `imx241`, `dw9806b`, `ipu-bridge`,
`intel_skl_int3472_discrete`. Kernel 7.3 changed the int3472 GPIO map
(`.hid` → `.hids`); the build detects that and uses
`kernel/patches/variants/hids/`. The installer builds everything first and
only replaces the installed version when all builds succeed.

A reboot is **mandatory**: the `SONY258A`↔`INT3472:01` ACPI dependency is only
built during device enumeration.

> **Why the bridge is `ipu-bridge.ko` (hyphen):** it must match the in-tree
> module filename so DKMS archives/shadows the stock
> `kernel/.../ipu-bridge.ko.xz`. Built as `ipu_bridge.ko` (underscore), the
> stock bridge stays in place and `depmod` loads it instead — giving
> "Connected 0 cameras". See the note in `kernel/dkms.conf`.

Verify:
```bash
sudo dmesg | grep -E 'Connected .* cameras|Found supported sensor|DW9806B'
# -> Found supported sensor INT347F:00 / SONY258A:00 / Connected 2 cameras / DW9806B ... detected
```

## Part 2 — libcamera userspace (front camera)
Stock libcamera has no IMX241 sensor helper, so the IPU3 IPA fails to
initialise for the front camera and it drops out of `cam -l`. Rebuild Fedora's
libcamera with `libcamera/0004-libipa-add-imx241-sensor-helper.patch` — see
[libcamera/README.md](libcamera/README.md). The rear camera works without this;
only the front camera requires it.

## Part 3 — PipeWire (desktop apps)
```bash
systemctl --user restart wireplumber pipewire pipewire-pulse
wpctl status   # both "Built-in Back/Front Camera" appear under Video > Sources
```

## Verification
```bash
cam -l                                            # lists both cameras
cam -c 1 --capture=10 --file=/tmp/rear_#.bin      # rear
cam -c 2 --capture=10 --file=/tmp/front_#.bin     # front
# view one NV12 720p frame:
ffmpeg -y -f rawvideo -pix_fmt nv12 -s 1280x720 \
  -i /tmp/rear_cam0-stream0-000005.bin -frames:v 1 /tmp/rear.png
```

## Uninstall
```bash
./scripts/uninstall-kernel-dkms.sh
sudo reboot
# libcamera: sudo dnf versionlock delete 'libcamera*' && \
#            sudo dnf reinstall libcamera libcamera-ipa libcamera-tools
```

## Caveats
- Images are **uncalibrated** (generic AE/AWB) — no `imx258.yaml`/`imx241.yaml`
  tuning files are shipped. Functional, but not color/exposure-tuned.
- A kernel update made **offline** is built by `galaxybook-dkms-catchup` once
  the network is up; a reboot is then needed (you get a desktop notification).
- Not included (optional upstream extras): kernel autofocus/resolution quality
  patches, per-module tuning calibration, OBS PipeWire patches.

## Credits
Kernel patches, `dw9806b.c`, `imx241.c`/`imx241-regs.h`, and the libcamera
`0004` helper are from
[fxjosemi/Samsung-Galaxy-Book-12-Linux](https://github.com/fxjosemi/Samsung-Galaxy-Book-12-Linux).
This repo adds the Fedora DKMS packaging and build scripts.

## License
[GPL-2.0](LICENSE). The kernel sources and patches are derived from the Linux
kernel and the upstream repo above and carry `SPDX-License-Identifier: GPL-2.0`.
The libcamera patch under `libcamera/` modifies libcamera sources and follows
upstream libcamera's license (LGPL-2.1); applying it produces LGPL-2.1 binaries.
