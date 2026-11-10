#!/bin/bash
# Remove the Galaxy Book 12 camera DKMS module (restores stock in-tree modules).
set -euo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
"$HERE/common/uninstall-dkms.sh" galaxybook12-camera
