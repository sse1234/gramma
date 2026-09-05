#!/usr/bin/env bash
# Packages the Linux release bundle as a tarball and an AppImage.
# Usage: tool/package-linux.sh <version> <arch: x64|arm64> <out dir>
set -euo pipefail
version="$1"; arch="$2"; out="$3"
root="$(cd "$(dirname "$0")/.." && pwd)"
bundle="$root/app/build/linux/$arch/release/bundle"
[ -x "$bundle/gramma" ] || { echo "no bundle at $bundle" >&2; exit 1; }
mkdir -p "$out"

tar -C "$(dirname "$bundle")" --transform "s,^bundle,gramma-$version," \
    -czf "$out/gramma-$version-linux-$arch.tar.gz" bundle

appdir="$(mktemp -d)/gramma.AppDir"
mkdir -p "$appdir/usr/bin"
cp -r "$bundle"/. "$appdir/usr/bin/"
cp "$root/app/linux/packaging/io.sse.gramma.desktop" "$appdir/"
cp "$root/app/linux/packaging/io.sse.gramma.png" "$appdir/"
ln -s io.sse.gramma.png "$appdir/.DirIcon"
ln -s usr/bin/gramma "$appdir/AppRun"

case "$arch" in
  x64) tool_arch=x86_64 ;;
  arm64) tool_arch=aarch64 ;;
  *) echo "unknown arch $arch" >&2; exit 1 ;;
esac
tool="$(mktemp -d)/appimagetool"
curl -fsSL -o "$tool" \
  "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-$tool_arch.AppImage"
chmod +x "$tool"
ARCH="$tool_arch" "$tool" --appimage-extract-and-run "$appdir" \
  "$out/gramma-$version-linux-$arch.AppImage"
ls -l "$out"
