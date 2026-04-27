#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd)

BUILD_ROOT=${BUILD_ROOT:-$REPO_ROOT/build/armhf-root}
DIST_DIR=${DIST_DIR:-$REPO_ROOT/dist}
VERSION=$(grep 'ARGYLL_VERSION_STR' "$REPO_ROOT/h/aconfig.h" | head -n 1 | sed 's/# define ARGYLL_VERSION_STR //' | tr -d '"')
PACKAGE_NAME="argyllcms-linux-armhf-v$VERSION"
PACKAGE_TARBALL="$DIST_DIR/$PACKAGE_NAME.tar.gz"
PACKAGE_STAGE=$(mktemp -d "${TMPDIR:-/tmp}/argyllcms-armhf-package.XXXXXX")
PACKAGE_ROOT="$PACKAGE_STAGE/$PACKAGE_NAME"

REQUIRED_BINS=(spotread chartread colprof ccxxmake oeminst)

cleanup() {
    rm -rf "$PACKAGE_STAGE"
}

trap cleanup EXIT

if [[ ! -d "$BUILD_ROOT/usr/bin" ]]; then
    echo "Missing staged runtime at $BUILD_ROOT/usr/bin" >&2
    echo "Run tools/build_armhf.sh first." >&2
    exit 1
fi

mkdir -p "$DIST_DIR"
rm -rf "$PACKAGE_ROOT"
mkdir -p "$PACKAGE_ROOT/bin"

for bin_name in "${REQUIRED_BINS[@]}"; do
    if [[ ! -x "$BUILD_ROOT/usr/bin/$bin_name" ]]; then
        echo "Missing required binary: $BUILD_ROOT/usr/bin/$bin_name" >&2
        exit 1
    fi
    install -m 0755 "$BUILD_ROOT/usr/bin/$bin_name" "$PACKAGE_ROOT/bin/$bin_name"
done

ln -sfn oeminst "$PACKAGE_ROOT/bin/i1d3ccss"

if [[ -d "$BUILD_ROOT/usr/ref" ]]; then
    mkdir -p "$PACKAGE_ROOT/ref"
    rsync -a "$BUILD_ROOT/usr/ref/" "$PACKAGE_ROOT/ref/"
fi

install -m 0644 "$REPO_ROOT/ReadMe.txt" "$PACKAGE_ROOT/"
install -m 0644 "$REPO_ROOT/License.txt" "$PACKAGE_ROOT/"

tar -C "$PACKAGE_STAGE" -czf "$PACKAGE_TARBALL" "$PACKAGE_NAME"

echo "Created $PACKAGE_TARBALL"