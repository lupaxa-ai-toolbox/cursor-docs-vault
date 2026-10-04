#!/usr/bin/env bash
# Local checks for cursor-docs-vault. Uses temporary git repositories only.
set -euo pipefail

ENGINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(mktemp -d "${TMPDIR:-/tmp}/cursor-docs-vault.XXXXXX")"
HOME_DIR="${ROOT}/home"
export HOME="${HOME_DIR}"
export GIT_AUTHOR_NAME="Vault Test"
export GIT_AUTHOR_EMAIL="vault-test@example.com"
export GIT_COMMITTER_NAME="Vault Test"
export GIT_COMMITTER_EMAIL="vault-test@example.com"

PASS=0
FAIL=0

cleanup() {
  rm -rf "${ROOT}"
}
trap cleanup EXIT

say() { printf '%s\n' "$*"; }

canon() {
  (cd "$1" && pwd)
}

pass() {
  PASS=$((PASS + 1))
  say "PASS: $1"
}

fail() {
  FAIL=$((FAIL + 1))
  say "FAIL: $1"
}

init_repo() {
  local path="$1"
  mkdir -p "${path}"
  git -C "${path}" init -b master >/dev/null
}

commit_all() {
  local path="$1"
  local message="$2"
  git -C "${path}" add -A
  git -C "${path}" commit -m "${message}" >/dev/null
}

new_vault() {
  local path="$1"
  init_repo "${path}"
  cp -R "${ENGINE}/vault-template/." "${path}/"
  commit_all "${path}" "Initial cursor-docs vault."
}

run_setup() {
  env CURSOR_DOCS_VAULT="$1" "${ENGINE}/bootstrap.sh" setup
}

# --- setup -----------------------------------------------------------------

setup_empty() {
  local vault="${ROOT}/setup-empty"
  init_repo "${vault}"
  run_setup "${vault}" >/dev/null
  [[ -f "${vault}/registry.toml" ]] || { fail "setup empty: missing registry"; return; }
  [[ -f "${vault}/projects/.gitkeep" ]] || { fail "setup empty: missing projects"; return; }
  git -C "${vault}" rev-parse --verify HEAD >/dev/null || { fail "setup empty: no commit"; return; }
  pass "setup copies template into an empty vault"
}

setup_keeps_registry() {
  local vault="${ROOT}/setup-keep"
  new_vault "${vault}"
  printf '\n# KEEP-ME\n' >> "${vault}/registry.toml"
  commit_all "${vault}" "Marker"
  run_setup "${vault}" >/dev/null
  grep -q 'KEEP-ME' "${vault}/registry.toml" || { fail "setup keep: marker missing"; return; }
  pass "setup leaves an existing registry.toml vault alone"
}

setup_refuses_unrelated() {
  local vault="${ROOT}/setup-unrelated"
  mkdir -p "${vault}"
  echo "notes" > "${vault}/notes.txt"
  if run_setup "${vault}" >/dev/null 2>&1; then
    fail "setup unrelated: expected failure"
    return
  fi
  [[ -f "${vault}/notes.txt" ]] || { fail "setup unrelated: file removed"; return; }
  pass "setup refuses an unrelated non-empty directory"
}

setup_refuses_git_without_registry() {
  local vault="${ROOT}/setup-noreg"
  init_repo "${vault}"
  echo "notes" > "${vault}/notes.txt"
  commit_all "${vault}" "Notes"
  if run_setup "${vault}" >/dev/null 2>&1; then
    fail "setup no registry: expected failure"
    return
  fi
  [[ -f "${vault}/notes.txt" ]] || { fail "setup no registry: file removed"; return; }
  pass "setup refuses a git repo with no registry.toml"
}

# --- ensure-linked ---------------------------------------------------------

link_with_origin() {
  local vault="${ROOT}/link-vault"
  local code="${ROOT}/link-code"
  new_vault "${vault}"
  init_repo "${code}"
  code="$(canon "${code}")"
  git -C "${code}" remote add origin "git@github.com:acme/widget.git"
  env CURSOR_DOCS_VAULT="${vault}" "${ENGINE}/scripts/ensure-linked.sh" "${code}" >/dev/null
  [[ -L "${code}/cursor-docs" ]] || { fail "link: not a symlink"; return; }
  [[ -d "${vault}/projects/acme/widget/superpowers/specs" ]] || { fail "link: missing specs dir"; return; }
  [[ -d "${vault}/projects/acme/widget/superpowers/plans" ]] || { fail "link: missing plans dir"; return; }
  grep -q 'org = "acme"' "${vault}/registry.toml" || { fail "link: registry org"; return; }
  grep -q 'repo = "widget"' "${vault}/registry.toml" || { fail "link: registry repo"; return; }
  grep -q "${code}" "${vault}/links.local.toml" || { fail "link: links.local"; return; }
  grep -qx 'cursor-docs' "${code}/.gitignore" || { fail "link: gitignore"; return; }
  pass "ensure-linked registers origin, symlink, and gitignore"
}

link_dot_github() {
  local vault="${ROOT}/dot-vault"
  local code="${ROOT}/dot-code"
  new_vault "${vault}"
  init_repo "${code}"
  git -C "${code}" remote add origin "git@github.com:acme/.github.git"
  env CURSOR_DOCS_VAULT="${vault}" "${ENGINE}/scripts/ensure-linked.sh" "${code}" >/dev/null
  [[ -d "${vault}/projects/acme/github" ]] || { fail "dot github: folder"; return; }
  [[ -d "${vault}/projects/acme/.github" ]] && { fail "dot github: hidden folder created"; return; }
  grep -q 'github = "acme/.github"' "${vault}/registry.toml" || { fail "dot github: registry"; return; }
  pass "dot-github repo uses folder github and keeps the real name"
}

link_no_origin() {
  local vault="${ROOT}/local-vault"
  local code="${ROOT}/local-checkout"
  new_vault "${vault}"
  init_repo "${code}"
  env CURSOR_DOCS_VAULT="${vault}" "${ENGINE}/scripts/ensure-linked.sh" "${code}" >/dev/null
  grep -q 'org = "local"' "${vault}/registry.toml" || { fail "no origin: org"; return; }
  grep -q 'repo = "local-checkout"' "${vault}/registry.toml" || { fail "no origin: repo"; return; }
  pass "checkout with no origin registers as local/directory"
}

link_unsafe() {
  local vault="${ROOT}/unsafe-vault"
  local code="${ROOT}/unsafe-code"
  new_vault "${vault}"
  init_repo "${code}"
  git -C "${code}" remote add origin "git@github.com:bad org/widget.git"
  if env CURSOR_DOCS_VAULT="${vault}" "${ENGINE}/scripts/ensure-linked.sh" "${code}" >/dev/null 2>&1; then
    fail "unsafe: expected failure"
    return
  fi
  pass "unsafe org name exits with an error"
}

link_migrate() {
  local vault="${ROOT}/mig-vault"
  local code="${ROOT}/mig-code"
  new_vault "${vault}"
  init_repo "${code}"
  git -C "${code}" remote add origin "git@github.com:acme/migrated.git"
  mkdir -p "${code}/cursor-docs/superpowers/specs"
  echo "moved" > "${code}/cursor-docs/superpowers/specs/note.md"
  env CURSOR_DOCS_VAULT="${vault}" "${ENGINE}/scripts/ensure-linked.sh" "${code}" >/dev/null
  [[ -f "${vault}/projects/acme/migrated/superpowers/specs/note.md" ]] || { fail "migrate: file missing"; return; }
  [[ -L "${code}/cursor-docs" ]] || { fail "migrate: not a symlink"; return; }
  pass "real cursor-docs directory is moved when the vault project is empty"
}

link_refuses_overwrite() {
  local vault="${ROOT}/over-vault"
  local code="${ROOT}/over-code"
  new_vault "${vault}"
  init_repo "${code}"
  git -C "${code}" remote add origin "git@github.com:acme/occupied.git"
  mkdir -p "${vault}/projects/acme/occupied"
  echo "keep" > "${vault}/projects/acme/occupied/keep.txt"
  mkdir -p "${code}/cursor-docs"
  echo "local" > "${code}/cursor-docs/local.txt"
  if env CURSOR_DOCS_VAULT="${vault}" "${ENGINE}/scripts/ensure-linked.sh" "${code}" >/dev/null 2>&1; then
    fail "overwrite: expected failure"
    return
  fi
  [[ -f "${vault}/projects/acme/occupied/keep.txt" ]] || { fail "overwrite: vault file lost"; return; }
  [[ -f "${code}/cursor-docs/local.txt" ]] || { fail "overwrite: local file lost"; return; }
  pass "real cursor-docs is left untouched when the vault project has files"
}

link_noop_and_replace() {
  local vault="${ROOT}/sym-vault"
  local code="${ROOT}/sym-code"
  new_vault "${vault}"
  init_repo "${code}"
  git -C "${code}" remote add origin "git@github.com:acme/sym.git"
  env CURSOR_DOCS_VAULT="${vault}" "${ENGINE}/scripts/ensure-linked.sh" "${code}" >/dev/null
  local second
  second="$(env CURSOR_DOCS_VAULT="${vault}" "${ENGINE}/scripts/ensure-linked.sh" "${code}")"
  printf '%s\n' "${second}" | grep -q 'Already linked:' || { fail "noop: missing Already linked"; return; }
  rm "${code}/cursor-docs"
  ln -s /tmp "${code}/cursor-docs"
  local replaced
  replaced="$(env CURSOR_DOCS_VAULT="${vault}" "${ENGINE}/scripts/ensure-linked.sh" "${code}")"
  printf '%s\n' "${replaced}" | grep -q 'Replacing existing symlink' || { fail "replace: missing message"; return; }
  [[ "$(readlink "${code}/cursor-docs")" == "$(canon "${vault}")/projects/acme/sym" ]] || { fail "replace: target"; return; }
  pass "correct symlink is a no-op and a wrong symlink is replaced"
}

sync_ignores_links_local() {
  local vault="${ROOT}/sync-vault"
  local code="${ROOT}/sync-code"
  new_vault "${vault}"
  init_repo "${code}"
  git -C "${code}" remote add origin "git@github.com:acme/synced.git"
  env CURSOR_DOCS_VAULT="${vault}" "${ENGINE}/scripts/ensure-linked.sh" "${code}" >/dev/null
  local out
  out="$(env CURSOR_DOCS_VAULT="${vault}" "${ENGINE}/scripts/sync-vault.sh")"
  printf '%s\n' "${out}" | grep -q 'remote is missing' || { fail "sync: missing remote message"; return; }
  if git -C "${vault}" ls-files --error-unmatch links.local.toml >/dev/null 2>&1; then
    fail "sync: links.local.toml was staged"
    return
  fi
  pass "vault commit does not stage links.local.toml"
}

# --- discover --------------------------------------------------------------

discover_mixed() {
  local scan="${ROOT}/scan"
  local vault="${scan}/vault"
  local engine="${scan}/engine"
  local good="${scan}/good"
  local bad="${scan}/bad"
  new_vault "${vault}"
  init_repo "${engine}"
  init_repo "${good}"
  init_repo "${bad}"
  git -C "${good}" remote add origin "git@github.com:acme/good.git"
  git -C "${bad}" remote add origin "git@github.com:bad org/nope.git"
  bad="$(canon "${bad}")"
  engine="$(canon "${engine}")"
  vault="$(canon "${vault}")"
  env CURSOR_DOCS_VAULT="${vault}" CURSOR_DOCS_ENGINE="${engine}" \
    "${ENGINE}/bootstrap.sh" discover "${scan}" >/dev/null
  [[ -L "${good}/cursor-docs" ]] || { fail "discover: good repo not linked"; return; }
  if [[ -L "${bad}/cursor-docs" ]]; then
    fail "discover: bad repo was linked"
    return
  fi
  if [[ -L "${engine}/cursor-docs" ]]; then
    fail "discover: engine was linked"
    return
  fi
  if [[ -L "${vault}/cursor-docs" ]]; then
    fail "discover: vault was linked"
    return
  fi
  grep -q $'failed\t'"${bad}" "${ENGINE}/.discover-report" || { fail "discover: failure not recorded"; return; }
  grep -q $'skipped\t'"${engine}" "${ENGINE}/.discover-report" || { fail "discover: engine not skipped"; return; }
  grep -q $'skipped\t'"${vault}" "${ENGINE}/.discover-report" || { fail "discover: vault not skipped"; return; }
  pass "discover skips engine and vault, records a failure, and links the rest"
}

# --- install ---------------------------------------------------------------

install_skill() {
  env HOME="${HOME_DIR}" "${ENGINE}/scripts/install-skill.sh" >/dev/null
  [[ -f "${HOME_DIR}/.cursor/skills/cursor-docs-vault/SKILL.md" ]] || { fail "install: skill"; return; }
  [[ -f "${HOME_DIR}/.cursor/rules/cursor-docs-vault.mdc" ]] || { fail "install: rule"; return; }
  pass "install copies the skill and the rule into HOME"
}

# --- update fast-forward ---------------------------------------------------

update_refuses_diverge() {
  local base="${ROOT}/ff-base"
  local vault="${ROOT}/ff-vault"
  new_vault "${base}"
  git clone "${base}" "${vault}" >/dev/null
  echo "left" >> "${base}/registry.toml"
  commit_all "${base}" "Left"
  echo "right" >> "${vault}/registry.toml"
  commit_all "${vault}" "Right"
  if env CURSOR_DOCS_VAULT="${vault}" "${ENGINE}/bootstrap.sh" update >/dev/null 2>&1; then
    fail "update: expected fast-forward failure"
    return
  fi
  pass "update stops when the vault cannot fast-forward"
}

setup_empty
setup_keeps_registry
setup_refuses_unrelated
setup_refuses_git_without_registry
link_with_origin
link_dot_github
link_no_origin
link_unsafe
link_migrate
link_refuses_overwrite
link_noop_and_replace
sync_ignores_links_local
discover_mixed
install_skill
update_refuses_diverge

say
say "Passed: ${PASS}  Failed: ${FAIL}"
[[ "${FAIL}" -eq 0 ]]
