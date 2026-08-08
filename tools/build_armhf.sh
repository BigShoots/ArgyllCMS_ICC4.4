#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd)

TOOLCHAIN_PREFIX=${TOOLCHAIN_PREFIX:-arm-linux-gnueabihf}
BUILD_ROOT=${BUILD_ROOT:-$REPO_ROOT/build/armhf-root}
LOCAL_TOOLS_DIR=${LOCAL_TOOLS_DIR:-$REPO_ROOT/.tools}
JOBS=${JOBS:-$(nproc)}
SYSROOT=${SYSROOT:-}
BUILD_TARGET=${BUILD_TARGET:-install}

realpath_existing() {
    local path="$1"
    [[ -e "$path" ]] || {
        echo "Missing path: $path" >&2
        exit 1
    }
    printf '%s/%s\n' "$(cd -- "$(dirname -- "$path")" && pwd)" "$(basename -- "$path")"
}

check_sysroot() {
    local sysroot_path="$1"
    local required_paths=(
        lib/libc.so.6
        lib/libm.so.6
        usr/lib/Scrt1.o
        usr/lib/libc_nonshared.a
        usr/lib/libpthread_nonshared.a
    )
    local required_path

    for required_path in "${required_paths[@]}"; do
        [[ -e "$sysroot_path/$required_path" ]] || {
            echo "Missing required sysroot file: $sysroot_path/$required_path" >&2
            exit 1
        }
    done
}

create_compiler_wrapper() {
    local wrapper_path="$1"
    local compiler_bin="$2"
    local sysroot_path="$3"
        local compiler_include_dir="$4"
        local sysroot_multiarch_include_dir=""

        if [[ -d "$sysroot_path/usr/include/arm-linux-gnueabihf" ]]; then
                sysroot_multiarch_include_dir="$sysroot_path/usr/include/arm-linux-gnueabihf"
        fi

    cat >"$wrapper_path" <<EOF
#!/usr/bin/env bash
set -euo pipefail
args=()
while [[ \$# -gt 0 ]]; do
    case "\$1" in
        -I/usr/include)
            args+=("-I$sysroot_path/usr/include")
            shift
            ;;
        -I/usr/local/include)
            if [[ -d "$sysroot_path/usr/local/include" ]]; then
                args+=("-I$sysroot_path/usr/local/include")
            fi
            shift
            ;;
        -I/usr/arm-linux-gnueabihf/include)
            if [[ -n "$sysroot_multiarch_include_dir" ]]; then
                args+=("-I$sysroot_multiarch_include_dir")
            fi
            shift
            ;;
        -I)
            if [[ \$# -ge 2 ]]; then
                case "\$2" in
                    /usr/include)
                        args+=("-I$sysroot_path/usr/include")
                        ;;
                    /usr/local/include)
                        if [[ -d "$sysroot_path/usr/local/include" ]]; then
                            args+=("-I$sysroot_path/usr/local/include")
                        fi
                        ;;
                    /usr/arm-linux-gnueabihf/include)
                        if [[ -n "$sysroot_multiarch_include_dir" ]]; then
                            args+=("-I$sysroot_multiarch_include_dir")
                        fi
                        ;;
                    *)
                        args+=("-I" "\$2")
                        ;;
                esac
                shift 2
            else
                args+=("\$1")
                shift
            fi
            ;;
        *)
            args+=("\$1")
            shift
            ;;
    esac
done
exec "$compiler_bin" \
  --sysroot="$sysroot_path" \
    -B"$sysroot_path/usr/lib/" \
    -B"$sysroot_path/lib/" \
    -L"$sysroot_path/usr/lib" \
    -L"$sysroot_path/lib" \
    -nostdinc \
    -isystem "$compiler_include_dir" \
$( [[ -n "$sysroot_multiarch_include_dir" ]] && printf '  -isystem "%s" \\
' "$sysroot_multiarch_include_dir" )  -isystem "$sysroot_path/usr/include" \
  -Wl,-rpath-link,"$sysroot_path/lib" \
  -Wl,-rpath-link,"$sysroot_path/usr/lib" \
    "\${args[@]}"
EOF
    chmod +x "$wrapper_path"
}

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
    local wrapper_dir=""
    local cc_bin="${TOOLCHAIN_PREFIX}-gcc"
    local cxx_bin="${TOOLCHAIN_PREFIX}-g++"
    local link_bin="${TOOLCHAIN_PREFIX}-gcc"
    local compiler_include_dir=""

    check_toolchain
    jam_bin=$(find_jam)

    if [[ -n "$SYSROOT" ]]; then
        SYSROOT=$(realpath_existing "$SYSROOT")
        check_sysroot "$SYSROOT"
        compiler_include_dir="$(${TOOLCHAIN_PREFIX}-gcc -print-file-name=include)"
        wrapper_dir=$(mktemp -d "${TMPDIR:-/tmp}/argyll-toolwrap.XXXXXX")
        create_compiler_wrapper "$wrapper_dir/gcc" "$(command -v "${TOOLCHAIN_PREFIX}-gcc")" "$SYSROOT" "$compiler_include_dir"
        create_compiler_wrapper "$wrapper_dir/g++" "$(command -v "${TOOLCHAIN_PREFIX}-g++")" "$SYSROOT" "$compiler_include_dir"
        create_compiler_wrapper "$wrapper_dir/link" "$(command -v "${TOOLCHAIN_PREFIX}-gcc")" "$SYSROOT" "$compiler_include_dir"
        cc_bin="$wrapper_dir/gcc"
        cxx_bin="$wrapper_dir/g++"
        link_bin="$wrapper_dir/link"
    fi

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
        -sCC="$cc_bin"
        -sC++="$cxx_bin"
        -sLINK="$link_bin"
        -sAR="${TOOLCHAIN_PREFIX}-ar rusc"
        -sRANLIB="${TOOLCHAIN_PREFIX}-ranlib"
    )

    # Jam treats any non-empty value, including the string "false", as true.
    # Only define this selector when the caller explicitly requests the
    # ccxxmake-only slice.
    if [[ "${PGENERATOR_ARM_CCXXMAKE_ONLY:-false}" == "true" ]]; then
        jam_args+=(-sPGENERATOR_ARM_CCXXMAKE_ONLY=true)
    fi

    rm -rf "$BUILD_ROOT"
    mkdir -p "$BUILD_ROOT"

    echo "Building ArgyllCMS ${version} for ${TOOLCHAIN_PREFIX}"
    echo "Using jam: $jam_bin"
    echo "Staging root: $BUILD_ROOT"
    if [[ -n "$SYSROOT" ]]; then
        echo "Using sysroot: $SYSROOT"
    fi

    (
        cd "$REPO_ROOT"
        export OSTYPE=linux-gnu
        export MACHTYPE=${TOOLCHAIN_PREFIX}
        export HOSTTYPE=${TOOLCHAIN_PREFIX}
        export CROSS_TARGET=${TOOLCHAIN_PREFIX}
        export CROSS_CFLAGS=
        export CROSS_LDFLAGS=
        export CC="$cc_bin"
        export CXX="$cxx_bin"
        export AR="${TOOLCHAIN_PREFIX}-ar"
        export RANLIB="${TOOLCHAIN_PREFIX}-ranlib"
        export STRIP="${TOOLCHAIN_PREFIX}-strip"
        "$jam_bin" "${jam_args[@]}" clean >/dev/null 2>&1 || true
        "$jam_bin" -q -j"$JOBS" "${jam_args[@]}" "$BUILD_TARGET"
    )

    if [[ -d "$BUILD_ROOT/usr/bin" ]]; then
        while IFS= read -r -d '' candidate; do
            if file -b "$candidate" | grep -q '^ELF '; then
                "${TOOLCHAIN_PREFIX}-strip" --strip-unneeded "$candidate" 2>/dev/null || true
            fi
        done < <(find "$BUILD_ROOT/usr/bin" -maxdepth 1 -type f -executable -print0)
        if [[ -x "$BUILD_ROOT/usr/bin/oeminst" ]]; then
            ln -sfn oeminst "$BUILD_ROOT/usr/bin/i1d3ccss"
        fi
    fi

    if [[ -n "$wrapper_dir" && -d "$wrapper_dir" ]]; then
        rm -rf "$wrapper_dir"
    fi

    echo "ARM runtime staged at $BUILD_ROOT"
}

main "$@"
