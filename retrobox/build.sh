#!/usr/bin/env bash
# Builds the RetroBox QEMU: QEMU with this repository's vmvga device overlaid,
# the RetroBox GTK display patches, and dxvk-native for SVGA3D.
#
# Usage: retrobox/build.sh [--install-deps]
#
# Runs on Debian 13 amd64 (the RetroBox host release): in CI, or locally with
#   docker run --rm --platform linux/amd64 -v "$PWD:/src" -w /src \
#       debian:trixie retrobox/build.sh --install-deps
#
# Output: retrobox/out/qemu-retrobox-<qemu>-<rev>-linux-x86_64.tar.gz, which
# unpacks to $PREFIX:
#   bin/qemu-system-i386, share/qemu/   QEMU (GTK display with OpenGL, no SDL)
#   lib/                                dxvk-native (libdxvk_d3d9.so.0, ...)
# QEMU dlopens DXVK, so run it with LD_LIBRARY_PATH=$PREFIX/lib.

set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RB="$ROOT/retrobox"
WORK="$RB/work"
OUT="$RB/out"
PREFIX="${PREFIX:-/opt/qemu-retrobox}"
JOBS="$(nproc)"

# shellcheck source=versions.env
. "$RB/versions.env"

log() { echo "==> $*"; }
die() { echo "error: $*" >&2; exit 1; }

DEPS=(
    build-essential git ninja-build pkg-config python3 python3-venv flex bison
    libglib2.0-dev libpixman-1-dev zlib1g-dev libzstd-dev libslirp-dev
    libgtk-3-dev libepoxy-dev libgbm-dev libegl-dev libgl-dev libx11-dev
    libasound2-dev curl ca-certificates
)

install_deps() {
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${DEPS[@]}"
    git config --global --add safe.directory "$ROOT"
}

fetch() {
    local url="$1" sha256="$2" dest="$3"
    if [ ! -f "$dest" ] || ! echo "$sha256  $dest" | sha256sum -c --status; then
        log "downloading $url"
        curl -fL --retry 3 -o "$dest" "$url"
    fi
    echo "$sha256  $dest" | sha256sum -c --status || die "checksum mismatch: $dest"
}

build() {
    local qemu_tar="$WORK/qemu-$QEMU_VERSION.tar.xz"
    local dxvk_tar="$WORK/dxvk-native-$DXVK_VERSION.tar.gz"
    local tree="$WORK/qemu-$QEMU_VERSION"
    local build="$WORK/build"
    local stage="$WORK/stage"

    mkdir -p "$WORK" "$OUT"
    fetch "https://download.qemu.org/qemu-$QEMU_VERSION.tar.xz" "$QEMU_SHA256" "$qemu_tar"
    fetch "https://github.com/doitsujin/dxvk/releases/download/v$DXVK_VERSION/dxvk-native-$DXVK_VERSION-steamrt-sniper.tar.gz" \
        "$DXVK_SHA256" "$dxvk_tar"

    log "preparing QEMU $QEMU_VERSION with vmvga and RetroBox patches"
    rm -rf "$tree" "$build" "$stage"
    tar -xf "$qemu_tar" -C "$WORK"
    cp -r "$ROOT/hw/." "$tree/hw/"
    local fix
    for fix in "$RB"/patches/*.patch; do
        log "applying $(basename "$fix")"
        (cd "$tree" && patch -p0 -s -i "$fix")
    done

    log "configuring (prefix $PREFIX)"
    mkdir -p "$build"
    (cd "$build" && "$tree/configure" \
        --prefix="$PREFIX" \
        --target-list=i386-softmmu \
        --enable-kvm \
        --enable-gtk \
        --enable-opengl \
        --disable-sdl \
        --disable-vte \
        --enable-slirp \
        --audio-drv-list=alsa \
        --disable-docs \
        --disable-werror)
    make -C "$build" -j"$JOBS"
    make -C "$build" install DESTDIR="$stage"

    log "adding dxvk-native $DXVK_VERSION"
    mkdir -p "$stage$PREFIX/lib"
    tar -xzf "$dxvk_tar" -C "$stage$PREFIX/lib" --strip-components=2 usr/lib

    local name
    name="qemu-retrobox-$QEMU_VERSION-$(git -C "$ROOT" rev-parse --short HEAD)-linux-x86_64.tar.gz"
    tar -C "$stage$PREFIX" -czf "$OUT/$name" .
    (cd "$OUT" && sha256sum -- "$name" >SHA256SUMS)
    log "package: $OUT/$name"
}

for arg in "$@"; do
    case "$arg" in
        --install-deps) install_deps ;;
        *) die "usage: $0 [--install-deps]" ;;
    esac
done
build
