# Tests

Bats coverage for the pure helpers in `scripts/lib/`:

- `workspace-bootstrap.sh` (shared by `setup.sh`, `create-workspace.sh`, and `init.sh`)
- `workspace-status.sh` (shared by `status.sh`)

## Scope

- `workspace-bootstrap.sh`: `sed_esc`, `configure_api_env`, `configure_webapp_env`,
  `configure_workspace_env`. `install_deps` and `bootstrap_laravel` are intentionally
  **not** covered here — they shell out to `composer`/`npm`/`php` and are side-effect
  heavy rather than config-only.
- `workspace-status.sh`: `read_env_value`, `truncate_field`, `workspace_branch`,
  `classify_process_table`. The actual `overmind status` invocation in `status.sh` is
  intentionally **not** covered here — it talks to a real Overmind socket and is
  side-effect heavy. Every state `classify_process_table` can produce is instead
  reproduced with literal fixture text standing in for that command's captured stdout.

## Running locally

Install [Bats](https://github.com/bats-core/bats-core):

```bash
brew install bats-core
```

Run the full suite:

```bash
bats -r tests/
```

Or a single file:

```bash
bats tests/lib/workspace_status.bats
```

## Layout

```
tests/
├── fixtures/
│   └── api.env.example        # minimal Laravel .env.example used by configure_api_env tests
└── lib/
    ├── workspace_bootstrap.bats
    └── workspace_status.bats
```

Each test that touches the filesystem uses a fresh temp directory (`mktemp -d`) via
`setup()`/`teardown()`, so tests never touch a real workspace and can run in any order.

## Platform

`workspace-bootstrap.sh` uses macOS-specific `sed -i ''` syntax (matching the
supported dev-lab platform), so this suite runs on `macos-latest` in CI
(`.github/workflows/bats-macos.yml`) rather than Linux.
