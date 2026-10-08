# Sources log

What was consulted while writing and fixing the build scripts of this repository.
Each change adds a line: date, component, sources.

| Date | Component | Sources |
|---|---|---|
| 2026-10-06 | Build scripts, patches | OpenJDK jdk21u (`doc/building.md`, configure options, make targets); Termux `packages/openjdk-21` patches (GPLv2+CE, listed in `patches/README.md`) |
| 2026-10-08 | `scripts/build.sh`: empty `libpthread.a` / `librt.a` for the link step | Android NDK documentation (Build System Maintainers Guide: bionic includes pthread and rt in libc, the NDK sysroot has no separate libraries); our CI failure log (`ld.lld: unable to find library -lpthread / -lrt` while linking `libjvm.so`) |
