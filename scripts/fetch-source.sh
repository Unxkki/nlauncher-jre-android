#!/usr/bin/env bash
# Download the pinned upstream OpenJDK tarball (github.com/openjdk/jdk21u),
# verify its sha256 and unpack a pristine tree into $SRC_DIR.
#
# Usage:
#   scripts/fetch-source.sh                 download + verify + unpack (pins from config.env)
#   scripts/fetch-source.sh --download-only download + verify, do not unpack
#   scripts/fetch-source.sh --pin <tag>     re-pin config.env to another jdk21u tag,
#                                           e.g. --pin jdk-21.0.13-ga (downloads it to hash it)
#
# Env: WORK_DIR, DOWNLOAD_DIR, SRC_DIR (see scripts/common.sh),
#      EXCLUDE_TESTS=1 to skip unpacking test/ (saves ~400 MB, not needed for images).
set -euo pipefail
# shellcheck source=common.sh
. "$(dirname "$0")/common.sh"

pin() {
  local tag="$1"
  [[ "$tag" =~ ^jdk-${JDK_FEATURE}\.[0-9]+\.[0-9]+(\.[0-9]+)?-ga$ ]] \
    || die "expected a GA tag like jdk-${JDK_FEATURE}.0.13-ga, got '$tag'"
  local version="${tag#jdk-}"; version="${version%-ga}"
  local repo="https://github.com/openjdk/jdk${JDK_FEATURE}u"
  log "resolving $tag in $repo"
  local refs commit build
  refs="$(git ls-remote --tags "$repo" "refs/tags/jdk-${version}*")"
  commit="$(printf '%s\n' "$refs" | awk -v t="refs/tags/$tag^{}" '$2==t {print $1}')"
  [ -n "$commit" ] || commit="$(printf '%s\n' "$refs" | awk -v t="refs/tags/$tag" '$2==t {print $1}')"
  [ -n "$commit" ] || die "tag $tag not found"
  # The GA tag points at the same commit as the last jdk-<version>+<build> tag.
  build="$(printf '%s\n' "$refs" | awk -v c="$commit" -v p="refs/tags/jdk-${version}+" '
      $1==c && index($2,p)==1 { s=substr($2,length(p)+1); sub(/\^\{\}$/,"",s); print s }' | sort -n | tail -1)"
  [ -n "$build" ] || die "could not find the build number (jdk-${version}+N) for $tag"
  local file="jdk${JDK_FEATURE}u-${tag}.tar.gz"
  local url="$repo/archive/refs/tags/$tag.tar.gz"
  download "$url" "$DOWNLOAD_DIR/$file"
  local sha
  sha="$(sha256_of "$DOWNLOAD_DIR/$file")"
  local cfg="$REPO_DIR/config.env" tmp
  tmp="$(mktemp)"
  sed -e "s|^JDK_TAG=.*|JDK_TAG=$tag|" \
      -e "s|^JDK_VERSION=.*|JDK_VERSION=$version|" \
      -e "s|^JDK_BUILD=.*|JDK_BUILD=$build|" \
      -e "s|^JDK_COMMIT=.*|JDK_COMMIT=$commit|" \
      -e "s|^JDK_SRC_URL=.*|JDK_SRC_URL=$url|" \
      -e "s|^JDK_SRC_FILE=.*|JDK_SRC_FILE=$file|" \
      -e "s|^JDK_SRC_SHA256=.*|JDK_SRC_SHA256=$sha|" \
      -e "s|^NL_REVISION=.*|NL_REVISION=1|" \
      "$cfg" > "$tmp"
  cat "$tmp" > "$cfg"
  rm -f "$tmp"
  log "pinned $tag (+$build, commit $commit, sha256 $sha); NL_REVISION reset to 1"
  log "now run scripts/apply-patches.sh --check and refresh patches that no longer apply"
}

case "${1:-}" in
  --pin)
    [ $# -eq 2 ] || die "usage: $0 --pin <tag>"
    pin "$2"
    exit 0
    ;;
  --download-only|"") ;;
  *) die "unknown argument: $1" ;;
esac

tarball="$DOWNLOAD_DIR/$JDK_SRC_FILE"
download "$JDK_SRC_URL" "$tarball" "$JDK_SRC_SHA256"
log "verified $JDK_SRC_FILE sha256=$JDK_SRC_SHA256"

[ "${1:-}" = "--download-only" ] && exit 0

top="jdk${JDK_FEATURE}u-${JDK_TAG}"
rm -rf "$SRC_DIR"
mkdir -p "$(dirname "$SRC_DIR")"
extract_dir="$(mktemp -d "$(dirname "$SRC_DIR")/extract.XXXXXX")"
excludes=()
if [ "${EXCLUDE_TESTS:-0}" = 1 ]; then
  excludes=(--exclude "$top/test/*")
fi
log "unpacking into $SRC_DIR"
tar -xzf "$tarball" -C "$extract_dir" ${excludes[@]+"${excludes[@]}"}
[ -d "$extract_dir/$top" ] || die "unexpected tarball layout (no $top/)"
mv "$extract_dir/$top" "$SRC_DIR"
rmdir "$extract_dir"
log "source ready: $SRC_DIR"
