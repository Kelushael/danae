#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${XDG_BIN_HOME:-$HOME/.local/bin}"

if [ ! -x "$BIN_DIR/danae" ]; then
  "$ROOT/install.sh"
fi

exec "$BIN_DIR/danae" "$@"
