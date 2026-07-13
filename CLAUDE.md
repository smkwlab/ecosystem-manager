# CLAUDE.md

Cross-repository management tool for the LaTeX thesis-writing ecosystem at
Kyushu Sangyo University (smkwlab). An Elixir escript that reports the status
of every repository in an ecosystem workspace (branches, uncommitted changes,
open PRs, issues) using parallel processing and the GitHub API.

This repository was split out of `smkwlab/latex-ecosystem` (see
latex-ecosystem#123); the tool no longer depends on living inside the
management repository — workspaces are resolved from user configuration.

## Build & Run

```bash
mix deps.get
mix escript.build            # produces ./ecosystem-manager

./ecosystem-manager status           # status of all repos in the workspace
./ecosystem-manager status --long    # detailed: branch, changes, PRs, issues
./ecosystem-manager status --no-github  # fast, no GitHub API calls
./ecosystem-manager repos            # show resolved repositories and sources
./ecosystem-manager config           # show current configuration
```

The escript is run from the ecosystem workspace root, or from anywhere once a
`workspace_path` / `workspaces` entry is set in
`~/.config/ecosystem-manager/config.exs` (`./ecosystem-manager init-config`).
Repositories are auto-discovered under the workspace; there is no hardcoded
list. See README.md for configuration and multi-workspace details.

## Development

```bash
mix test                     # test suite (coverage threshold 90%)
mix test --cover             # coverage report
mix format && mix credo && mix dialyzer   # quality checks
```

TDD: write tests before implementation. Match the surrounding code's style.

## CI

`.github/workflows/ci.yml` calls the org-standard reusable workflow
`smkwlab/.github/.github/workflows/elixir-ci.yml@v1` (mix test / credo /
dialyzer), the same setup as `registry-manager`. `.github/workflows/
ai-code-review.yml` runs the org AI review on pull requests.

## Conventions

- Commits: Conventional Commits, English, reference the issue number
- Branches: feature branches in English; do not commit directly to `main`
- Pull Requests: PR-based review; do not merge without explicit instruction
