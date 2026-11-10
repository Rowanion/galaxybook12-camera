#!/bin/bash
# Install the Galaxy Book 12 camera kernel modules (DKMS package galaxybook12-camera)
# for every installed kernel, plus the post-network rebuild service.
set -euo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
"$HERE/common/install-dkms.sh" galaxybook12-camera "$HERE/kernel"
echo
echo "REBOOT required (the SONY258A<->INT3472 ACPI dependency is built only"
echo "during device enumeration). Verify after reboot:"
echo "  sudo dmesg | grep -E 'Connected .* cameras|DW9806B'"
echo "  cam -l"
