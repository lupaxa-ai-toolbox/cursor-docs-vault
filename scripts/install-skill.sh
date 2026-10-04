#!/usr/bin/env bash
# Install the cursor-docs-vault skill and rule into ~/.cursor/.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib.sh"

HOME_DIR="${HOME}"
SKILL_SRC="${ENGINE_ROOT}/skills/cursor-docs-vault"
RULE_SRC="${ENGINE_ROOT}/rules/cursor-docs-vault.mdc"
SKILL_DEST="${HOME_DIR}/.cursor/skills/cursor-docs-vault"
RULE_DEST="${HOME_DIR}/.cursor/rules/cursor-docs-vault.mdc"

[[ -f "${SKILL_SRC}/SKILL.md" ]] || die "missing ${SKILL_SRC}/SKILL.md"
[[ -f "${RULE_SRC}" ]] || die "missing ${RULE_SRC}"

mkdir -p "${SKILL_DEST}" "${HOME_DIR}/.cursor/rules"
rm -rf "${SKILL_DEST}"
mkdir -p "${SKILL_DEST}"
cp -R "${SKILL_SRC}/." "${SKILL_DEST}/"
cp "${RULE_SRC}" "${RULE_DEST}"

echo "Installed skill -> ${SKILL_DEST}"
echo "Installed rule -> ${RULE_DEST}"
