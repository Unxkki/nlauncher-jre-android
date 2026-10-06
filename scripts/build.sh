#!/usr/bin/env bash
# Configure and build OpenJDK for Android with the NDK, then link the trimmed
# runtime image with jlink.
#
# Prerequisites: scripts/fetch-source.sh, scripts/fetch-headers.sh,
#                scripts/apply-patches.sh have been run.
#
# Env:
#   TARGET                 aarch64 (default) | arm
#   ANDROID_NDK_HOME       NDK r28c (or ANDROID_NDK_ROOT)
#   BOOT_JDK               JDK 21 for the build host (default: $JAVA_HOME)
#   BUILD_JDK              optional: a JDK of exactly this version for the build host
#                          (--with-build-jdk). Default: the build creates its own.
#   BUILD_CC / BUILD_CXX   host C/C++ compiler for build tools (default: clang/clang++)
#   JOBS                   make parallelism (default: configure's choice)
#   NATIVE_DEBUG_SYMBOLS   none (default) | external | zipped | internal
#   MAKE                   GNU make >= 3.81 (default: gmake if present, else make)
#   EXTRA_CONFIGURE_ARGS   appended to configure verbatim (word-split)
#   SKIP_CONFIGURE=1       reuse an existing configuration
#
# Output: $BUILD_OUT/images/jmods (all target jmods) and
#         $OUT_DIR/stage/$TARGET/jre-21 (jlink'ed runtime image, unstripped)
set -euo pipefail
# shellcheck source=common.sh
. "$(dirname "$0")/common.sh"

resolve_target
resolve_ndk

[ -f "$SRC_DIR/.nlauncher-patched" ] || die "source tree is not patched (run scripts/apply-patches.sh)"
[ -f "$DEPS_DIR/sysroot/include/X11/Xlib.h" ] || die "build headers missing (run scripts/fetch-headers.sh)"

BOOT_JDK="${BOOT_JDK:-${JAVA_HOME:-}}"
[ -n "$BOOT_JDK" ] && [ -x "$BOOT_JDK/bin/javac" ] || die "set BOOT_JDK (or JAVA_HOME) to a JDK 20 or 21 for this host"

if [ -z "${MAKE:-}" ]; then
  if command -v gmake >/dev/null 2>&1; then MAKE='gmake'; else MAKE='make'; fi
fi
"$MAKE" --version 2>/dev/null | head -1 | grep -q 'GNU Make' || die "$MAKE is not GNU make"
command -v autoconf >/dev/null 2>&1 || die "autoconf is required (configure regenerates its script)"

TC="$NDK_TOOLCHAIN/bin"
CC_T="$TC/${CLANG_TRIPLE}${ANDROID_API}-clang"
CXX_T="$TC/${CLANG_TRIPLE}${ANDROID_API}-clang++"
[ -x "$CC_T" ] || die "no compiler $CC_T"

# Flags for every target library/executable:
#  - 16 KB ELF segment alignment (required for Android 15+ devices with 16 KB pages);
#  - libc++ is linked statically (--with-stdc++lib=static below); keep its
#    symbols out of the dynamic symbol tables of our libraries.
EXTRA_LDFLAGS="-Wl,-z,max-page-size=16384 -Wl,--exclude-libs,libc++_static.a -Wl,--exclude-libs,libc++abi.a -Wl,--exclude-libs,libunwind.a"
EXTRA_CFLAGS=""
EXTRA_CXXFLAGS=""

# shellcheck disable=SC2054 # commas inside --with-jvm-features are intended
config_args=(
  --openjdk-target="$OPENJDK_TARGET"
  --with-conf-name="$CONF_NAME"
  --with-boot-jdk="$BOOT_JDK"
  --with-toolchain-type=clang
  --with-debug-level=release
  --with-native-debug-symbols="${NATIVE_DEBUG_SYMBOLS:-none}"
  --with-jvm-variants=server
  --with-jvm-features=-zgc,-shenandoahgc,-jvmci
  --enable-headless-only
  --disable-precompiled-headers
  --disable-warnings-as-errors
  --enable-option-checking=fatal
  --with-stdc++lib=static
  --with-freetype=bundled
  --with-libjpeg=bundled
  --with-giflib=bundled
  --with-libpng=bundled
  --with-lcms=bundled
  --with-zlib=bundled
  --x-includes="$DEPS_DIR/sysroot/include"
  --x-libraries="$DEPS_DIR/sysroot/lib"
  --with-cups-include="$DEPS_DIR/sysroot/include"
  --with-fontconfig-include="$DEPS_DIR/sysroot/include"
  --with-version-pre=
  --with-version-build="$JDK_BUILD"
  --with-version-opt="nl$NL_REVISION"
  --with-vendor-name=NLauncher
  --with-vendor-url=https://github.com/Unxkki/nlauncher-jre-android
  --with-vendor-bug-url=https://github.com/Unxkki/nlauncher-jre-android/issues
  --with-vendor-vm-bug-url=https://github.com/Unxkki/nlauncher-jre-android/issues
  --with-extra-cflags="$EXTRA_CFLAGS"
  --with-extra-cxxflags="$EXTRA_CXXFLAGS"
  --with-extra-ldflags="$EXTRA_LDFLAGS"
)
[ -n "${BUILD_JDK:-}" ] && config_args+=(--with-build-jdk="$BUILD_JDK")
[ -n "${JOBS:-}" ] && config_args+=(--with-jobs="$JOBS")
if [ -n "${EXTRA_CONFIGURE_ARGS:-}" ]; then
  # shellcheck disable=SC2206 # intentional word splitting
  config_args+=($EXTRA_CONFIGURE_ARGS)
fi

tool_vars=(
  CC="$CC_T"
  CXX="$CXX_T"
  AR="$TC/llvm-ar"
  NM="$TC/llvm-nm"
  OBJCOPY="$TC/llvm-objcopy"
  OBJDUMP="$TC/llvm-objdump"
  STRIP="$TC/llvm-strip"
  BUILD_CC="${BUILD_CC:-clang}"
  BUILD_CXX="${BUILD_CXX:-clang++}"
)
[ -x "$TC/llvm-cxxfilt" ] && tool_vars+=(CXXFILT="$TC/llvm-cxxfilt")

if [ "${SKIP_CONFIGURE:-0}" != 1 ] || [ ! -f "$BUILD_OUT/spec.gmk" ]; then
  log "configure ($CONF_NAME, $OPENJDK_TARGET, API $ANDROID_API, NDK $NDK_REVISION_FOUND)"
  (cd "$SRC_DIR" && bash configure "${config_args[@]}" "${tool_vars[@]}")
fi

log "make jmods ($CONF_NAME)"
"$MAKE" -C "$SRC_DIR" CONF_NAME="$CONF_NAME" LOG=info jmods

# jlink: a cross build cannot run the target's own jlink, so we use the JDK
# that was built for the build host as part of this build (the "Build JDK",
# see doc/building.md, "Boot JDK and Build JDK"), or $BUILD_JDK when given.
# It links the *target* jmods; the target platform is read from java.base.jmod.
build_jdk="${BUILD_JDK:-}"
if [ -z "$build_jdk" ]; then
  # spec.gmk has BUILD_JDK:=$(BUILDJDK_OUTPUTDIR)/jdk, i.e. <conf>/buildjdk/jdk.
  build_jdk="$BUILD_OUT/buildjdk/jdk"
fi
JLINK="$build_jdk/bin/jlink"
[ -x "$JLINK" ] || die "jlink of the build JDK not found at $JLINK"

modules="$(grep -v '^[[:space:]]*\(#\|$\)' "$REPO_DIR/jlink-modules.txt" | awk '{print $1}' | paste -sd, -)"
stage="$OUT_DIR/stage/$TARGET"
rm -rf "$stage"
mkdir -p "$stage"
log "jlink --add-modules $modules"
"$JLINK" \
  --module-path "$BUILD_OUT/images/jmods" \
  --add-modules "$modules" \
  --output "$stage/jre-$JDK_FEATURE" \
  --no-header-files \
  --no-man-pages \
  --release-info "add:NLAUNCHER_RELEASE=$(release_tag)"

log "runtime image: $stage/jre-$JDK_FEATURE"
