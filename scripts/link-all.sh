#!/usr/bin/env bash
# Link every org/repo listed in the vault's links.local.toml.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib.sh"
load_config
require_vault

LINKS="${CURSOR_DOCS_VAULT}/links.local.toml"
LINK_SCRIPT="${SCRIPT_DIR}/link-project.sh"

if [[ ! -f "${LINKS}" ]]; then
  die "missing ${LINKS}. Copy links.local.example.toml and edit paths, or run ensure-linked.sh."
fi

parse_links() {
  python3 - <<'PY' "${LINKS}"
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
in_paths = False
for raw in text.splitlines():
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
    if key and value:
        print(f"{key}\t{value}")
PY
}

linked=0
skipped=0
while IFS=$'\t' read -r key path; do
  [[ -n "${key}" && -n "${path}" ]] || continue
  echo "==> ${key}"
  if [[ "${path}" == *"/Users/YOU/"* ]]; then
    echo "WARN: skipping placeholder path for ${key}" >&2
    skipped=$((skipped + 1))
    continue
  fi
  if [[ ! -d "${path}" ]]; then
    echo "WARN: skipping ${key} — code repo does not exist: ${path}" >&2
    skipped=$((skipped + 1))
    continue
  fi
  "${LINK_SCRIPT}" "${key}" "${path}"
  linked=$((linked + 1))
done < <(parse_links)

if [[ "${linked}" -eq 0 && "${skipped}" -eq 0 ]]; then
  die "no paths found in ${LINKS}"
fi

if [[ "${skipped}" -gt 0 ]]; then
  echo "Linked ${linked} project(s), skipped ${skipped}."
else
  echo "Linked ${linked} project(s)."
fi
