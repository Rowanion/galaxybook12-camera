#!/bin/bash
# Shared DKMS uninstaller of the Galaxy Book 12 driver repos (camera, audio,
# accel). Identical copy in each repo:  common/uninstall-dkms.sh <dkms-package-name>
# Removes every version of the package (the stock kernel modules are used
# again after a reboot). When none of the three packages is left, the shared
# helper, source cache and catch-up service are removed too.
set -euo pipefail
[ "$(id -u)" = 0 ] || exec sudo "$0" "$@"
NAME="${1:?dkms package name}"
ALL=(galaxybook12-camera alc298-galaxybook st-accel-sam0201)

for v in $(dkms status -m "$NAME" 2>/dev/null | sed -n "s|^$NAME/\([^,:]*\)[,:].*|\1|p" | sort -u); do
  echo "removing $NAME/$v"; dkms remove -m "$NAME" -v "$v" --all >/dev/null || true
done
rm -rf /usr/src/"$NAME"-*

left=0
for n in "${ALL[@]}"; do [ -n "$(dkms status -m "$n" 2>/dev/null)" ] && left=1; done
if [ $left = 0 ]; then
  echo "no Galaxy Book DKMS package left: removing shared helper, cache, catch-up service"
  systemctl disable --now galaxybook-dkms-catchup.path galaxybook-dkms-catchup.service 2>/dev/null || true
  rm -f /etc/systemd/system/galaxybook-dkms-catchup.{service,path} /usr/local/sbin/galaxybook-dkms-catchup
  rm -rf /usr/local/lib/galaxybook-dkms /var/cache/galaxybook-kernel-src
  systemctl daemon-reload
fi
echo "Removed $NAME. Reboot to use the stock kernel modules."
