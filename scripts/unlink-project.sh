#!/usr/bin/env bash
# Remove a code checkout's cursor-docs symlink. Vault files stay in place.
#
# Usage:
#   ./scripts/unlink-project.sh <path-to-code-repo>
set -euo pipefail

[[ $# -eq 1 ]] || { echo "Usage: $0 <path-to-code-repo>" >&2; exit 2; }
CODE_REPO="$1"
[[ -d "${CODE_REPO}" ]] || { echo "ERROR: code repo does not exist: ${CODE_REPO}" >&2; exit 1; }
CODE_REPO="$(cd "${CODE_REPO}" && pwd)"
LINK_PATH="${CODE_REPO}/cursor-docs"

if [[ ! -L "${LINK_PATH}" ]]; then
  echo "ERROR: ${LINK_PATH} is not a symlink." >&2
  exit 1
fi

rm "${LINK_PATH}"
echo "Removed symlink ${LINK_PATH}"
