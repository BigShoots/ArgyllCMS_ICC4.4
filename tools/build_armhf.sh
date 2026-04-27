#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd)

TOOLCHAIN_PREFIX=${TOOLCHAIN_PREFIX:-arm-linux-gnueabihf}
BUILD_ROOT=${BUILD_ROOT:-$REPO_ROOT/build/armhf-root}
LOCAL_TOOLS_DIR=${LOCAL_TOOLS_DIR:-$REPO_ROOT/.tools}
JOBS=${JOBS:-$(nproc)}

find_jam() {
    if [[ -n "${JAM_BIN:-}" && -x "${JAM_BIN}" ]]; then
        printf '%s\n' "$JAM_BIN"
        return 0
    fi

    if command -v jam >/dev/null 2>&1; then
        command -v jam
        return 0
    fi

    if command -v jam.perforce >/dev/null 2>&1; then
        command -v jam.perforce
        return 0
    fi

    local package_dir="$LOCAL_TOOLS_DIR/jam"
    local package_deb="$package_dir/jam.deb"
    local package_root="$package_dir/root"
    local package_bin="$package_root/usr/bin/jam.perforce"

    mkdir -p "$package_dir"

    if [[ ! -x "$package_bin" ]]; then
        rm -rf "$package_root"
        mkdir -p "$package_root"
        curl -fsSL -o "$package_deb" "http://archive.ubuntu.com/ubuntu/pool/universe/j/jam/jam_2.6.1-2.1ubuntu1_amd64.deb"
        dpkg-deb -x "$package_deb" "$package_root"
    fi

    if [[ ! -x "$package_bin" ]]; then
        echo "Unable to locate a usable jam executable" >&2
        return 1
    fi

    printf '%s\n' "$package_bin"
}

check_toolchain() {
    local missing=0
    local tools=(gcc g++ ar ranlib strip)
    local tool

    for tool in "${tools[@]}"; do
        if ! command -v "${TOOLCHAIN_PREFIX}-${tool}" >/dev/null 2>&1; then
            echo "Missing required tool: ${TOOLCHAIN_PREFIX}-${tool}" >&2
            missing=1
        fi
    done

    if [[ "$missing" -ne 0 ]]; then
        exit 1
    fi
}

main() {
    local jam_bin
    local version
    local jam_args

    check_toolchain
    jam_bin=$(find_jam)

    version=$(grep 'ARGYLL_VERSION_STR' "$REPO_ROOT/h/aconfig.h" | head -n 1 | sed 's/# define ARGYLL_VERSION_STR //' | tr -d '"')

    jam_args=(
        -fJambase
        -sDESTDIR="$BUILD_ROOT"
        -sPREFIX=/usr
        -sCROSS_TARGET="${TOOLCHAIN_PREFIX}"
        -sCROSS_SKIP_HOST_TOOLS=true
        -sPGENERATOR_ARM_RUNTIME=true
        -sUSE_PLOT=false
        -sBUILTIN_TIFF=true
        -sBUILTIN_JPEG=true
        -sBUILTIN_PNG=true
        -sBUILTIN_Z=true
        -sBUILTIN_SSL=true
        -sCC="${TOOLCHAIN_PREFIX}-gcc"
        -sC++="${TOOLCHAIN_PREFIX}-g++"
        -sLINK="${TOOLCHAIN_PREFIX}-gcc"
        -sAR="${TOOLCHAIN_PREFIX}-ar rusc"
        -sRANLIB="${TOOLCHAIN_PREFIX}-ranlib"
    )

    rm -rf "$BUILD_ROOT"
    mkdir -p "$BUILD_ROOT"

    echo "Building ArgyllCMS ${version} for ${TOOLCHAIN_PREFIX}"
    echo "Using jam: $jam_bin"
    echo "Staging root: $BUILD_ROOT"

    (
        cd "$REPO_ROOT"
        export OSTYPE=linux-gnu
        export MACHTYPE=${TOOLCHAIN_PREFIX}
        export HOSTTYPE=${TOOLCHAIN_PREFIX}
        export CROSS_TARGET=${TOOLCHAIN_PREFIX}
        export CROSS_CFLAGS=
        export CROSS_LDFLAGS=
        export CC="${TOOLCHAIN_PREFIX}-gcc"
        export CXX="${TOOLCHAIN_PREFIX}-g++"
        export AR="${TOOLCHAIN_PREFIX}-ar"
        export RANLIB="${TOOLCHAIN_PREFIX}-ranlib"
        export STRIP="${TOOLCHAIN_PREFIX}-strip"
        "$jam_bin" "${jam_args[@]}" clean >/dev/null 2>&1 || true
        "$jam_bin" -q -j"$JOBS" "${jam_args[@]}" install
    )

    if [[ -d "$BUILD_ROOT/usr/bin" ]]; then
        find "$BUILD_ROOT/usr/bin" -maxdepth 1 -type f -executable -print0 | \
            xargs -0 -r "${TOOLCHAIN_PREFIX}-strip" 2>/dev/null || true
    fi

    ln -sfn oeminst "$BUILD_ROOT/usr/bin/i1d3ccss"

    echo "ARM runtime staged at $BUILD_ROOT"
}

main "$@"
