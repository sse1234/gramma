#!/usr/bin/env bash
# Renders app/linux/packaging/aur/PKGBUILD.in for a release.
# Usage: tool/render-pkgbuild.sh <version> <dist dir with the linux tarballs> <out dir>
#
# Writes <out dir>/PKGBUILD, ready for `makepkg -si` on Arch Linux and for
# publishing to the AUR as gramma-bin.
set -euo pipefail
version="$1"; dist="$2"; out="$3"
root="$(cd "$(dirname "$0")/.." && pwd)"

sum() { sha256sum "$1" | cut -d' ' -f1; }
x64="$(sum "$dist/gramma-$version-linux-x64.tar.gz")"
arm64="$(sum "$dist/gramma-$version-linux-arm64.tar.gz")"

mkdir -p "$out"
sed -e "s/@VERSION@/$version/" \
    -e "s/@SHA256_X64@/$x64/" \
    -e "s/@SHA256_ARM64@/$arm64/" \
    "$root/app/linux/packaging/aur/PKGBUILD.in" > "$out/PKGBUILD"
echo "rendered $out/PKGBUILD for $version"
