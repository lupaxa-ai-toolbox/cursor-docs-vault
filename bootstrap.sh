#!/usr/bin/env bash
# cursor-docs-vault — install the skill and link code checkouts into a private vault.
#
# Usage:
#   ./bootstrap.sh              # same as: setup
#   ./bootstrap.sh setup        # clone or seed the vault, install the skill
#   ./bootstrap.sh update       # pull the engine and vault, reinstall, refresh links
#   ./bootstrap.sh status       # show paths, skill, and link state
#   ./bootstrap.sh link <path>  # ensure-linked one code checkout
#   ./bootstrap.sh link-all     # link paths from the vault's links.local.toml
#   ./bootstrap.sh discover [dir ...]
#   ./bootstrap.sh unlink <path>
#
# Config: config.local.env (see config.example.env)
set -euo pipefail

BOOTSTRAP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${BOOTSTRAP_ROOT}/scripts/lib.sh"

usage() {
  sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
  exit 2
}

vault_has_commit() {
  git -C "${CURSOR_DOCS_VAULT}" rev-parse --verify HEAD >/dev/null 2>&1
}

vault_is_dirty() {
  [[ -n "$(git -C "${CURSOR_DOCS_VAULT}" status --porcelain)" ]]
}

copy_template() {
  local src="${ENGINE_ROOT}/vault-template"
  [[ -d "${src}" ]] || die "missing vault template: ${src}"
  cp -R "${src}/." "${CURSOR_DOCS_VAULT}/"
  echo "Copied vault template into ${CURSOR_DOCS_VAULT}"
}

pull_ff() {
  local path="$1"
  local label="$2"
  if ! git -C "${path}" rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
    echo "remote is missing; left ${label} local."
    return 0
  fi
  if ! git -C "${path}" pull --ff-only; then
    die "${label} cannot fast-forward: ${path}"
  fi
}

cmd_setup() {
  need_cmd git
  need_cmd python3
  load_config

  if [[ -z "${CURSOR_DOCS_VAULT:-}" ]]; then
    die "CURSOR_DOCS_VAULT is unset. Copy config.example.env to config.local.env and set it."
  fi

  if [[ ! -e "${CURSOR_DOCS_VAULT}" ]]; then
    [[ -n "${CURSOR_DOCS_VAULT_URL:-}" ]] || die "CURSOR_DOCS_VAULT does not exist and CURSOR_DOCS_VAULT_URL is unset."
    info "Cloning vault"
    git clone "${CURSOR_DOCS_VAULT_URL}" "${CURSOR_DOCS_VAULT}"
  fi

  [[ -d "${CURSOR_DOCS_VAULT}/.git" ]] || die "CURSOR_DOCS_VAULT is not a git repo: ${CURSOR_DOCS_VAULT}"
  require_vault

  if ! vault_has_commit; then
    if vault_is_dirty; then
      die "vault directory is not an empty git repo: ${CURSOR_DOCS_VAULT}"
    fi
    copy_template
    "${ENGINE_ROOT}/scripts/sync-vault.sh" "Initial cursor-docs vault."
  elif [[ -f "${CURSOR_DOCS_VAULT}/registry.toml" ]]; then
    info "Vault already has registry.toml"
    pull_ff "${CURSOR_DOCS_VAULT}" "vault"
  else
    die "vault is not empty and has no registry.toml: ${CURSOR_DOCS_VAULT}"
  fi

  "${ENGINE_ROOT}/scripts/install-skill.sh"
  ok "Setup complete"
  echo "Start a new Cursor agent so the skill loads."
}

cmd_update() {
  need_cmd git
  need_cmd python3
  load_config
  require_vault

  if [[ -d "${ENGINE_ROOT}/.git" ]]; then
    info "Pulling engine"
    pull_ff "${ENGINE_ROOT}" "engine" || die "engine cannot fast-forward"
  fi
  # pull_ff returns 0 when remote is missing. A failed ff-only already died.
  load_config
  require_vault

  info "Pulling vault"
  if git -C "${CURSOR_DOCS_VAULT}" rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
    if ! git -C "${CURSOR_DOCS_VAULT}" pull --ff-only; then
      die "vault cannot fast-forward: ${CURSOR_DOCS_VAULT}"
    fi
  else
    echo "remote is missing; left vault local."
  fi

  "${ENGINE_ROOT}/scripts/install-skill.sh"
  if [[ -f "${CURSOR_DOCS_VAULT}/links.local.toml" ]]; then
    "${ENGINE_ROOT}/scripts/link-all.sh"
  fi
  ok "Update complete"
}

cmd_status() {
  load_config
  echo "cursor-docs-vault status"
  echo "engine:    ${CURSOR_DOCS_ENGINE:-${ENGINE_ROOT}}"
  echo "vault:     ${CURSOR_DOCS_VAULT:-"(unset)"}"
  echo "transport: ${CURSOR_DOCS_GIT_TRANSPORT}"
  local skill="${HOME}/.cursor/skills/cursor-docs-vault/SKILL.md"
  local rule="${HOME}/.cursor/rules/cursor-docs-vault.mdc"
  if [[ -f "${skill}" ]]; then
    echo "skill:     installed"
  else
    echo "skill:     missing"
  fi
  if [[ -f "${rule}" ]]; then
    echo "rule:      installed"
  else
    echo "rule:      missing"
  fi
  if [[ -n "${CURSOR_DOCS_VAULT:-}" && -f "${CURSOR_DOCS_VAULT}/links.local.toml" ]]; then
    echo "links:"
    python3 - <<'PY' "${CURSOR_DOCS_VAULT}/links.local.toml" "${CURSOR_DOCS_VAULT}"
import sys
from pathlib import Path

links = Path(sys.argv[1])
vault = Path(sys.argv[2])
in_paths = False
for raw in links.read_text(encoding="utf-8").splitlines():
    line = raw.split("#", 1)[0].strip()
    if not line:
        continue
    if line.startswith("[") and line.endswith("]"):
        in_paths = line.strip("[]").strip() == "paths"
        continue
    if not in_paths or "=" not in line:
        continue
    key, value = line.split("=", 1)
    key = key.strip().strip('"').strip("'")
    value = value.strip().strip('"').strip("'")
    org, _, repo = key.partition("/")
    expected = vault / "projects" / org / repo
    link = Path(value) / "cursor-docs"
    if link.is_symlink() and link.resolve() == expected.resolve():
        state = "linked"
    else:
        state = "failed"
    print(f"  {state}\t{key}\t{value}")
PY
  else
    echo "links:     (none)"
  fi
  local report="${ENGINE_ROOT}/.discover-report"
  if [[ -f "${report}" ]]; then
    echo "discover:"
    cat "${report}"
  fi
}

record_discover() {
  local state="$1"
  local path="$2"
  local reason="${3:-}"
  if [[ -n "${reason}" ]]; then
    printf '%s\t%s\t%s\n' "${state}" "${path}" "${reason}" >> "${DISCOVER_REPORT}"
  else
    printf '%s\t%s\n' "${state}" "${path}" >> "${DISCOVER_REPORT}"
  fi
}

should_skip_discover() {
  local repo="$1"
  local engine vault
  engine="$(cd "${CURSOR_DOCS_ENGINE}" && pwd)"
  vault="$(cd "${CURSOR_DOCS_VAULT}" && pwd)"
  [[ "${repo}" == "${engine}" || "${repo}" == "${vault}" ]]
}

discover_and_link() {
  local roots=()
  local root maxdepth repo gitdir reason
  need_cmd find
  load_config
  require_vault

  if [[ $# -gt 0 ]]; then
    roots=("$@")
  elif [[ -n "${CURSOR_DOCS_DISCOVER_ROOTS:-}" ]]; then
    local part
    IFS=':' read -r -a roots <<< "${CURSOR_DOCS_DISCOVER_ROOTS}"
    local cleaned=()
    for part in "${roots[@]}"; do
      [[ -n "${part}" ]] && cleaned+=("${part}")
    done
    roots=("${cleaned[@]}")
  fi
  [[ ${#roots[@]} -gt 0 ]] || die "usage: $0 discover [dir ...]  (or set CURSOR_DOCS_DISCOVER_ROOTS)"

  maxdepth="${CURSOR_DOCS_DISCOVER_MAXDEPTH}"
  [[ "${maxdepth}" =~ ^[1-9][0-9]*$ ]] || die "CURSOR_DOCS_DISCOVER_MAXDEPTH must be a positive integer (got: ${maxdepth})"

  DISCOVER_REPORT="${ENGINE_ROOT}/.discover-report"
  : > "${DISCOVER_REPORT}"

  for root in "${roots[@]}"; do
    [[ -d "${root}" ]] || die "not a directory: ${root}"
    root="$(cd "${root}" && pwd)"
    info "Discovering git repos under ${root} (maxdepth ${maxdepth})"
    while IFS= read -r -d '' gitdir; do
      repo="$(dirname "${gitdir}")"
      if should_skip_discover "${repo}"; then
        record_discover skipped "${repo}" "engine or vault"
        continue
      fi
      if reason="$("${ENGINE_ROOT}/scripts/ensure-linked.sh" "${repo}" 2>&1)"; then
        record_discover linked "${repo}"
        echo "${reason}"
      else
        echo "WARN: failed to link ${repo}" >&2
        echo "${reason}" >&2
        record_discover failed "${repo}" "${reason//$'\n'/ }"
      fi
    done < <(find "${root}" -maxdepth "${maxdepth}" -type d -name .git -print0 2>/dev/null)
  done
  echo "Discover report: ${DISCOVER_REPORT}"
}

load_config

cmd="${1:-setup}"
shift || true

case "${cmd}" in
  -h|--help|help) usage ;;
  setup) cmd_setup "$@" ;;
  update) cmd_update "$@" ;;
  status) cmd_status "$@" ;;
  link)
    [[ $# -ge 1 ]] || die "usage: $0 link <path-to-code-repo>"
    load_config
    "${ENGINE_ROOT}/scripts/ensure-linked.sh" "$1"
    ;;
  link-all)
    load_config
    "${ENGINE_ROOT}/scripts/link-all.sh"
    ;;
  discover) discover_and_link "$@" ;;
  unlink)
    [[ $# -ge 1 ]] || die "usage: $0 unlink <path-to-code-repo>"
    "${ENGINE_ROOT}/scripts/unlink-project.sh" "$1"
    ;;
  *)
    die "unknown command: ${cmd} (try: setup|update|status|link|link-all|discover|unlink)"
    ;;
esac
