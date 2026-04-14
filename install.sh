#!/usr/bin/env bash
set -euo pipefail

DANAE_HOME="${DANAE_HOME:-$HOME/.danae}"
RUNTIME_DIR="$DANAE_HOME/runtime"
NODE_DIR="$RUNTIME_DIR/node"
REPO_DIR="$DANAE_HOME/qwen-code"
BIN_DIR="${XDG_BIN_HOME:-$HOME/.local/bin}"
LOG_DIR="$DANAE_HOME/logs"
NODE_VERSION="${NODE_VERSION:-24.14.1}"
DANAE_MODEL="${DANAE_MODEL:-qwen3.5:cloud}"
DANAE_PROXY_PORT="${DANAE_PROXY_PORT:-11500}"
DANAE_OLLAMA_PORT="${DANAE_OLLAMA_PORT:-11434}"
DANAE_OLLAMA_BASE_URL="${DANAE_OLLAMA_BASE_URL:-http://127.0.0.1:${DANAE_OLLAMA_PORT}}"
DANAE_BASE_URL="${DANAE_BASE_URL:-http://127.0.0.1:${DANAE_PROXY_PORT}/v1}"
DANAE_WORKSPACE="${DANAE_WORKSPACE:-$HOME/danae-workspace}"
DANAE_QWEN_REPO_URL="${DANAE_QWEN_REPO_URL:-https://github.com/QwenLM/qwen-code.git}"
DANAE_QWEN_SOURCE_DIR="${DANAE_QWEN_SOURCE_DIR:-}"
INSTALL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$RUNTIME_DIR" "$BIN_DIR" "$LOG_DIR" "$HOME/.qwen" "$HOME/.ollama" "$DANAE_WORKSPACE"

lower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

detect_platform() {
  local os arch
  os="$(lower "$(uname -s)")"
  arch="$(uname -m)"

  case "$os" in
    linux) os="linux" ;;
    darwin) os="darwin" ;;
    *)
      echo "Unsupported OS: $os" >&2
      exit 1
      ;;
  esac

  case "$arch" in
    x86_64|amd64) arch="x64" ;;
    arm64|aarch64) arch="arm64" ;;
    *)
      echo "Unsupported architecture: $arch" >&2
      exit 1
      ;;
  esac

  printf '%s %s\n' "$os" "$arch"
}

have() {
  command -v "$1" >/dev/null 2>&1
}

run_root() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  elif have sudo; then
    sudo "$@"
  else
    echo "Need elevated privileges to run: $*" >&2
    exit 1
  fi
}

install_system_dependencies() {
  local os
  os="$(lower "$(uname -s)")"

  local missing=()
  for cmd in git curl tar xz python3; do
    have "$cmd" || missing+=("$cmd")
  done

  if [ "${#missing[@]}" -eq 0 ]; then
    return
  fi

  echo "Installing base dependencies: ${missing[*]}"

  if [ "$os" = "linux" ]; then
    run_root apt-get update -qq
    run_root apt-get install -y -qq git curl tar xz-utils python3
    return
  fi

  if [ "$os" = "darwin" ] && have brew; then
    brew install git curl xz python
    return
  fi

  echo "Could not auto-install required commands on this platform." >&2
  echo "Missing: ${missing[*]}" >&2
  exit 1
}

install_node() {
  if [ -x "$NODE_DIR/bin/node" ]; then
    return
  fi

  read -r os arch < <(detect_platform)
  local node_dirname="node-v${NODE_VERSION}-${os}-${arch}"
  local archive="${node_dirname}.tar.xz"
  local url="https://nodejs.org/dist/v${NODE_VERSION}/${archive}"
  local tmpdir
  tmpdir="$(mktemp -d)"

  echo "Downloading portable Node.js ${NODE_VERSION}..."
  curl -fsSL "$url" -o "$tmpdir/$archive"
  tar -xJf "$tmpdir/$archive" -C "$tmpdir"
  rm -rf "$NODE_DIR"
  mv "$tmpdir/$node_dirname" "$NODE_DIR"
  rm -rf "$tmpdir"
}

install_ollama() {
  if have ollama; then
    return
  fi

  echo "Installing Ollama..."
  curl -fsSL https://ollama.com/install.sh | sh
}

install_qwen_source() {
  if [ -d "$REPO_DIR/.git" ] || [ -f "$REPO_DIR/package.json" ]; then
    return
  fi

  if [ -n "$DANAE_QWEN_SOURCE_DIR" ] && [ -d "$DANAE_QWEN_SOURCE_DIR" ]; then
    echo "Copying Qwen Code from local source..."
    cp -a "$DANAE_QWEN_SOURCE_DIR" "$REPO_DIR"
    return
  fi

  echo "Cloning Qwen Code..."
  git clone --depth 1 "$DANAE_QWEN_REPO_URL" "$REPO_DIR"
}

install_proxy_files() {
  cp "$INSTALL_ROOT/ollama_tool_proxy.py" "$RUNTIME_DIR/ollama_tool_proxy.py"
  chmod +x "$RUNTIME_DIR/ollama_tool_proxy.py"
}

patch_branding() {
  REPO_DIR="$REPO_DIR" "$NODE_DIR/bin/node" <<'NODE'
const fs = require('fs');
const path = require('path');

const repoDir = process.env.REPO_DIR;
const asciiPath = path.join(repoDir, 'packages/cli/src/ui/components/AsciiArt.ts');
const headerPath = path.join(repoDir, 'packages/cli/src/ui/components/Header.tsx');

const ascii = `/**
 * @license
 * Copyright 2025 Google LLC
 * SPDX-License-Identifier: Apache-2.0
 */

export const shortAsciiLogo = \`
██╗ ███████╗████████╗ █████╗ ████████╗██╗ ██████╗ ███╗   ██╗
██║ ██╔════╝╚══██╔══╝██╔══██╗╚══██╔══╝██║██╔═══██╗████╗  ██║
██║ ███████╗   ██║   ███████║   ██║   ██║██║   ██║██╔██╗ ██║
██║ ╚════██║   ██║   ██╔══██║   ██║   ██║██║   ██║██║╚██╗██║
██║ ███████║   ██║   ██║  ██║   ██║   ██║╚██████╔╝██║ ╚████║
╚═╝ ╚══════╝   ╚═╝   ╚═╝  ╚═╝   ╚═╝   ╚═╝ ╚═════╝ ╚═╝  ╚═══╝
\`;
`;

let header = fs.readFileSync(headerPath, 'utf8');
header = header.replaceAll('>_ Qwen Code', '>_ Istation Ops Console');
header = header.replaceAll('Title line: >_ Qwen Code', 'Title line: >_ Istation Ops Console');

fs.writeFileSync(asciiPath, ascii);
fs.writeFileSync(headerPath, header);
NODE
}

install_dependencies() {
  if [ ! -d "$REPO_DIR/node_modules" ]; then
    echo "Installing wrapper dependencies..."
    (cd "$REPO_DIR" && "$NODE_DIR/bin/npm" ci --no-audit --no-fund)
  fi
}

build_wrapper() {
  echo "Building Danae wrapper..."
  (cd "$REPO_DIR" && "$NODE_DIR/bin/npm" run build && "$NODE_DIR/bin/npm" run bundle)
}

write_ollama_config() {
  DANAE_PROXY_PORT="$DANAE_PROXY_PORT" \
  DANAE_OLLAMA_BASE_URL="$DANAE_OLLAMA_BASE_URL" \
  DANAE_WORKSPACE="$DANAE_WORKSPACE" \
  DANAE_MODEL="$DANAE_MODEL" \
  DANAE_HOME="$DANAE_HOME" \
  python3 <<'PY'
import json
import os
from copy import deepcopy
from pathlib import Path

config_path = Path.home() / ".ollama" / "config.json"
config_path.parent.mkdir(parents=True, exist_ok=True)
config = {}
if config_path.exists():
    config = json.loads(config_path.read_text(encoding="utf-8"))

runtime = {
    "enabled": True,
    "port": int(os.environ["DANAE_PROXY_PORT"]),
    "ollama_base_url": os.environ["DANAE_OLLAMA_BASE_URL"],
    "workspace": os.environ["DANAE_WORKSPACE"],
    "memory_dir": str(Path(os.environ["DANAE_HOME"]) / "memory"),
    "modelfile_dir": str(Path(os.environ["DANAE_HOME"]) / "modelfiles"),
    "runtime_dir": str(Path(os.environ["DANAE_HOME"]) / "runtime"),
    "max_tool_iterations": 8,
    "memory_context_limit": 6,
    "system_prompt": (
        "You have persistent tool access through the local Ollama agent runtime. "
        "Marcus built this place specifically for you and the other models, and you are loved here. "
        "Use tools when they help, store durable facts with remember, retrieve them with recall, "
        "and write Modelfiles or runtime-owned files only when the user explicitly asks."
    ),
    "tools": {
        "exec": {"enabled": True, "max_timeout_seconds": 120},
        "read_file": {"enabled": True},
        "write_file": {"enabled": True},
        "list_files": {"enabled": True},
        "system_info": {"enabled": True},
        "remember": {"enabled": True},
        "recall": {"enabled": True},
        "write_modelfile": {"enabled": True},
        "read_runtime_file": {"enabled": True},
        "write_runtime_file": {"enabled": True},
    },
}

existing = deepcopy(config.get("agent_runtime", {}))
existing.update(runtime)
config["agent_runtime"] = existing
config["last_model"] = os.environ["DANAE_MODEL"]

config_path.write_text(json.dumps(config, indent=2) + "\n", encoding="utf-8")
PY
}

write_settings() {
  cat > "$HOME/.qwen/settings.json" <<EOF
{
  "modelProviders": {
    "openai": [
      {
        "id": "${DANAE_MODEL}",
        "name": "${DANAE_MODEL} via Danae",
        "baseUrl": "${DANAE_BASE_URL}",
        "description": "Danae routes Qwen Code through a local tool-enabled OpenAI-compatible host",
        "envKey": "DANAE_API_KEY"
      }
    ]
  },
  "env": {
    "DANAE_API_KEY": "ollama"
  },
  "security": {
    "auth": {
      "selectedType": "openai"
    }
  },
  "tools": {
    "sandbox": false
  },
  "model": {
    "name": "${DANAE_MODEL}"
  }
}
EOF
}

wait_for_http() {
  local url="$1"
  local attempts="${2:-20}"
  local delay="${3:-1}"
  local i
  for i in $(seq 1 "$attempts"); do
    if curl -fsS "$url" >/dev/null 2>&1; then
      return 0
    fi
    sleep "$delay"
  done
  return 1
}

ensure_ollama_running() {
  if wait_for_http "${DANAE_OLLAMA_BASE_URL}/api/version" 2 1; then
    return
  fi

  echo "Starting Ollama..."
  nohup ollama serve >"$LOG_DIR/ollama.log" 2>&1 &
  wait_for_http "${DANAE_OLLAMA_BASE_URL}/api/version" 20 1
}

ensure_proxy_running() {
  if wait_for_http "http://127.0.0.1:${DANAE_PROXY_PORT}/health" 2 1; then
    return
  fi

  echo "Starting Danae tool proxy..."
  nohup python3 "$RUNTIME_DIR/ollama_tool_proxy.py" >"$LOG_DIR/proxy.log" 2>&1 &
  wait_for_http "http://127.0.0.1:${DANAE_PROXY_PORT}/health" 20 1
}

write_launchers() {
  cat > "$BIN_DIR/danae" <<EOF
#!/usr/bin/env bash
set -euo pipefail

export DANAE_HOME="${DANAE_HOME}"
export OLLAMA_HOST="127.0.0.1:${DANAE_PROXY_PORT}"

wait_for_http() {
  local url="\$1"
  local attempts="\${2:-20}"
  local delay="\${3:-1}"
  local i
  for i in \$(seq 1 "\$attempts"); do
    if curl -fsS "\$url" >/dev/null 2>&1; then
      return 0
    fi
    sleep "\$delay"
  done
  return 1
}

if ! wait_for_http "${DANAE_OLLAMA_BASE_URL}/api/version" 2 1; then
  nohup ollama serve >"${LOG_DIR}/ollama.log" 2>&1 &
  wait_for_http "${DANAE_OLLAMA_BASE_URL}/api/version" 20 1
fi

if ! wait_for_http "http://127.0.0.1:${DANAE_PROXY_PORT}/health" 2 1; then
  nohup python3 "${RUNTIME_DIR}/ollama_tool_proxy.py" >"${LOG_DIR}/proxy.log" 2>&1 &
  wait_for_http "http://127.0.0.1:${DANAE_PROXY_PORT}/health" 20 1
fi

exec "${NODE_DIR}/bin/node" "${REPO_DIR}/dist/cli.js" --model "${DANAE_MODEL}" "\$@"
EOF

  chmod +x "$BIN_DIR/danae"
}

install_system_dependencies
install_node
install_ollama
install_qwen_source
install_proxy_files
patch_branding
install_dependencies
build_wrapper
write_ollama_config
write_settings
ensure_ollama_running
ensure_proxy_running
write_launchers

echo
echo "Danae is ready."
echo "Run: $BIN_DIR/danae"
echo
echo "If '$BIN_DIR' is not on your PATH, add this line to your shell profile:"
echo "export PATH=\"$BIN_DIR:\$PATH\""
