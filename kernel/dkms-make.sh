#!/bin/bash
# Build the Galaxy Book 12 camera modules for one kernel, from that
# kernel's own vanilla source plus our patches (shared Galaxy Book DKMS helper:
# cached source, zero-fuzz patching, clear offline failure).
set -euo pipefail
KVER="${1:?kernelver required}"
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
HEADERS="/lib/modules/$KVER/build"
JOBS="${JOBS:-$(nproc)}"
# shellcheck source=/dev/null
. "${GB_HELPER:-/usr/local/lib/galaxybook-dkms/kernel-src.sh}"

[ -d "$HEADERS" ] || { echo "ERROR: no kernel headers at $HEADERS (install kernel-devel-$KVER)" >&2; exit 1; }
SRC="$(gb_kernel_src "$KVER" \
  drivers/media/i2c/imx258.c \
  drivers/media/pci/intel/ipu-bridge.c \
  drivers/platform/x86/intel/int3472/discrete.c \
  drivers/platform/x86/intel/int3472/discrete_quirks.c \
  drivers/platform/x86/intel/int3472/clk_and_regulator.c \
  drivers/platform/x86/intel/int3472/led.c)"

OUT="$HERE/out"; rm -rf "$OUT"
M="$OUT/drivers/media/i2c"; B="$OUT/drivers/media/pci/intel"
I="$OUT/drivers/platform/x86/intel/int3472"
mkdir -p "$M" "$B" "$I"
cp "$SRC/drivers/media/i2c/imx258.c" "$M/imx258.c"
cp "$HERE/dw9806b.c" "$M/dw9806b.c"
cp "$HERE/imx241.c" "$HERE/imx241-regs.h" "$M/"
cp "$SRC/drivers/media/pci/intel/ipu-bridge.c" "$B/ipu-bridge.c"
cp "$SRC"/drivers/platform/x86/intel/int3472/{discrete,discrete_quirks,clk_and_regulator,led}.c "$I/"

# Kernel 7.3 turned int3472_gpio_map.hid into a NULL-terminated .hids list.
VARIANT=""
grep -q 'const char \* const \*hids;' "$I/discrete.c" && VARIANT="$HERE/patches/variants/hids"
gb_apply_patches "$HERE" "$OUT" "$VARIANT"

printf '%s\n' 'obj-m += imx258.o' 'obj-m += imx241.o' 'obj-m += dw9806b.o' > "$M/Makefile"
printf '%s\n' 'obj-m += ipu-bridge.o' > "$B/Makefile"
printf '%s\n' 'obj-m += intel_skl_int3472_discrete.o' \
  'intel_skl_int3472_discrete-y := discrete.o discrete_quirks.o clk_and_regulator.o led.o' > "$I/Makefile"

make -C "$HEADERS" M="$M" modules -j"$JOBS" CONFIG_DEBUG_INFO_BTF_MODULES=
make -C "$HEADERS" M="$B" modules -j"$JOBS" CONFIG_DEBUG_INFO_BTF_MODULES=
make -C "$HEADERS" M="$I" modules -j"$JOBS" CONFIG_DEBUG_INFO_BTF_MODULES=
echo "Built 5 camera modules for $KVER"
