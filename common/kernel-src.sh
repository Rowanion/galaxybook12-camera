# Shared helper for the Galaxy Book DKMS packages (sourced by each dkms-make.sh).
# Installed to /usr/local/lib/galaxybook-dkms/kernel-src.sh.
#
#   SRC="$(gb_kernel_src <kernelver> <path-in-tree>...)"
#
# Returns a directory holding vanilla kernel.org source for that kernel's
# upstream version, with at least the requested files/dirs extracted. The
# tarball is downloaded once and cached, so later rebuilds need no network.
# Fails with a clear message when offline; galaxybook-dkms-catchup.service
# retries once the network is up.

GB_CACHE="${GB_CACHE:-/var/cache/galaxybook-kernel-src}"

gb_kernel_src() {
  local kver="$1"; shift
  local ks="${kver%%-*}"
  local major="${ks%%.*}"
  local archive="$GB_CACHE/linux-$ks.tar.xz"
  local src="$GB_CACHE/linux-$ks"
  local url="https://cdn.kernel.org/pub/linux/kernel/v${major}.x/linux-$ks.tar.xz"
  local p missing=()

  mkdir -p "$GB_CACHE" || return 1
  exec 9>"$GB_CACHE/.lock"
  flock 9

  for p in "$@"; do [ -e "$src/$p" ] || missing+=("linux-$ks/$p"); done
  if [ ${#missing[@]} -gt 0 ]; then
    if [ ! -f "$archive" ]; then
      echo "Fetching linux-$ks source from $url" >&2
      if ! curl --fail --location --silent --show-error --retry 3 --connect-timeout 15 \
           -o "$archive.part" "$url" >&2; then
        rm -f "$archive.part"
        echo "ERROR: could not download linux-$ks source (no network yet?)." >&2
        echo "       galaxybook-dkms-catchup.service will build this once the network is up." >&2
        flock -u 9; return 1
      fi
      mv "$archive.part" "$archive"
    fi
    if ! tar -xJf "$archive" -C "$GB_CACHE" "${missing[@]}" >&2; then
      echo "ERROR: $archive is corrupt or incomplete; deleting it so the next attempt re-downloads." >&2
      rm -rf "$archive" "$src"
      flock -u 9; return 1
    fi
  fi
  flock -u 9
  echo "$src"
}

# Apply every patches/000*.patch with zero fuzz. If a patches/variants/<name>/
# directory is given and holds a file of the same name, that variant is used.
gb_apply_patches() {   # gb_apply_patches <pkgdir> <outdir> [variant-dir]
  local here="$1" out="$2" variant="${3:-}" p
  for p in "$here"/patches/000*.patch; do
    [ -e "$p" ] || continue
    if [ -n "$variant" ] && [ -f "$variant/$(basename "$p")" ]; then
      p="$variant/$(basename "$p")"
    fi
    echo "Applying ${p#"$here"/}"
    patch -d "$out" -p1 --fuzz=0 --no-backup-if-mismatch < "$p" || return 1
  done
}
