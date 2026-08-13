# Tests

Bats coverage for the pure configuration helpers in `scripts/lib/workspace-bootstrap.sh`
(shared by `setup.sh`, `create-workspace.sh`, and `init.sh`).

## Scope

- `sed_esc`, `configure_api_env`, `configure_webapp_env`, `configure_workspace_env`
- `install_deps` and `bootstrap_laravel` are intentionally **not** covered here — they
  shell out to `composer`/`npm`/`php` and are side-effect heavy rather than config-only.

## Running locally

Install [Bats](https://github.com/bats-core/bats-core):

```bash
brew install bats-core
```

Run the suite:

```bash
bats tests/lib/workspace_bootstrap.bats
```

## Layout

```
tests/
├── fixtures/
│   └── api.env.example        # minimal Laravel .env.example used by configure_api_env tests
└── lib/
    └── workspace_bootstrap.bats
```

Each test copies `tests/fixtures/api.env.example` into a fresh temp directory
(`mktemp -d`) via `setup()`/`teardown()`, so tests never touch a real workspace
and can run in any order.

## Platform

`workspace-bootstrap.sh` uses macOS-specific `sed -i ''` syntax (matching the
supported dev-lab platform), so this suite runs on `macos-latest` in CI
(`.github/workflows/bats-macos.yml`) rather than Linux.
