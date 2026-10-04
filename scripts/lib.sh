#!/usr/bin/env bash
# Shared helpers for the cursor-docs-vault engine.
# shellcheck shell=bash

_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE_ROOT="$(cd "${_LIB_DIR}/.." && pwd)"

die() { echo "ERROR: $*" >&2; exit 1; }
info() { echo "==> $*"; }
ok() { echo "OK: $*"; }

load_config() {
  local config="${ENGINE_ROOT}/config.local.env"
  local vault url engine roots depth transport
  vault="${CURSOR_DOCS_VAULT:-}"
  url="${CURSOR_DOCS_VAULT_URL:-}"
  engine="${CURSOR_DOCS_ENGINE:-}"
  roots="${CURSOR_DOCS_DISCOVER_ROOTS:-}"
  depth="${CURSOR_DOCS_DISCOVER_MAXDEPTH:-}"
  transport="${CURSOR_DOCS_GIT_TRANSPORT:-}"

  if [[ -f "${config}" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "${config}"
    set +a
  fi

  [[ -n "${vault}" ]] && CURSOR_DOCS_VAULT="${vault}"
  [[ -n "${url}" ]] && CURSOR_DOCS_VAULT_URL="${url}"
  [[ -n "${engine}" ]] && CURSOR_DOCS_ENGINE="${engine}"
  [[ -n "${roots}" ]] && CURSOR_DOCS_DISCOVER_ROOTS="${roots}"
  [[ -n "${depth}" ]] && CURSOR_DOCS_DISCOVER_MAXDEPTH="${depth}"
  [[ -n "${transport}" ]] && CURSOR_DOCS_GIT_TRANSPORT="${transport}"

  CURSOR_DOCS_ENGINE="${CURSOR_DOCS_ENGINE:-${ENGINE_ROOT}}"
  CURSOR_DOCS_DISCOVER_MAXDEPTH="${CURSOR_DOCS_DISCOVER_MAXDEPTH:-3}"
  CURSOR_DOCS_GIT_TRANSPORT="${CURSOR_DOCS_GIT_TRANSPORT:-ssh}"
  export CURSOR_DOCS_ENGINE CURSOR_DOCS_DISCOVER_MAXDEPTH CURSOR_DOCS_GIT_TRANSPORT
  if [[ -n "${CURSOR_DOCS_VAULT:-}" ]]; then
    export CURSOR_DOCS_VAULT
  fi
  if [[ -n "${CURSOR_DOCS_VAULT_URL:-}" ]]; then
    export CURSOR_DOCS_VAULT_URL
  fi
  if [[ -n "${CURSOR_DOCS_DISCOVER_ROOTS:-}" ]]; then
    export CURSOR_DOCS_DISCOVER_ROOTS
  fi
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

abs_path() {
  local target="$1"
  if [[ -d "${target}" ]]; then
    (cd "${target}" && pwd)
  else
    local parent base
    parent="$(cd "$(dirname "${target}")" && pwd)"
    base="$(basename "${target}")"
    printf '%s/%s\n' "${parent}" "${base}"
  fi
}

require_vault() {
  [[ -n "${CURSOR_DOCS_VAULT:-}" ]] || die "CURSOR_DOCS_VAULT is unset. Set it in config.local.env."
  [[ -d "${CURSOR_DOCS_VAULT}/.git" ]] || die "CURSOR_DOCS_VAULT is not a git repo: ${CURSOR_DOCS_VAULT}"
  CURSOR_DOCS_VAULT="$(cd "${CURSOR_DOCS_VAULT}" && pwd)"
  export CURSOR_DOCS_VAULT
}

vault_repo_name() {
  local name="$1"
  while [[ "${name}" == .* ]]; do
    name="${name#.}"
  done
  printf '%s\n' "${name}"
}

safe_name() {
  local label="$1"
  local value="$2"
  [[ "${value}" =~ ^[A-Za-z0-9._-]+$ ]] || die "refusing unsafe ${label}: ${value}"
  [[ "${value}" != .* ]] || die "refusing unsafe ${label}: ${value}"
}
