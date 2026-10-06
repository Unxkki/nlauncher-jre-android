#!/usr/bin/env bash
# Fetch the compile-time-only X11 / CUPS / fontconfig headers listed in
# deps/headers.lock and stage them under $DEPS_DIR/sysroot/include.
# Nothing from these packages ends up in the JRE (see deps/headers.lock).
set -euo pipefail
# shellcheck source=common.sh
. "$(dirname "$0")/common.sh"

MIRRORS="${DEBIAN_MIRRORS:-https://snapshot.debian.org/archive/debian/20261001T000000Z https://deb.debian.org/debian}"
LOCK="$REPO_DIR/deps/headers.lock"
DEB_DIR="$DOWNLOAD_DIR/debs"
STAGE="$DEPS_DIR/sysroot"

rm -rf "$STAGE"
mkdir -p "$STAGE/include" "$STAGE/lib" "$DEB_DIR"

grep -v '^[[:space:]]*\(#\|$\)' "$LOCK" | while read -r pkg path sha; do
  deb="$DEB_DIR/$(basename "$path")"
  ok=0
  for m in $MIRRORS; do
    if (download "$m/$path" "$deb" "$sha"); then ok=1; break; fi
    log "mirror failed: $m"
  done
  [ "$ok" = 1 ] || die "could not download $pkg ($path)"

  tmp="$(mktemp -d)"
  (
    cd "$tmp"
    if ! ar x "$deb" 2>/dev/null; then
      tar -xf "$deb"   # bsdtar (macOS) reads ar archives
    fi
    data=""
    for d in data.tar.*; do [ -f "$d" ] && data="$d" && break; done
    [ -n "$data" ] || die "$pkg: no data.tar.* in $deb"
    mkdir root
    tar -xf "$data" -C root
  )
  for sub in X11 cups fontconfig; do
    if [ -d "$tmp/root/usr/include/$sub" ]; then
      mkdir -p "$STAGE/include/$sub"
      cp -R "$tmp/root/usr/include/$sub/." "$STAGE/include/$sub/"
    fi
  done
  rm -rf "$tmp"
  log "staged headers from $pkg"
done

for h in X11/Xlib.h X11/Xutil.h X11/Intrinsic.h X11/extensions/shape.h \
         X11/extensions/Xrender.h X11/extensions/XTest.h X11/extensions/Xrandr.h \
         X11/extensions/XShm.h cups/cups.h cups/ppd.h cups/raster.h fontconfig/fontconfig.h; do
  [ -f "$STAGE/include/$h" ] || die "missing header after staging: $h"
done
log "headers ready in $STAGE/include"
