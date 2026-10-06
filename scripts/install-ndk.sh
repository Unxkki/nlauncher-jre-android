#!/usr/bin/env bash
# Make the pinned NDK (r28c) available and print its path on stdout.
#
#   scripts/install-ndk.sh [<install-dir>]
#
# Order: $ANDROID_NDK_HOME / $ANDROID_NDK_ROOT if they are r28c, then
# <sdk>/ndk/<revision> of $ANDROID_HOME / $ANDROID_SDK_ROOT /
# ~/Library/Android/sdk / ~/Android/Sdk, else download the official zip
# from dl.google.com (sha256-verified) into <install-dir> (default: work/ndk).
set -euo pipefail
# shellcheck source=common.sh
. "$(dirname "$0")/common.sh"

is_pinned_ndk() {
  [ -n "$1" ] && [ -f "$1/source.properties" ] &&
    [ "$(sed -n 's/^Pkg\.Revision *= *//p' "$1/source.properties" | tr -d '\r')" = "$NDK_REVISION" ]
}

for cand in "${ANDROID_NDK_HOME:-}" "${ANDROID_NDK_ROOT:-}" \
            "${ANDROID_HOME:+$ANDROID_HOME/ndk/$NDK_REVISION}" \
            "${ANDROID_SDK_ROOT:+$ANDROID_SDK_ROOT/ndk/$NDK_REVISION}" \
            "$HOME/Library/Android/sdk/ndk/$NDK_REVISION" \
            "$HOME/Android/Sdk/ndk/$NDK_REVISION"; do
  if is_pinned_ndk "$cand"; then
    log "using NDK $NDK_REVISION at $cand"
    echo "$cand"
    exit 0
  fi
done

dest="${1:-$WORK_DIR/ndk}"
ndk="$dest/android-ndk-$NDK_VERSION"
if is_pinned_ndk "$ndk"; then
  echo "$ndk"
  exit 0
fi
case "$(host_os)" in
  linux) url="$NDK_LINUX_URL"; sha="$NDK_LINUX_SHA256" ;;
  darwin) url="$NDK_DARWIN_URL"; sha="$NDK_DARWIN_SHA256" ;;
esac
zip="$dest/$(basename "$url")"
download "$url" "$zip" "$sha"
log "unpacking $(basename "$zip")"
rm -rf "$ndk"
unzip -q "$zip" -d "$dest"
rm -f "$zip"
is_pinned_ndk "$ndk" || die "unexpected NDK layout in $zip"
echo "$ndk"
