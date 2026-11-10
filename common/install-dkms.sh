#!/bin/bash
# Shared DKMS installer of the Galaxy Book 12 driver repos (camera, audio,
# accel). Identical copy in each repo; called by that repo's install script:
#   common/install-dkms.sh <dkms-package-name> <package-dir-with-dkms.conf>
#
# - builds the package for EVERY installed kernel that has kernel-devel,
#   from that kernel's own vanilla kernel.org source plus the repo's patches;
# - only if all builds succeed: removes other versions of the package and
#   installs the new one (on any failure, the installed version is untouched);
# - installs the shared source helper and galaxybook-dkms-catchup (rebuilds
#   after kernel updates once the network is up, notifies on failure).
set -euo pipefail
[ "$(id -u)" = 0 ] || exec sudo "$0" "$@"
NAME="${1:?dkms package name}"
PKG="$(cd -- "${2:?package dir}" && pwd)"
COMMON="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
VER="$(sed -n 's/^PACKAGE_VERSION="\(.*\)"/\1/p' "$PKG/dkms.conf")"
[ -n "$VER" ] || { echo "no PACKAGE_VERSION in $PKG/dkms.conf"; exit 1; }
CACHE=/var/cache/galaxybook-kernel-src

kernels() {   # installed kernels with kernel-devel
  local d; for d in /lib/modules/*/; do
    [ -e "$d/vmlinuz" ] && [ -e "$d/build/Makefile" ] && basename "$d"
  done; return 0
}

echo "==> Build dependencies"
need=()
for p in dkms make gcc patch curl tar xz "kernel-devel-$(uname -r)"; do
  rpm -q "$p" >/dev/null 2>&1 || need+=("$p")
done
[ ${#need[@]} -eq 0 ] || dnf install -y "${need[@]}"

echo "==> Shared helper, source cache, catch-up service"
install -d /usr/local/lib/galaxybook-dkms
install -m 644 "$COMMON/kernel-src.sh" /usr/local/lib/galaxybook-dkms/
mkdir -p "$CACHE"
if [ -d /var/cache/galaxybook12-camera ]; then            # pre-2.0 camera cache
  for t in /var/cache/galaxybook12-camera/linux-*.tar.xz; do
    [ -e "$t" ] && [ ! -e "$CACHE/$(basename "$t")" ] && mv "$t" "$CACHE/"
  done
  rm -rf /var/cache/galaxybook12-camera
fi
systemctl disable --now galaxybook12-camera-catchup.path galaxybook12-camera-catchup.service 2>/dev/null || true
rm -f /etc/systemd/system/galaxybook12-camera-catchup.{service,path} /usr/local/sbin/galaxybook12-camera-catchup
install -m 755 "$COMMON/galaxybook-dkms-catchup" /usr/local/sbin/
install -m 644 "$COMMON/galaxybook-dkms-catchup.service" "$COMMON/galaxybook-dkms-catchup.path" /etc/systemd/system/
restorecon -R /usr/local/lib/galaxybook-dkms "$CACHE" /usr/local/sbin/galaxybook-dkms-catchup \
  /etc/systemd/system/galaxybook-dkms-catchup.* 2>/dev/null || true
systemctl daemon-reload
systemctl enable galaxybook-dkms-catchup.service galaxybook-dkms-catchup.path
systemctl start galaxybook-dkms-catchup.path

echo "==> Staging $NAME/$VER"
dst="/usr/src/$NAME-$VER"; rm -rf "$dst"; mkdir -p "$dst"
cp -r "$PKG/." "$dst/"; rm -rf "$dst/out"; chmod +x "$dst/dkms-make.sh"
# (no "| grep -q" under pipefail: grep exits early, dkms gets SIGPIPE, the pipe "fails")
[ -n "$(dkms status -m "$NAME" -v "$VER" 2>/dev/null)" ] || dkms add -m "$NAME" -v "$VER"

echo "==> Building $NAME/$VER for every kernel (nothing replaced yet)"
fail=0
for k in $(kernels); do
  echo "--- $k"
  dkms build --force -m "$NAME" -v "$VER" -k "$k" >/dev/null 2>&1 || {
    echo "!! FAILED for $k  (log: /var/lib/dkms/$NAME/$VER/build/make.log)"; fail=1; }
done
if [ $fail = 1 ]; then
  echo "Aborting: the currently installed version of $NAME was NOT touched."
  exit 1
fi

echo "==> Installing (each install regenerates the initramfs images; this is slow)"
for v in $(dkms status -m "$NAME" 2>/dev/null | sed -n "s|^$NAME/\([^,:]*\)[,:].*|\1|p" | sort -u); do
  [ "$v" = "$VER" ] && continue
  echo "    removing old $NAME/$v"
  dkms remove -m "$NAME" -v "$v" --all >/dev/null || echo "!! could not remove $NAME/$v"
done
for k in $(kernels); do dkms install --force -m "$NAME" -v "$VER" -k "$k" >/dev/null; done

dkms status -m "$NAME"
echo "Done: $NAME/$VER. Reboot once to load it."
