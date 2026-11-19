#!/usr/bin/env bash
# Builds JuleHygge for Linux into linux/build/JuleHygge, and packs the release tarball
# linux/build/JuleHygge-linux-x86_64.tar.gz (JuleHygge, install.sh, README.md).
#
#   ./build.sh                 # development build, version 0.0.0 (never updates itself)
#   VERSION=1.6.0 ./build.sh   # release build stamped with that version (the release workflow does this)
#
# Needs Rust (rustup, stable >= 1.89) and:
#   sudo apt install build-essential pkg-config libcairo2-dev libpango1.0-dev libasound2-dev
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v cargo >/dev/null; then
    echo "cargo not found: install Rust with https://rustup.rs" >&2
    exit 1
fi
if ! pkg-config --exists cairo pangocairo alsa; then
    echo "cairo, pango or alsa not found: sudo apt install pkg-config libcairo2-dev libpango1.0-dev libasound2-dev" >&2
    exit 1
fi

cargo build --release --locked 2>/dev/null || cargo build --release
mkdir -p build
cp target/release/JuleHygge build/JuleHygge
echo "Built: $(pwd)/build/JuleHygge ($(build/JuleHygge --version))"

# the release tarball: flat, owned by root:root, so it unpacks the same everywhere
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
cp build/JuleHygge install.sh README.md "$stage/"
chmod 755 "$stage/JuleHygge" "$stage/install.sh"
tar -czf build/JuleHygge-linux-x86_64.tar.gz --owner=0 --group=0 -C "$stage" JuleHygge install.sh README.md
echo "Packed: $(pwd)/build/JuleHygge-linux-x86_64.tar.gz"
