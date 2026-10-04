#!/usr/bin/env bash
# Commit vault registry and project docs. Never stage links.local.toml.
# Push when an upstream exists. Otherwise leave the commit local.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib.sh"
load_config
require_vault
need_cmd git

cd "${CURSOR_DOCS_VAULT}"

MESSAGE="${1:-Update cursor-docs vault.}"
to_add=()
for path in README.md .gitignore registry.toml links.local.example.toml projects; do
  if [[ -e "${path}" ]]; then
    to_add+=("${path}")
  fi
done
if [[ ${#to_add[@]} -gt 0 ]]; then
  git add -- "${to_add[@]}"
fi
if git ls-files --error-unmatch links.local.toml >/dev/null 2>&1; then
  git reset -q HEAD -- links.local.toml
fi

if git diff --cached --quiet; then
  echo "Nothing to commit in ${CURSOR_DOCS_VAULT}"
else
  git commit -m "${MESSAGE}"
  echo "Committed vault changes in ${CURSOR_DOCS_VAULT}"
fi

if git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
  git push
  echo "Pushed ${CURSOR_DOCS_VAULT}"
else
  echo "remote is missing; vault commit left local."
fi
