#!/bin/bash
# Standalone Rust build script for Xcode.
# Compiles the Tauri Rust library (libapp.a) for the current Xcode build
# destination so that Xcode's Build & Run works without needing `tauri ios dev`.
#
# This script is called by the "Build Rust Code" pre-build script phase.
# It determines the correct Rust target from Xcode build settings and
# compiles via cargo, then copies the artifact to the Externals directory
# that Xcode links against.

set -euo pipefail

# Ensure toolchains are in PATH
export PATH="/Users/IA/.cargo/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

# Resolve ALL paths to absolute immediately (before any cd)
SRCROOT="${SRCROOT:-$(cd "$(dirname "$0")" && pwd)}"
PROJECT_ROOT="$(cd "${SRCROOT}/../../.." && pwd)"
TAURI_DIR="${PROJECT_ROOT}/src-tauri"
DIST_DIR="${PROJECT_ROOT}/dist"
ASSETS_DIR="${SRCROOT}/assets"
CONFIGURATION="${CONFIGURATION:-debug}"

echo "[build-rust.sh] PROJECT_ROOT: ${PROJECT_ROOT}"
echo "[build-rust.sh] TAURI_DIR: ${TAURI_DIR}"
echo "[build-rust.sh] SRCROOT: ${SRCROOT}"

# Map Xcode SDK + arch to Rust target triple
determine_rust_target() {
    local sdk="${SDK_NAME:-iphonesimulator}"
    local arch="${ARCHS:-arm64}"

    if [[ "$sdk" == iphonesimulator* ]]; then
        case "$arch" in
            arm64) echo "aarch64-apple-ios-sim" ;;
            x86_64) echo "x86_64-apple-ios" ;;
            *) echo "aarch64-apple-ios-sim" ;;
        esac
    elif [[ "$sdk" == iphoneos* ]]; then
        echo "aarch64-apple-ios"
    else
        echo "aarch64-apple-ios-sim"
    fi
}

RUST_TARGET=$(determine_rust_target)
echo "[build-rust.sh] Rust target: ${RUST_TARGET}"
echo "[build-rust.sh] Configuration: ${CONFIGURATION}"

# Map Xcode configuration to Cargo profile
if [[ "$CONFIGURATION" == "release" ]]; then
    CARGO_FLAGS="--release"
    CARGO_OUT_DIR="release"
else
    CARGO_FLAGS=""
    CARGO_OUT_DIR="debug"
fi

# Build the frontend dist if it doesn't exist yet
if [ ! -d "$DIST_DIR" ] || [ ! -f "$DIST_DIR/index.html" ]; then
    echo "[build-rust.sh] Building frontend (dist not found)..."
    pushd "${PROJECT_ROOT}" > /dev/null
    npm run build
    popd > /dev/null
else
    echo "[build-rust.sh] Frontend dist exists, skipping frontend build."
fi

# Copy frontend dist into assets/ so Xcode bundles it into the .app
if [ -d "$DIST_DIR" ] && [ -f "$DIST_DIR/index.html" ]; then
    echo "[build-rust.sh] Syncing dist/ → assets/..."
    mkdir -p "${ASSETS_DIR}"
    rm -rf "${ASSETS_DIR:?}/"*
    cp -R "${DIST_DIR}/"* "${ASSETS_DIR}/"
    echo "[build-rust.sh] Frontend assets ready."
fi

# Build the Rust library
echo "[build-rust.sh] Running cargo build..."
pushd "${TAURI_DIR}" > /dev/null
cargo build --target "${RUST_TARGET}" --lib ${CARGO_FLAGS} 2>&1
popd > /dev/null

# Determine the output library path
# Cargo produces: target/<triple>/<profile>/libapp_lib.a
CARGO_LIB="${TAURI_DIR}/target/${RUST_TARGET}/${CARGO_OUT_DIR}/libapp_lib.a"

if [ ! -f "$CARGO_LIB" ]; then
    echo "[build-rust.sh] ERROR: Expected library not found at ${CARGO_LIB}"
    echo "[build-rust.sh] Contents of target dir:"
    ls -la "${TAURI_DIR}/target/${RUST_TARGET}/${CARGO_OUT_DIR}/"lib*.a 2>/dev/null || echo "  (no .a files found)"
    exit 1
fi

echo "[build-rust.sh] Built: ${CARGO_LIB}"

# Copy to the Externals directory that Xcode links against
# Xcode expects: Externals/<arch>/<configuration>/libapp.a
for arch in ${ARCHS:-arm64}; do
    DEST_DIR="${SRCROOT}/Externals/${arch}/${CONFIGURATION}"
    mkdir -p "${DEST_DIR}"
    cp "${CARGO_LIB}" "${DEST_DIR}/libapp.a"
    echo "[build-rust.sh] Copied to: ${DEST_DIR}/libapp.a"
done

echo "[build-rust.sh] Done."
