#!/usr/bin/env bash
# Packages the Linux release bundle as a tarball and an AppImage.
# Usage: tool/package-linux.sh <version> <arch: x64|arm64> <out dir>
#
# Both artifacts carry the desktop entry and the icon set from
# app/linux/packaging under share/, laid out like /usr/share, so that
# launchers, task bars and window switchers find the app icon:
#   tarball:  gramma-<version>/{gramma,lib,data,share,LICENSE}
#   AppImage: usr/{bin,share} plus the top-level files appimagetool wants
set -euo pipefail
version="$1"; arch="$2"; out="$3"
root="$(cd "$(dirname "$0")/.." && pwd)"
bundle="$root/app/build/linux/$arch/release/bundle"
packaging="$root/app/linux/packaging"
[ -x "$bundle/gramma" ] || { echo "no bundle at $bundle" >&2; exit 1; }
mkdir -p "$out"

# Desktop integration files, installed relative to a prefix.
install_share() {
  local prefix="$1"
  install -Dm644 "$packaging/io.sse.gramma.desktop" \
    "$prefix/share/applications/io.sse.gramma.desktop"
  local png
  for png in "$packaging"/icons/hicolor/*/apps/io.sse.gramma.png; do
    local size; size="$(basename "$(dirname "$(dirname "$png")")")"
    install -Dm644 "$png" "$prefix/share/icons/hicolor/$size/apps/io.sse.gramma.png"
  done
}

stage="$(mktemp -d)/gramma-$version"
mkdir -p "$stage"
cp -r "$bundle"/. "$stage/"
install_share "$stage"
install -m644 "$root/LICENSE" "$stage/LICENSE"
tar -C "$(dirname "$stage")" -czf "$out/gramma-$version-linux-$arch.tar.gz" "gramma-$version"

appdir="$(mktemp -d)/gramma.AppDir"
mkdir -p "$appdir/usr/bin"
cp -r "$bundle"/. "$appdir/usr/bin/"
install_share "$appdir/usr"
cp "$packaging/io.sse.gramma.desktop" "$appdir/"
cp "$packaging/icons/hicolor/256x256/apps/io.sse.gramma.png" "$appdir/"
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
