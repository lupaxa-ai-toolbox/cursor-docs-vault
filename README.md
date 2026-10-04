<p align="center">
    <a href="https://github.com/lupaxa-ai-toolbox">
        <img src="https://raw.githubusercontent.com/the-lupaxa-project/brand-assets/master/logos/organisations/ai-toolbox/readme-logo.png" alt="Organisation Logo" />
    </a>
</p>

<h1 align="center">Cursor Docs Vault</h1>

Share Cursor agent specs and plans from one private vault across a team's repositories.

Each code checkout keeps a `cursor-docs` symlink. The specs and plans themselves stay in a private git repository the team owns.

## Setup

```bash
git clone https://github.com/lupaxa-ai-toolbox/cursor-docs-vault.git
cd cursor-docs-vault
cp config.example.env config.local.env
```

Edit `config.local.env` and set `CURSOR_DOCS_VAULT` to the directory for your private vault. Set `CURSOR_DOCS_VAULT_URL` when that directory does not exist yet and `setup` should clone it.

```bash
./bootstrap.sh setup
./bootstrap.sh link /absolute/path/to/a-code-checkout
./bootstrap.sh discover /absolute/path/to/a-source-tree
./bootstrap.sh status
```

`./bootstrap.sh update` pulls the engine and the vault, reinstalls the skill, and refreshes links.

Start a new Cursor agent after setup so the skill loads.

<a href="https://github.com/the-lupaxa-project">
    <img src="https://raw.githubusercontent.com/the-lupaxa-project/brand-assets/master/logos/components/footer-for-child-orgs.svg" alt="The Lupaxa Project Footer" width="100%" />
</a>
