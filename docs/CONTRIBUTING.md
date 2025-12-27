# Contributing

This repo keeps local developer checks aligned with CI. Use the Makefile targets below to run the same lint/smoke commands locally.
Canonical commands are Makefile targets and `scripts/lint.sh` / `scripts/ci_local.sh`. Do not reference deprecated helpers.

## Prereqs
- bash
- make
- Optional (installed in CI): shellcheck, shfmt
  - CI installs tooling via `.github/scripts/install_ci_tools.sh`.

## Quickstart
From the repo root:
- `make help` — list available targets
- `make lint` — non-strict lint checks (CI-aligned)
- `make lint-strict` — strict lint checks
- `make smoke` — CI-safe smoke test entrypoint
- `make ci` — run lint-strict then smoke

## Smoke artifacts
The smoke runner (`tests/smoke.sh`) writes report files for quick triage:
- Text report: `smoke-report.txt`
- JSON report: `smoke-report.json`

By default, these are created under a temp directory such as `/tmp/hz-smoke-XXXXXXXX/`. You can also override the directory by setting `HZ_SMOKE_REPORT_DIR` before running `make smoke`.

In CI, the smoke step uploads artifacts named `smoke-triage-reports`, which include the text/JSON reports plus any `/tmp/hz-baseline-triage-*.txt` and `/tmp/hz-baseline-triage-*.json` files produced by the smoke suite.
