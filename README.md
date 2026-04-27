# ArgyllCMS ARM

This repository packages the upstream ArgyllCMS 3.5.0 source tree with a reproducible Linux `armhf` cross-build flow.

The source files in this repository come from the upstream `Argyll_V3.5.0_src.zip` release. The added ARM-specific layer is intentionally small:

- `tools/build_armhf.sh` cross-builds and stages an `arm-linux-gnueabihf` runtime.
- `tools/package_release.sh` creates a release tarball with the PGenerator-relevant binaries.
- `.gitignore` keeps generated build output out of the repository.

## Why this repo exists

PGenerator+ only needs the Linux ARM runtime pieces required for meter and spectro workflows. The current repository builds an ARM runtime subset that avoids workstation-specific display dependencies while still covering the command-line tools needed for meter, profiling, and CCSS generation workflows:

- `spotread`
- `chartread`
- `colprof`
- `ccxxmake`
- `oeminst`

`ccxxmake` is patched here to support a headless ARM runtime path for file-based `.ti3 -> .ccss/.ccmx` conversion. Interactive display-driven use is still intentionally disabled in ARM runtime mode, and tools such as `dispcal` and `dispread` remain outside this stripped runtime slice.

Upstream ArgyllCMS 3.5.0 no longer ships a standalone `i1d3ccss` binary. That legacy functionality was folded into `oeminst`, so downstream packaging that expects `i1d3ccss` should provide a compatibility symlink to `oeminst`.

## Host requirements

The helper scripts assume a Linux host with:

- `arm-linux-gnueabihf-gcc`
- `arm-linux-gnueabihf-g++`
- `arm-linux-gnueabihf-ar`
- `arm-linux-gnueabihf-ranlib`
- `arm-linux-gnueabihf-strip`
- `bash`, `curl`, `dpkg-deb`, `tar`, `rsync`

`jam` is also required by upstream ArgyllCMS. If the host does not already provide `jam` or `jam.perforce`, `tools/build_armhf.sh` will download the Debian `jam` package and extract a local `jam.perforce` binary into `.tools/` without requiring root.

The helper script also forces ArgyllCMS to use its bundled TIFF, JPEG, PNG, Z, and SSL libraries. That avoids depending on host-installed `armhf` development packages for the first release path.
It also disables upstream plotting support in the ARM runtime build, which removes another X11-only dependency chain that is not needed for the PGenerator command-line subset.

For older Raspberry Pi userlands, the important detail is matching the target glibc headers as well as the target libraries. This repository supports a sysrooted build path so `ccxxmake` can be built against headers and libraries harvested from a live Pi rootfs instead of the host cross-toolchain's newer glibc headers.

Two deterministic generated files are intentionally checked into this repository:

- `tiff/libtiff/tif_fax3sm.c`
- `imdi/imdi_k.h`

They are normally produced by freshly built helper binaries during the upstream build. For cross-compiling, checking them in avoids trying to execute ARM binaries on the x86 build host.

The cross-build helper also skips generation of the optional `gamut/RefMediumGamut.gam` sample. That sample is not required for the PGenerator runtime binaries targeted by this repository.

## Build

From the repository root:

```bash
tools/build_armhf.sh
```

This stages the ARM runtime under `build/armhf-root/`.

Optional environment overrides:

```bash
JOBS=8 \
TOOLCHAIN_PREFIX=arm-linux-gnueabihf \
BUILD_ROOT="$PWD/build/custom-armhf-root" \
tools/build_armhf.sh
```

To build against a Raspberry Pi sysroot:

```bash
SYSROOT=/path/to/pi-sysroot \
BUILD_ROOT="$PWD/build/armhf-root-pi-sysroot" \
tools/build_armhf.sh
```

To build only the Pi-compatible `ccxxmake` slice used for CCSS/CCMX creation:

```bash
SYSROOT=/path/to/pi-sysroot \
PGENERATOR_ARM_CCXXMAKE_ONLY=true \
BUILD_ROOT="$PWD/build/armhf-root-pi-sysroot-ccxxmake" \
tools/build_armhf.sh
```

That mode stages a headless `ccxxmake` in `usr/bin/ccxxmake` that supports file-based operation such as `ccxxmake -S -f ref.ti3 output.ccss`.

## Package a release tarball

After a successful build:

```bash
tools/package_release.sh
```

This creates `dist/argyllcms-linux-armhf-v<version>.tar.gz` containing:

- `bin/spotread`
- `bin/chartread`
- `bin/colprof`
- `bin/ccxxmake`
- `bin/oeminst`
- `bin/i1d3ccss` as a symlink to `oeminst`
- `ref/` support files installed by upstream

## Notes

- Upstream ArgyllCMS uses `jam -fJambase` as its real build entry point.
- For ARM cross-builds, the important part is forcing the Jam host variables away from the native x86_64 defaults. Without that, `Jambase` injects `-m64`, which is wrong for `arm-linux-gnueabihf-gcc`.
- The helper script sets `HOSTTYPE=arm-linux-gnueabihf`, `MACHTYPE=arm-linux-gnueabihf`, and `OSTYPE=linux-gnu` before invoking Jam.
- The helper script also exports `CC`, `CXX`, `AR`, `RANLIB`, and `STRIP` so the embedded `configure` steps for upstream libraries use the ARM toolchain too.
- When `SYSROOT` is set, the helper wraps the cross compiler to force the Pi sysroot headers ahead of the host cross-toolchain headers and rewrites injected `-I/usr/include` style paths back into the sysroot.
- `PGENERATOR_ARM_CCXXMAKE_ONLY=true` suppresses unrelated runtime executables so the build can stop at a clean `ccxxmake` install instead of drifting into ancillary tools.
- The repository also corrects the embedded TIFF/JPEG configure wrapper to pass `--host=<triplet>` for cross-builds. Upstream ships that wrapper with `--build`, which breaks clean cross-configure runs.
- The upstream `makepackagebin.sh` script only recognizes x86 and x86_64 Linux package names, so this repository provides its own ARM release packager.

## PGenerator+ integration

The resulting runtime can be imported into PGenerator+ with the existing tooling in that project:

- `PGenerator_plus/tools/import_argyll_runtime.sh`
- `PGenerator_plus/tools/build_pgenerator_plus_image.sh --argyll-runtime-dir <staged-runtime>`
