#!/usr/bin/env bash
# Link one code checkout into the private cursor-docs vault.
#
# Usage:
#   ./scripts/ensure-linked.sh <path-to-code-repo>
#   ./scripts/ensure-linked.sh            # uses the current directory
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib.sh"
load_config
require_vault

CODE_REPO_INPUT="${1:-.}"
[[ -d "${CODE_REPO_INPUT}" ]] || die "code repo does not exist: ${CODE_REPO_INPUT}"
CODE_REPO="$(cd "${CODE_REPO_INPUT}" && pwd)"

ENGINE_REAL="$(cd "${CURSOR_DOCS_ENGINE}" && pwd)"
if [[ "${CODE_REPO}" == "${ENGINE_REAL}" || "${CODE_REPO}" == "${CURSOR_DOCS_VAULT}" ]]; then
  die "refusing to link the engine or the vault into the vault: ${CODE_REPO}"
fi

ORG=""
GITHUB_REPO=""
parse_origin() {
  local remote cleaned pathpart
  if git -C "${CODE_REPO}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    remote="$(git -C "${CODE_REPO}" remote get-url origin 2>/dev/null || true)"
    if [[ -n "${remote}" ]]; then
      cleaned="${remote%.git}"
      pathpart=""
      if [[ "${cleaned}" == git@*:* ]]; then
        pathpart="${cleaned#*:}"
      elif [[ "${cleaned}" == *github.com/* ]]; then
        pathpart="${cleaned#*github.com/}"
      elif [[ "${cleaned}" == *:*/* ]]; then
        pathpart="${cleaned##*:}"
      fi
      if [[ -n "${pathpart}" && "${pathpart}" == */* ]]; then
        ORG="${pathpart%/*}"
        GITHUB_REPO="${pathpart##*/}"
      fi
    fi
  fi
  if [[ -z "${GITHUB_REPO}" ]]; then
    GITHUB_REPO="$(basename "${CODE_REPO}")"
  fi
  if [[ -z "${ORG}" ]]; then
    ORG="local"
  fi
}

parse_origin
REPO="$(vault_repo_name "${GITHUB_REPO}")"
GITHUB_FULL="${ORG}/${GITHUB_REPO}"
KEY="${ORG}/${REPO}"

safe_name org "${ORG}"
[[ -n "${REPO}" ]] || die "empty vault repo name after stripping dots from '${GITHUB_REPO}'"
safe_name repo "${REPO}"

VAULT_PROJECT="${CURSOR_DOCS_VAULT}/projects/${ORG}/${REPO}"
LINK_PATH="${CODE_REPO}/cursor-docs"
REGISTRY="${CURSOR_DOCS_VAULT}/registry.toml"
LINKS_LOCAL="${CURSOR_DOCS_VAULT}/links.local.toml"

echo "==> ensure-linked"
echo "    vault:   ${CURSOR_DOCS_VAULT}"
echo "    org:     ${ORG}"
echo "    repo:    ${REPO}  (github: ${GITHUB_REPO})"
echo "    path:    ${KEY}"
echo "    checkout:${CODE_REPO}"

project_has_files() {
  [[ -d "${VAULT_PROJECT}" ]] || return 1
  local item
  for item in "${VAULT_PROJECT}"/* "${VAULT_PROJECT}"/.[!.]* "${VAULT_PROJECT}"/..?*; do
    [[ -e "${item}" ]] && return 0
  done
  return 1
}

migrate_real_cursor_docs() {
  local src="$1"
  local dest="$2"
  mkdir -p "${dest}"
  local item base
  for item in "${src}"/* "${src}"/.[!.]* "${src}"/..?*; do
    [[ -e "${item}" ]] || continue
    base="$(basename "${item}")"
    cp -R "${item}" "${dest}/${base}"
  done
  rm -rf "${src}"
  echo "Migrated real cursor-docs/ into ${dest}"
}

if [[ -e "${LINK_PATH}" && ! -L "${LINK_PATH}" ]]; then
  if project_has_files; then
    die "vault project already has files: ${VAULT_PROJECT}"
  fi
  migrate_real_cursor_docs "${LINK_PATH}" "${VAULT_PROJECT}"
fi

ensure_registry() {
  mkdir -p "${CURSOR_DOCS_VAULT}/projects"
  if [[ ! -f "${REGISTRY}" ]]; then
    cat > "${REGISTRY}" <<EOF
# Canonical projects for this vault.
# Docs live at: projects/<org>/<repo>/superpowers/{specs,plans}/

[[projects]]
org = "${ORG}"
repo = "${REPO}"
github = "${GITHUB_FULL}"
notes = "Auto-registered by ensure-linked.sh"
EOF
    echo "Created ${REGISTRY}"
    return
  fi

  python3 - <<'PY' "${REGISTRY}" "${ORG}" "${REPO}" "${GITHUB_FULL}"
import sys
from pathlib import Path

path, org, repo, github = Path(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4]
text = path.read_text(encoding="utf-8")
blocks = text.split("[[projects]]")
for block in blocks[1:]:
    o = r = None
    for line in block.splitlines():
        s = line.split("#", 1)[0].strip()
        if s.startswith("org ") and "=" in s:
            o = s.split("=", 1)[1].strip().strip('"').strip("'")
        elif s.startswith("repo ") and "=" in s:
            r = s.split("=", 1)[1].strip().strip('"').strip("'")
    if o == org and r == repo:
        print(f"Already registered {org}/{repo}")
        raise SystemExit(0)

entry = f'''
[[projects]]
org = "{org}"
repo = "{repo}"
github = "{github}"
notes = "Auto-registered by ensure-linked.sh"
'''
if not text.endswith("\n"):
    text += "\n"
path.write_text(text + entry)
print(f"Registered {org}/{repo} in registry.toml")
PY
}

ensure_registry

python3 - <<'PY' "${LINKS_LOCAL}" "${KEY}" "${CODE_REPO}"
import sys
from pathlib import Path

path, key, repo = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
text = path.read_text(encoding="utf-8") if path.exists() else "[paths]\n"
lines = text.splitlines()
out = []
in_paths = False
seen = False
quoted_key = f'"{key}"'

def key_matches(raw_key: str) -> bool:
    k = raw_key.strip().strip('"').strip("'")
    return k == key

for raw in lines:
    stripped = raw.split("#", 1)[0].strip()
    if stripped.startswith("[") and stripped.endswith("]"):
        section = stripped.strip("[]").strip()
        if in_paths and not seen:
            out.append(f'{quoted_key} = "{repo}"')
            seen = True
        in_paths = section == "paths"
        out.append(raw)
        continue
    if in_paths and "=" in stripped:
        left = stripped.split("=", 1)[0].strip()
        if key_matches(left):
            out.append(f'{quoted_key} = "{repo}"')
            seen = True
            continue
    out.append(raw)
if in_paths and not seen:
    out.append(f'{quoted_key} = "{repo}"')
    seen = True
if not seen:
    if out and out[-1].strip():
        out.append("")
    out.append("[paths]")
    out.append(f'{quoted_key} = "{repo}"')
path.write_text("\n".join(out) + "\n", encoding="utf-8")
print(f"Updated {path} ({key})")
PY

"${SCRIPT_DIR}/link-project.sh" "${ORG}" "${REPO}" "${CODE_REPO}"

[[ -L "${LINK_PATH}" ]] || die "${LINK_PATH} is not a symlink after linking"
target="$(readlink "${LINK_PATH}")"
[[ "${target}" == "${VAULT_PROJECT}" ]] || die "unexpected link target: ${target} (expected ${VAULT_PROJECT})"

echo "OK: ${LINK_PATH} -> ${target}"
