#!/usr/bin/env bash
# Create the "complete corresponding source" archive attached to every release
# (GPLv2 section 3): the upstream tarball exactly as downloaded, this
# repository (patches, scripts, workflows, config) and the pinned header
# packages used at compile time.
#
#   out/jre21-android-sources.tar  (+ .sha256)
#
# Requires: scripts/fetch-source.sh --download-only and scripts/fetch-headers.sh.
set -euo pipefail
# shellcheck source=common.sh
. "$(dirname "$0")/common.sh"

tag="$(release_tag)"
name="jre${JDK_FEATURE}-android-sources"
top="nlauncher-jre-android-$tag"
stage="$OUT_DIR/source-stage"
rm -rf "$stage"
mkdir -p "$stage/$top/upstream" "$stage/$top/deps"

tarball="$DOWNLOAD_DIR/$JDK_SRC_FILE"
[ -f "$tarball" ] || die "missing $tarball (run scripts/fetch-source.sh --download-only)"
[ "$(sha256_of "$tarball")" = "$JDK_SRC_SHA256" ] || die "sha256 mismatch for $tarball"
cp "$tarball" "$stage/$top/upstream/"

# Build recipe: the committed tree of this repository.
if git -C "$REPO_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  git -C "$REPO_DIR" archive --format=tar --prefix="nlauncher-jre-android/" HEAD \
    | tar -x -C "$stage/$top"
  rev="$(git -C "$REPO_DIR" rev-parse HEAD)"
else
  mkdir -p "$stage/$top/nlauncher-jre-android"
  (cd "$REPO_DIR" && tar --exclude=./work --exclude=./out --exclude=./.git -cf - .) \
    | tar -x -C "$stage/$top/nlauncher-jre-android"
  rev="unknown"
fi

grep -v '^[[:space:]]*\(#\|$\)' "$REPO_DIR/deps/headers.lock" | while read -r _ path sha; do
  deb="$DOWNLOAD_DIR/debs/$(basename "$path")"
  [ -f "$deb" ] || die "missing $deb (run scripts/fetch-headers.sh)"
  [ "$(sha256_of "$deb")" = "$sha" ] || die "sha256 mismatch for $deb"
  cp "$deb" "$stage/$top/deps/"
done

cat > "$stage/$top/SOURCES.txt" <<EOF
Complete corresponding source for the $tag binaries of nlauncher-jre-android
(OpenJDK $JDK_VERSION+$JDK_BUILD for Android).

upstream/$JDK_SRC_FILE
    OpenJDK source exactly as downloaded from
    $JDK_SRC_URL
    sha256 $JDK_SRC_SHA256 (tag $JDK_TAG, commit $JDK_COMMIT).
    License: GPLv2 with the Classpath Exception (HotSpot: GPLv2), see LICENSE inside.

nlauncher-jre-android/
    The build recipe at commit $rev: patches/ (applied in the order of
    patches/series), scripts/, config.env, jlink-modules.txt, workflows.

deps/
    Debian packages whose headers (X11, CUPS, fontconfig) are needed to
    compile java.desktop; no code from them is linked into the binaries.

To rebuild: see nlauncher-jre-android/README.md ("Building locally"). Place
upstream/$JDK_SRC_FILE into work/downloads/ and deps/*.deb into
work/downloads/debs/ to build without network access.
EOF

mkdir -p "$OUT_DIR"
out="$OUT_DIR/$name.tar"
rm -f "$out" "$out.sha256"
tar -C "$stage" -cf "$out" "$top"
rm -rf "$stage"
(cd "$OUT_DIR" && printf '%s  %s\n' "$(sha256_of "$name.tar")" "$name.tar" > "$name.tar.sha256")
log "$(cat "$out.sha256")"
