#!/usr/bin/env bash
# Link <vault>/projects/<org>/<repo> to <code-repo>/cursor-docs
#
# Usage:
#   ./scripts/link-project.sh <org> <repo> <absolute-path-to-code-repo>
#   ./scripts/link-project.sh <org>/<repo> <absolute-path-to-code-repo>
#
# Requires CURSOR_DOCS_VAULT (see config.local.env).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib.sh"
load_config
require_vault

usage() {
  echo "Usage: $0 <org> <repo> <absolute-path-to-code-repo>" >&2
  echo "   or: $0 <org>/<repo> <absolute-path-to-code-repo>" >&2
  exit 2
}

if [[ $# -eq 3 ]]; then
  ORG="$1"
  REPO="$2"
  CODE_REPO="$3"
elif [[ $# -eq 2 && "$1" == */* ]]; then
  ORG="${1%%/*}"
  REPO="${1#*/}"
  CODE_REPO="$2"
else
  usage
fi

safe_name org "${ORG}"
safe_name repo "${REPO}"

[[ -d "${CODE_REPO}" ]] || die "code repo does not exist: ${CODE_REPO}"
CODE_REPO="$(cd "${CODE_REPO}" && pwd)"

VAULT_PROJECT="${CURSOR_DOCS_VAULT}/projects/${ORG}/${REPO}"
LINK_PATH="${CODE_REPO}/cursor-docs"

mkdir -p "${VAULT_PROJECT}/superpowers/specs" "${VAULT_PROJECT}/superpowers/plans"

if [[ -L "${LINK_PATH}" ]]; then
  current="$(readlink "${LINK_PATH}")"
  if [[ "${current}" == "${VAULT_PROJECT}" ]]; then
    echo "Already linked: ${LINK_PATH} -> ${VAULT_PROJECT}"
    exit 0
  fi
  echo "Replacing existing symlink ${LINK_PATH} (-> ${current})"
  rm "${LINK_PATH}"
elif [[ -e "${LINK_PATH}" ]]; then
  die "${LINK_PATH} exists and is not a symlink. Run ensure-linked.sh to migrate it."
fi

gitignore="${CODE_REPO}/.gitignore"
marker="# Agent specs and plans (symlink into the cursor-docs vault)"
if [[ ! -f "${gitignore}" ]]; then
  printf '%s\ncursor-docs\n' "${marker}" > "${gitignore}"
  echo "Created ${gitignore} with cursor-docs"
elif ! grep -qE '^cursor-docs/?$' "${gitignore}" 2>/dev/null; then
  printf '\n%s\ncursor-docs\n' "${marker}" >> "${gitignore}"
  echo "Appended cursor-docs to ${gitignore}"
fi

ln -s "${VAULT_PROJECT}" "${LINK_PATH}"
echo "Linked ${LINK_PATH} -> ${VAULT_PROJECT}"
