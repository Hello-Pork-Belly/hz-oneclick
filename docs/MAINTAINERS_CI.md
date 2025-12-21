# Maintainers: CI & runners

> Maintainers only. End users installing via curl do **not** need any CI or runner setup.

## Public installer endpoint

- Public install uses `https://sh.horizontech.eu.org` (served as a bash script).
- CI verifies the public endpoint on GitHub-hosted runners; no self-hosted runner is needed.
- Self-hosted/manual verification can set `HZ_PUBLIC_INSTALLER_STRICT=1` to fail CI if the download is blocked.

## Run CI checks locally

Prerequisites: bash, grep, curl (optional: shellcheck, shfmt).

```bash
bash .github/scripts/run_ci_locally.sh
```

```bash
bash .github/scripts/lint_bash.sh
```

```bash
bash .github/scripts/smoke_gating.sh self-test
```

## Real-machine E2E (self-hosted)

- Runner labels must include:
  - x64: `self-hosted`, `linux`, `x64`, `hz-e2e-x64`
  - arm64: `self-hosted`, `linux`, `arm64`, `hz-e2e-arm64`
- Trigger the `E2E Self-hosted` workflow via `workflow_dispatch` and set inputs:
  - `mode`: `preflight` (default, non-destructive) or `install`
  - `confirm_install`: must be exactly `I_UNDERSTAND_THIS_WILL_MODIFY_THE_MACHINE` to allow `mode=install`
  - `smoke_strict`: toggle strict smoke gating (maps to `HZ_SMOKE_STRICT`)
  - `notes`: optional run notes (printed to logs)
- Safety model: defaults to preflight checks only; install mode is blocked unless the confirmation string is provided.
- Intended for dedicated test machines only.
- Validates the same local CI parity checks via `.github/scripts/run_ci_locally.sh` on real machines.

## PR Smoke（快速检查）

- 触发方式：`pull_request` / `push`。
- 执行内容：`tests/smoke.sh`（强制开启 smoke 模式，带超时，避免挂起）。
- 本地运行（模拟 CI smoke）：

```bash
HZ_CI_SMOKE=1 bash tests/smoke.sh
```

- 可选环境变量：`HZ_SMOKE_STRICT=1` 将 WARN 视为失败（默认 0）。
- `tests/smoke.sh` 的退出码语义：
  - `VERDICT=PASS` ➜ exit 0
  - `VERDICT=WARN` ➜ `HZ_SMOKE_STRICT=0` 时 exit 0，`HZ_SMOKE_STRICT=1` 时 exit 1
  - `VERDICT=FAIL` ➜ exit 1
  - verdict 缺失/未知或出现内部错误 ➜ exit 2
- PR smoke 出现 WARN 会在 GitHub Actions 中生成 warning annotation（默认不失败）。
- PR smoke 在 WARN/FAIL 或步骤失败时会在 Actions 的 Artifacts 中上传 `smoke-triage-reports`，包含 `/tmp/hz-baseline-triage-*.txt` 和 `/tmp/hz-baseline-triage-*.json`。

## Full Regression（完整回归）

- 触发方式：手动触发 `Full Regression` 工作流（`workflow_dispatch`），以及每周定时（默认每周一凌晨）。
- 执行内容：`tests/full_regression.sh`（完整 baseline 回归 + quick triage JSON）。
- 本地运行：

```bash
CI=false BASELINE_TEST_MODE=1 HZ_TRIAGE_TEST_MODE=1 bash tests/full_regression.sh
```

- 全量回归默认 `HZ_SMOKE_STRICT=1`，WARN 会直接失败并触发上传。
- 失败、WARN 或步骤失败时会上传 `artifacts/full-regression/` 以及 `/tmp/hz-baseline-triage-*.json|.txt`，用于回归排查。
