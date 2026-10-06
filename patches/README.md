# Patches

`series` lists the patches in the order `scripts/apply-patches.sh` applies
them (`git apply -p1`, exact context, no fuzz) on top of the pristine
upstream tarball pinned in `../config.env`
(`openjdk/jdk21u`, tag `jdk-21.0.12-ga` = `jdk-21.0.12+8`).

## `termux/` — from Termux

Source: [termux/termux-packages](https://github.com/termux/termux-packages),
directory `packages/openjdk-21`, commit
`44c28b599ca5cdee9be98b8b803ddca4807e580b` (the Termux package was at
21.0.12, same upstream tarball and sha256). The patches are GPL-licensed
changes to GPL code, written by the Termux contributors named in each
patch header (Duy Tran Khanh, Henrik Grimler, Tee KOBAYASHI, agnostic-apollo,
Robert Kirkman, Fredrik Fornwall, alexytomi and others). Headers and file
names are kept as in Termux, so numbering has gaps where we dropped a patch.

| Termux patch | Status | Notes |
|---|---|---|
| 0001 libinet: include netinet/in.h | taken as is | |
| 0002 os_linux: android checks and fixes | taken as is | |
| 0003 define SYS_gettid on arm/aarch64 | taken as is | |
| 0004 disable posix print_uptime | taken as is | no utmpx on Android |
| 0005 link against system libiconv | **dropped** | bionic has `iconv` in libc since API 28; there is no libiconv in the NDK |
| 0006 aarch64_get_thread_helper → Thread::current | taken as is | |
| 0007 remove aarch64_get_thread_helper asm | taken as is | |
| 0008 use Android's strerror_r | taken as is | |
| 0009 use utimensat on android | taken as is | |
| 0010 fix futimes on android | taken as is | |
| 0011 add CXXFLAGS_JDKLIB to CXXFLAGS | taken as is | |
| 0012 use ASCII codeset on android | **dropped** | `nl_langinfo(CODESET)` exists in bionic since API 26 (we target 29) |
| 0013 fix libjvm.so path when run from an Android app | **dropped** | inserts an `#elif defined(__ANDROID__)` branch after `#if defined(__linux__)`; the NDK defines `__linux__`, so the branch is dead code, and its fallback is a Termux path (`@TERMUX_PREFIX@/bin/java`). Our app starts the VM with `JNI_CreateJavaVM` and lays the JRE out as a normal tree, so HotSpot finds `java.home` from the location of `libjvm.so` |
| 0014 arm: cast address when clearing cache | taken as is | armv7 only |
| 0015 no fpu_control on Android | taken as is | |
| 0016 libfontmanager: link against libawt_xawt | **modified** | headless build: link against `libawt_headless` (via `LIBS_linux`); `libawt_xawt` when not headless |
| 0017 libjvm.so path from /proc/self/maps | taken as is | |
| 0018 warn instead of exiting if getcpu(2) unsupported | taken as is | |
| 0019 remove pre-UAL aliases | taken as is | armv7 only |
| 0020 arm: fix assembly in os_linux_arm.cpp | taken as is | armv7 only |
| 0021 workaround for tagged pointers on Android 11+ | **modified** | guard `__TERMUX__` → `__ANDROID__`; only affects the `java` launcher (`JLI_Launch`). Apps embedding the VM should set `android:allowNativeHeapPointerTagging="false"` |
| 0022 x86: always compile with PIC | **dropped** | 32-bit x86 only, not a target |
| 0023 fix StackOverflowError on ARM | taken as is | armv7 only |
| 0024 dlvsym is available if API >= 24 | taken as is | |
| 0025 update hard-coded paths for Termux | **dropped** | only rewrites `/etc`, `/tmp`, `/usr` paths to the Termux prefix; the parts we need are re-done prefix-free in `nl-0003` (temp dir), `nl-0004` (mount table) and `nl-0005` (resolv.conf) |
| 0026 elfFile.hpp: ELF_ST_TYPE already defined | taken as is | |
| 0027 getloadavg for android | taken as is | no-op for API ≥ 29 |
| 0028 use getpagesize() instead of SHMLBA | taken as is | |
| 0029 strerror_r returns char* | taken as is | |
| 0030 make: handle arm like other arches | taken as is | |
| 0031 fix bugs in File.getCanonicalPath | taken as is | |
| 0032 JvmMapfile.gmk: same symbols for android | taken as is | |
| 0033 fix build with lld 17 | taken as is | |
| 0034 define ARM for arm build with clang | taken as is | armv7 only |
| 0035 no dlinfo/RTLD_DI_LINKMAP on android | taken as is | |
| 0036 bionic type redefinition fix | taken as is | |
| 0037 jdk.attach hard-coded /tmp → Termux prefix | **dropped** | Termux path; `jdk.attach` is not part of our image |
| 0038 do not disable new dtags | taken as is | bionic only honours `DT_RUNPATH` |
| 0039 disable statx syscall | taken as is | |
| 0040 prevent build of libsaproc | taken as is | |
| tmpdir-path-length.diff | **dropped** | Termux prefix substitution; replaced by `nl-0003` |

Termux build options we do **not** reproduce: `-landroid-shmem`,
`-landroid-spawn`, `-liconv` (see `nl-0002`; `posix_spawn` is in bionic
since API 28), X11/CUPS/ALSA/fontconfig/freetype from the Termux prefix
(we build headless, freetype/libpng/libjpeg/giflib/lcms/zlib bundled),
rpaths into `/data/data/com.termux/...`, `link-time-opt`.

## `nlauncher/` — our patches

| Patch | What and why |
|---|---|
| nl-0001 android: build without ALSA, skip libjsound | configure requires ALSA for every Linux target; Android has none. `javax.sound` keeps working without its native mixers |
| nl-0002 android: never use large pages / SysV shm | replaces the libandroid-shmem dependency; shm is denied to apps by SELinux |
| nl-0003 android: HotSpot temp directory from `$TMPDIR` | no `/tmp` on Android; fallback `/data/local/tmp` |
| nl-0004 nio: `/proc/mounts` when `/etc/mtab` is missing | `FileSystem.getFileStores()` on Android |
| nl-0005 dns: `-Djdk.android.resolvConf=<file>` | no `/etc/resolv.conf` on Android; lets the app provide DNS servers for JNDI DNS (SRV lookups) |
| nl-0006 android: `/system/fonts` in the fallback font path | AWT fonts without fontconfig |

## Updating to a new jdk21u tag

```
scripts/fetch-source.sh --pin jdk-21.0.N-ga
scripts/fetch-source.sh && scripts/apply-patches.sh --check
```

Refresh patches that fail (compare with the current Termux
`packages/openjdk-21`), update `TERMUX_PACKAGES_COMMIT` in `config.env` and
this table.
