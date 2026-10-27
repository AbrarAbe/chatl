#!/usr/bin/env bash
# Integration test for install.sh using a local dist dir (no network).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_SCRIPT="${ROOT_DIR}/install.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

INSTALL_DIR="${TMP_DIR}/usr/local/bin"
export CHATL_INSTALL_DIR="$INSTALL_DIR"
export CHATL_DIST_DIR="${TMP_DIR}/dist"
export PATH="${INSTALL_DIR}:$PATH"

mkdir -p "$INSTALL_DIR" "$CHATL_DIST_DIR"

fail() {
    echo "test_install.sh: $*" >&2
    exit 1
}

# --- build a fake release bundle ---
echo "#!/bin/sh" >"${CHATL_DIST_DIR}/chatl-0.2.0-linux-x64"
echo 'echo "chatl 0.2.0"' >>"${CHATL_DIST_DIR}/chatl-0.2.0-linux-x64"
chmod +x "${CHATL_DIST_DIR}/chatl-0.2.0-linux-x64"

# checksums must contain "  chatl-0.2.0-linux-x64.zip" — the archive name,
# not the binary name, so zip the dir first.
mkdir -p "${CHATL_DIST_DIR}/zip"
cp "${CHATL_DIST_DIR}/chatl-0.2.0-linux-x64" "${CHATL_DIST_DIR}/zip/chatl-0.2.0-linux-x64"
(cd "${CHATL_DIST_DIR}/zip" && zip -q -X chatl-0.2.0-linux-x64.zip chatl-0.2.0-linux-x64)
cp "${CHATL_DIST_DIR}/zip/chatl-0.2.0-linux-x64.zip" "${CHATL_DIST_DIR}/"

SHA="$(sha256sum "${CHATL_DIST_DIR}/chatl-0.2.0-linux-x64.zip" | awk '{print $1}')"
echo "${SHA}  chatl-0.2.0-linux-x64.zip" >"${CHATL_DIST_DIR}/SHA256SUMS"

# --- test 1: install ---
bash "$INSTALL_SCRIPT" --version 0.2.0 >/tmp/install.out 2>&1 || {
    cat /tmp/install.out >&2
    fail "install failed"
}
grep -q "installed chatl 0.2.0 to ${INSTALL_DIR}/chatl" /tmp/install.out || {
    cat /tmp/install.out >&2
    fail "expected install confirmation"
}

# --- test 2: version works ---
OUT="$(chatl --version)" || fail "chatl --version failed"
[ "$OUT" = "chatl 0.2.0" ] || {
    echo "unexpected version: $OUT" >&2
    exit 1
}

# --- test 3: uninstall ---
bash "$INSTALL_SCRIPT" --uninstall >/tmp/uninstall.out 2>&1 || {
    cat /tmp/uninstall.out >&2
    fail "uninstall failed"
}
[ ! -f "${INSTALL_DIR}/chatl" ] || {
    echo "chatl still present after uninstall" >&2
    exit 1
}

echo "all install.sh tests passed"
