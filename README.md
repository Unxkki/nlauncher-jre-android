# nlauncher-jre-android

Build scripts for **OpenJDK 21 for Android** (`arm64-v8a`; `armeabi-v7a`
optional), cross-compiled with the Android NDK from unmodified upstream
sources ([openjdk/jdk21u](https://github.com/openjdk/jdk21u)) plus a small
set of patches. The result is a headless Java runtime image (HotSpot
`server` VM with C1 + C2 JIT) that an Android app can embed to run Java
applications such as Minecraft: Java Edition.

The recipe is based on the [Termux](https://github.com/termux/termux-packages/tree/master/packages/openjdk-21)
OpenJDK package; see [patches/README.md](patches/README.md) for exactly which
Termux patches are used, changed or dropped. Unlike the Termux package, the
image has no hard-coded installation prefix and no dependencies outside the
Android NDK's stable system libraries.

> Status: experimental. The build is verified in CI; runtime behaviour on
> devices is being validated by the NLauncher Android app.

## Downloads

Each [release](https://github.com/Unxkki/nlauncher-jre-android/releases) contains:

| File | Contents |
|---|---|
| `jre21-android-arm64.tar.xz` | runtime image for `arm64-v8a` |
| `jre21-android-arm.tar.xz` | runtime image for `armeabi-v7a` (only if that build succeeded) |
| `*.sha256` | SHA-256 of each file (`sha256sum -c` format) |
| `jre21-android-sources.tar` | complete corresponding source: the upstream tarball as downloaded, this repository at the release commit, and the header packages used at compile time |

### Artifact contract

`jre21-android-<arch>.tar.xz` contains exactly one top-level directory,
`jre-21/`, with the standard layout of a JDK runtime image:

```
jre-21/
  bin/java
  lib/server/libjvm.so
  lib/lib*.so            (libjava, libjli, libnet, libnio, libzip, libjimage, libawt_headless, ...)
  lib/modules            (jimage with the classes of the modules below)
  lib/jvm.cfg
  conf/                  (security, logging, net.properties, ...)
  legal/                 (license notices of every module)
  release                (JAVA_VERSION, MODULES, ..., NLAUNCHER_RELEASE)
  NLAUNCHER-BUILD.txt    (key=value: upstream tag/commit, tarball sha256,
                          patch-series hash, NDK version, API level, build date)
```

Properties guaranteed by the build (checked by `scripts/elfcheck.py`):

* every ELF file is built for the target ABI, with `PT_LOAD` segments
  aligned to 16 KB (`-Wl,-z,max-page-size=16384`, required on devices with
  16 KB pages);
* libc++ is linked **statically** into each library (`--with-stdc++lib=static`,
  i.e. `libc++_static`); no `libc++_shared.so` is needed and none is shipped,
  so the JRE cannot clash with the app's own C++ runtime;
* dependencies are limited to Android system libraries (`libc`, `libm`,
  `libdl`, `liblog`, `libz`, `libandroid`) and libraries inside the image;
  no `RPATH`, `RUNPATH` only `$ORIGIN`-relative, no text relocations;
* minimum API level 29 (Android 10).

`java.home` is not baked in: lay the image out as a directory tree (for
example `<filesDir>/runtimes/jre-21/`) and HotSpot derives `java.home`
from the location of `lib/server/libjvm.so`.

### Modules

Listed in [jlink-modules.txt](jlink-modules.txt): `java.se` (includes
headless `java.desktop`), `jdk.unsupported`, `jdk.crypto.ec`, `jdk.zipfs`,
`jdk.naming.dns`, `jdk.localedata`, `jdk.charsets`, `jdk.management`,
`jdk.jfr`, `jdk.management.jfr`, `jdk.net`, `jdk.httpserver`,
`jdk.security.auth`, `jdk.dynalink`, `jdk.random`. This covers Minecraft
1.21.x with Fabric/Quilt/Forge/NeoForge and common mods. Developer tools
(`javac`, `jshell`, debugger agents, `jdk.attach`, ...) are not included.

### Release tags

`jre21-<upstream version>.<upstream build>-nl<revision>`, e.g.
**`jre21-21.0.12.8-nl1`** = OpenJDK `jdk-21.0.12+8` (`jdk-21.0.12-ga`),
first NLauncher revision. The revision is bumped when patches or build
options change for the same upstream version and reset to 1 for a new
upstream version. Tags contain no `+`. The tag must match `config.env`
(`JDK_VERSION`, `JDK_BUILD`, `NL_REVISION`); CI refuses mismatches.

## Source code and license

The binaries are OpenJDK and are distributed under the
**GNU General Public License, version 2, with the Classpath Exception**
(see [LICENSE](LICENSE), copied verbatim from upstream). Note that HotSpot
(`lib/server/libjvm.so`) is GPLv2 *without* the Classpath Exception; the
class libraries, `jni.h` and the `java` launcher carry the exception.
Third-party components inside OpenJDK keep their own licenses, listed in
`jre-21/legal/`.

Sources for every release:

* upstream: `https://github.com/openjdk/jdk21u/archive/refs/tags/<JDK_TAG>.tar.gz`
  (tag, commit and sha256 pinned in [config.env](config.env); also recorded in
  `NLAUNCHER-BUILD.txt` inside the image);
* changes and build recipe: this repository at the release tag;
* everything in one file: `jre21-android-sources.tar` attached to the release.

Patch attribution: the patches in `patches/termux/` come from
termux-packages and were written by the Termux contributors named in each
patch header; ours are in `patches/nlauncher/`.

## Building

The supported build host is **Linux x86_64** (GitHub Actions `ubuntu-24.04`,
[`.github/workflows/build.yml`](.github/workflows/build.yml), about 1–2 h per
target). Requirements:

* Android NDK **r28c** (`28.2.13676358`) in `ANDROID_NDK_HOME` —
  `scripts/install-ndk.sh` finds or downloads it (pinned sha256);
* a JDK 21 for the host as boot JDK (`BOOT_JDK` or `JAVA_HOME`);
* `bash`, GNU `make`, `autoconf`, a host `clang`, `curl`, `unzip`, `xz`,
  `git`, `python3`; ~15 GB of free disk.

```sh
export ANDROID_NDK_HOME="$(scripts/install-ndk.sh)"
export BOOT_JDK=/path/to/jdk-21
scripts/fetch-source.sh          # download + verify the pinned jdk21u tarball, unpack to work/src
scripts/fetch-headers.sh         # compile-time X11/CUPS/fontconfig headers (pinned .debs)
scripts/apply-patches.sh         # apply patches/series
TARGET=aarch64 scripts/build.sh  # configure + make jmods + jlink -> out/stage/aarch64/jre-21
TARGET=aarch64 scripts/package.sh  # strip, check, NLAUNCHER-BUILD.txt -> out/jre21-android-arm64.tar.xz
scripts/make-source-bundle.sh    # out/jre21-android-sources.tar
```

`TARGET=arm` builds `armeabi-v7a` (optional, best effort).

### How the runtime image is produced

OpenJDK is configured with `--openjdk-target=aarch64-linux-android`
(`arm-linux-androideabi` for arm), the NDK's `aarch64-linux-android29-clang`
as compiler, `--enable-headless-only`, `--with-jvm-variants=server`, bundled
freetype/libpng/libjpeg/giflib/lcms/zlib, static libc++. Because a cross
build cannot run its own output, the build first creates a small **Build
JDK** for the host from the same sources (see "Boot JDK and Build JDK" in
upstream `doc/building.md`; `BUILD_JDK=<path>` can point to an existing JDK
of exactly the same version instead). `make jmods` produces the target's
`.jmod` files, and the Build JDK's `jlink` links the runtime image from
them with `--add-modules <jlink-modules.txt> --no-header-files
--no-man-pages`. jlink takes the target platform from `java.base.jmod`, so
the result contains the Android binaries. No CDS archive is generated
(it cannot be created while cross-compiling); apps can use
`-XX:+AutoCreateSharedArchive -XX:SharedArchiveFile=...` on the device.

The configure step needs X11, CUPS and fontconfig **headers** even for a
headless build; `scripts/fetch-headers.sh` takes them from pinned Debian 12
packages (`deps/headers.lock`). Nothing from those packages is linked.

### macOS (experimental)

[`.github/workflows/build-macos-selfhosted.yml`](.github/workflows/build-macos-selfhosted.yml)
runs the same scripts on a self-hosted Apple Silicon runner
(`[self-hosted, macOS, ARM64]`, manual dispatch only), with the NDK from
`ANDROID_NDK_HOME`, `~/Library/Android/sdk/ndk/28.2.13676358` or a download.
Cross-compiling OpenJDK for Android from macOS is not something upstream
documents or tests; treat this path as a fallback. Releases are always
built on Ubuntu.

## Notes for embedders

* Set `TMPDIR` to a writable directory (e.g. the app cache) before creating
  the VM — HotSpot uses it instead of `/tmp`; also pass `-Djava.io.tmpdir`.
* Pass `-Duser.timezone=<Olson id>` (Android has no `/etc/localtime`) and
  `-Duser.home`.
* DNS for JNDI (SRV records): write the device's DNS servers in resolv.conf
  format to a file and pass `-Djdk.android.resolvConf=<file>`.
* Starting processes: apps targeting API 29+ cannot `exec` files from their
  data directory, so `lib/jspawnhelper` cannot be used; pass
  `-Djdk.lang.Process.launchMechanism=FORK` if the app needs
  `ProcessBuilder` for system binaries.
* Heap pointer tagging (Android 11+): when the VM is created with
  `JNI_CreateJavaVM` inside the app process, set
  `android:allowNativeHeapPointerTagging="false"` in the manifest.
* Useful flags: `-XX:-UsePerfData`, `-XX:-UseContainerSupport`,
  `-Djava.awt.headless=true`.

## Русский

**Что это.** Скрипты сборки OpenJDK 21 под Android (arm64-v8a, опционально
armeabi-v7a) из апстрим-исходников `openjdk/jdk21u` с патчами по рецепту
Termux. Результат — headless-JRE (HotSpot server, C1+C2) для встраивания в
приложение NLauncher для Android. Без путей Termux и без libandroid-shmem /
libandroid-spawn / libc++_shared; minSdk 29; все `.so` выровнены под
страницы 16 КБ.

**Лицензия.** GPLv2 с Classpath Exception (файл LICENSE — дословно из
апстрима); HotSpot (`libjvm.so`) — GPLv2 без исключения. Исходники каждого
релиза: тег апстрима и sha256 в `config.env` и в `NLAUNCHER-BUILD.txt`,
этот репозиторий на теге релиза и архив `jre21-android-sources.tar` в
релизе (апстрим-tarball как скачан + патчи + скрипты + пакеты заголовков).

**Артефакт.** `jre21-android-arm64.tar.xz` (+ `.sha256`), внутри один
каталог `jre-21/` со стандартной раскладкой (`bin/java`,
`lib/server/libjvm.so`, `lib/modules`, `lib/jvm.cfg`, `conf/`, `legal/`,
`release`, `NLAUNCHER-BUILD.txt`). Теги релизов: `jre21-21.0.12.8-nl1`
(версия апстрима, номер сборки, наша ревизия; без `+`).

**Сборка.** Основной путь — GitHub Actions `ubuntu-24.04` (`build.yml`):
вручную (выбор target) или push тега `jre21-*` → GitHub Release.
Self-hosted Mac (`build-macos-selfhosted.yml`) — запасной,
экспериментальный путь. Локально — команды из раздела «Building».
