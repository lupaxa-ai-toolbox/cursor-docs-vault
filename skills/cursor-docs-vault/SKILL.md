---
name: cursor-docs-vault
description: >-
  Keep Cursor agent specs and plans in one shared private vault. Use before
  writing a spec or plan, when linking a code checkout, or when the user asks
  to set up cursor-docs-vault.
---

# cursor-docs-vault

Agent specs and plans for every code checkout live in one private git vault.
Each code checkout's `cursor-docs` path is a symlink into that vault. The code
repository does not store those files.

## Before writing specs or plans

Run this from the engine checkout. Do not ask whether to link.

```bash
ENGINE="${CURSOR_DOCS_ENGINE:-$HOME/cursor-docs-vault}"
"$ENGINE/scripts/ensure-linked.sh" "$(git rev-parse --show-toplevel)"
```

Then write under `cursor-docs/superpowers/specs/` and `cursor-docs/superpowers/plans/`.

After changing `registry.toml` or those docs, sync the vault:

```bash
"$ENGINE/scripts/sync-vault.sh"
```

`links.local.toml` stays uncommitted. It is machine-local.

## Rules

- Do not create a real `cursor-docs/` directory in a code repository.
- Do not commit `cursor-docs` in the code repository. It is a symlink and belongs in `.gitignore`.
- The `.gitignore` line is the only vault-related change that belongs in the code repository.
- If `sync-vault.sh` prints `remote is missing`, leave the commit local and say so.

## Example prompts

- `Link this repo into the cursor-docs vault`
- `Write a design spec for this feature`
- `Set up cursor-docs-vault on this machine`
