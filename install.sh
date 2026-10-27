#!/usr/bin/env bash
# install.sh — install chatl from GitHub Releases
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/AbrarAbe/chatl/main/install.sh | sh
#   curl -fsSL ... | sh -s -- --version 0.2.0
#   install.sh --uninstall
#   CHATL_DIST_DIR=/path/to/dist install.sh --version 0.2.0   (offline testing)
#
set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
INSTALL_DIR="${CHATL_INSTALL_DIR:-$HOME/.local/bin}"
DIST_DIR="${CHATL_DIST_DIR:-}"
VERSION=""
UNINSTALL=0
ARCHIVE=""

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
fail() {
  echo "install.sh: $*" >&2
  exit 1
}

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    fail "required command not found: $1"
  fi
}

os_arch() {
  local os arch
  os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64) arch="x64" ;;
    aarch64|arm64) arch="arm64" ;;
    *) fail "unsupported architecture: $arch" ;;
  esac
  case "$os" in
    linux) echo "linux-${arch}" ;;
    darwin) echo "macos-${arch}" ;;
    *) fail "unsupported operating system: $os (linux or macos required)" ;;
  esac
}

platform_ext() {
  case "$1" in
    linux-*) echo ".tar.gz" ;;   # placeholders; replaced by zip below
    macos-*) echo ".tar.gz" ;;
    windows-*) echo ".zip" ;;
    *) echo ".zip" ;;
  esac
}

# -----------------------------------------------------------------------------
# Argument parsing
# -----------------------------------------------------------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    --version)
      VERSION="$2"; shift 2 ;;
    --version=*)
      VERSION="${1#--version=}"; shift ;;
    --uninstall)
      UNINSTALL=1; shift ;;
    --help|-h)
      cat <<EOF
Usage: install.sh [--version <v>] [--uninstall] [--help]
  --version <v>   Install version v (default: latest)
  --uninstall     Remove chatl from ${INSTALL_DIR}
  --help          Show this help
Env:
  CHATL_DIST_DIR  Directory containing chatl-<v>-<plat>.zip + SHA256SUMS
                  (offline; skips network)
EOF
      exit 0 ;;
    *)
      fail "unknown argument: $1" ;;
  esac
done

need_cmd curl
need_cmd sha256sum
need_cmd unzip

# -----------------------------------------------------------------------------
# Uninstall
# -----------------------------------------------------------------------------
if [ "$UNINSTALL" -eq 1 ]; then
  if [ -f "${INSTALL_DIR}/chatl" ]; then
    rm -f "${INSTALL_DIR}/chatl"
    echo "chatl removed from ${INSTALL_DIR}"
  else
    echo "chatl not found in ${INSTALL_DIR}"
  fi
  exit 0
fi

# -----------------------------------------------------------------------------
# Resolve version
# -----------------------------------------------------------------------------
if [ -z "$VERSION" ]; then
  echo "fetching latest release from GitHub…" >&2
  VERSION="$(curl -fsS "https://api.github.com/repos/AbrarAbe/chatl/releases/latest" \
    | grep '"tag_name":' | sed -E 's/.*"tag_name": "([^"]+)".*/\1/')" \
    || fail "could not determine latest release (try --version <v>)"
fi
echo "installing chatl ${VERSION}" >&2

# -----------------------------------------------------------------------------
# Resolve platform & archive name
# -----------------------------------------------------------------------------
PLATFORM="$(os_arch)"
ARCHIVE="chatl-${VERSION}-${PLATFORM}.zip"

# -----------------------------------------------------------------------------
# Download (or use local dist dir)
# -----------------------------------------------------------------------------
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if [ -n "$DIST_DIR" ]; then
  if [ ! -f "${DIST_DIR}/${ARCHIVE}" ]; then
    fail "archive not found: ${DIST_DIR}/${ARCHIVE}"
  fi
  if [ ! -f "${DIST_DIR}/SHA256SUMS" ]; then
    fail "checksums not found: ${DIST_DIR}/SHA256SUMS"
  fi
  cp "${DIST_DIR}/${ARCHIVE}" "${WORK}/${ARCHIVE}"
  cp "${DIST_DIR}/SHA256SUMS" "${WORK}/SHA256SUMS"
else
  URL="https://github.com/AbrarAbe/chatl/releases/download/${VERSION}/${ARCHIVE}"
  echo "downloading ${ARCHIVE}…" >&2
  curl -fsSL "${URL}" -o "${WORK}/${ARCHIVE}" \
    || fail "download failed: ${URL}"
  curl -fsSL "https://github.com/AbrarAbe/chatl/releases/download/${VERSION}/SHA256SUMS" \
    -o "${WORK}/SHA256SUMS" \
    || fail "could not download checksums for ${VERSION}"
fi

# -----------------------------------------------------------------------------
# Verify checksum
# -----------------------------------------------------------------------------
if ! (cd "${WORK}" && grep " ${ARCHIVE}" SHA256SUMS | sha256sum -c -); then
  fail "checksum verification failed for ${ARCHIVE}"
fi

# -----------------------------------------------------------------------------
# Install
# -----------------------------------------------------------------------------
mkdir -p "${INSTALL_DIR}"
unzip -o -q "${WORK}/${ARCHIVE}" -d "${WORK}/extract"
# find the binary (top level of zip)
BINARY="$(find "${WORK}/extract" -maxdepth 1 -type f -name 'chatl*' -print -quit)"
if [ -z "$BINARY" ]; then
  fail "chatl binary not found in archive"
fi
chmod +x "${BINARY}"
cp -f "${BINARY}" "${INSTALL_DIR}/chatl"

echo "installed chatl ${VERSION} to ${INSTALL_DIR}/chatl"
echo "add ${INSTALL_DIR} to your PATH if it is not already:"
echo "  export PATH=\"\${PATH}:${INSTALL_DIR}\""
