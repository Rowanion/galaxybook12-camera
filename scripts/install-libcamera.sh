#!/bin/bash
# Rebuild Fedora's libcamera with the IMX241 front-camera sensor helper (patch 0004),
# install it, and versionlock so a dnf update can't revert the patch.
#
# NOTE: this is a from-source RPM rebuild (pulls ~build deps, downloads the SRPM,
# compiles libcamera — several minutes). It is a point-in-time rebuild: when a
# newer Fedora libcamera is released you must re-run it (see "updates" below).
# The spec edits target Fedora's current libcamera spec layout; a future spec
# restructure may need tweaking.
set -euo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PATCH_SRC="$HERE/libcamera/0004-libipa-add-imx241-sensor-helper.patch"
PATCH_BN="$(basename "$PATCH_SRC")"
[ -f "$PATCH_SRC" ] || { echo "ERROR: missing $PATCH_SRC" >&2; exit 1; }

echo "== build tooling + libcamera build deps =="
sudo dnf install -y rpm-build rpmdevtools dnf5-plugins
sudo dnf builddep -y libcamera
rpmdev-setuptree

echo "== fetch + unpack the source RPM =="
cd ~
dnf download --source libcamera || sudo dnf download --source libcamera --enablerepo='*-source'
rpm -Uvh --force ~/libcamera-*.src.rpm
cp "$PATCH_SRC" ~/rpmbuild/SOURCES/

SPEC=~/rpmbuild/SPECS/libcamera.spec

echo "== patch the spec (idempotent) =="
if ! grep -q "$PATCH_BN" "$SPEC"; then
  if grep -q '^Patch[0-9]' "$SPEC"; then
    last=$(grep -n '^Patch[0-9]' "$SPEC" | tail -1 | cut -d: -f1)
    sed -i "${last}a Patch99: $PATCH_BN" "$SPEC"
  else
    sed -i "0,/^Source[0-9]*:/s//&\nPatch99: $PATCH_BN/" "$SPEC"
  fi
fi
# bump release so our build supersedes stock and survives updates (idempotent)
sed -i -E 's/^Release:[[:space:]]*([0-9]+)%\{\?dist\}$/Release: \1%{?dist}.gb12cam/' "$SPEC"
CL=$(LC_ALL=C date +'%a %b %d %Y')
grep -q 'IMX241 libipa sensor helper' "$SPEC" || \
  sed -i "/^%changelog$/a * $CL galaxybook12-camera - add IMX241 libipa sensor helper (patch 0004)\n" "$SPEC"

echo "== verify patch applies, then build (skip test suite) =="
rpmbuild -bp "$SPEC"
rpmbuild -bb --nocheck "$SPEC"

echo "== install rebuilt packages =="
# always install the three essentials from our build, plus any other
# libcamera subpackage already present, so versions stay consistent
want=(libcamera libcamera-ipa libcamera-tools)
for p in $(rpm -qa --qf '%{NAME}\n' | grep -E '^libcamera-(gstreamer|v4l2|qcam|devel)$|^python3-libcamera$'); do
  want+=("$p")
done
rpms=()
for p in "${want[@]}"; do
  f=$(ls ~/rpmbuild/RPMS/x86_64/${p}-*.gb12cam.*.rpm 2>/dev/null) && rpms+=("$f")
done
sudo dnf install -y "${rpms[@]}"

echo "== versionlock so updates can't drop the patch =="
sudo dnf versionlock add $(rpm -qa --qf '%{NAME}\n' | grep -E '^libcamera|^python3-libcamera') || true

echo
echo "Done. 'cam -l' should list both the back and front cameras."
echo "To move to a newer libcamera later:"
echo "  sudo dnf versionlock delete 'libcamera*' && sudo dnf update 'libcamera*'"
echo "  then re-run this script against the new SRPM."
