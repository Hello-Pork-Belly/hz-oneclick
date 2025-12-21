# hz-oneclick

HorizonTech 的一键安装脚本合集。

> ⚠️ 重要说明
> 这些脚本目前 **主要在部分云供应商提供的免费 VPS（ARM / x86）+ Ubuntu 22.04 / 24.04 上做过测试**。
> 其它平台或发行版可能可以用，但需要你自己多做验证。
> **所有脚本都视为实验性质（Experimental），请在可回滚环境中使用，并自行做好备份。**

## 仓库定位

- 为 HorizonTech 各篇教程提供「一行命令」的安装入口  
- 把共用步骤（比如 rclone、Docker、基础优化）做成可复用模块  
- 方便读者 fork 后根据自己的环境修改

示例目标（规划中）：

- Immich 部署到 VPS
- rclone 网盘挂载（OneDrive 等）
- Plex / Transmission / Tailscale / 反向代理隧道等常用组件

## 预计使用方式（规划中）

未来会提供类似命令：

```bash
bash <(curl -fsSL https://sh.horizontech.page)

```
或直接从 GitHub Raw 调用：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Fat-Pork-Belly/hz-oneclick/main/hz.sh)
```

## 贡献与提交流程

- 每个步骤或独立功能对应一个 PR，保持范围小、便于 review 和回滚。
- 推荐使用前缀命名 PR 标题（如 `feat/xxx`、`fix/xxx`、`chore/xxx`、`docs/xxx` 或 `refactor/xxx`）。
- 合并前必须通过 CI 检查。
- PR 描述需严格按照模板填写，并确保 Summary、Testing 等必填项完整。

## CI 说明

### Run CI checks locally

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

### Real-machine E2E (self-hosted)

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

### PR Smoke（快速检查）

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

### Full Regression（完整回归）

- 触发方式：手动触发 `Full Regression` 工作流（`workflow_dispatch`），以及每周定时（默认每周一凌晨）。
- 执行内容：`tests/full_regression.sh`（完整 baseline 回归 + quick triage JSON）。
- 本地运行：

```bash
CI=false BASELINE_TEST_MODE=1 HZ_TRIAGE_TEST_MODE=1 bash tests/full_regression.sh
```

- 全量回归默认 `HZ_SMOKE_STRICT=1`，WARN 会直接失败并触发上传。
- 失败、WARN 或步骤失败时会上传 `artifacts/full-regression/` 以及 `/tmp/hz-baseline-triage-*.json|.txt`，用于回归排查。

## Sensitive docs policy

- 规划文档、架构图、环境与基础设施细节必须保存在私有位置，不得提交到公共仓库。
- 如需参考结构，可使用 `docs/templates/wp-architecture-plan.template.md` 中的公共占位模板，在本地复制后填充实际信息。

## Baseline Quick Triage

- 直接运行：`bash <(curl -fsSL https://raw.githubusercontent.com/Fat-Pork-Belly/hz-oneclick/main/modules/diagnostics/quick-triage.sh)`（可选语言 en/zh），按提示输入要诊断的域名（示例：`abc.yourdomain.com`）。
- 终端会输出 `VERDICT:` / `KEY:` / `REPORT:` 行，完整报告会写到 `/tmp/` 目录，文件名带时间戳和域名（示例：`/tmp/hz-baseline-triage-abc.yourdomain.com-20240101-120000.txt`）。
- 报告内容已脱敏，反馈问题时优先提供 `KEY:` 行以及 `REPORT:` 路径或内容，方便他人复现和定位，无需粘贴整份日志。
- 需要机器可读的结果时，追加 `--format json`（保持默认的人类可读输出不变）：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Fat-Pork-Belly/hz-oneclick/main/modules/diagnostics/quick-triage.sh) --format json
```

- JSON 模式会同时生成文本报告和 JSON 报告（同目录、文件名带 `.json`），末尾输出四行摘要，便于 CI 或日志采集解析：
  - `VERDICT: <PASS|WARN|FAIL>`
  - `KEY: <关键词列表>`
  - `REPORT: <文本报告路径>`
  - `REPORT_JSON: <JSON 报告路径>`
- JSON 与文本报告同样经过脱敏处理，措辞保持供应商中立（以 `abc.yourdomain.com` 等占位符为例）。
- JSON 输出包含 `schema_version`、`generated_at` 等标准字段，方便脚本或 CI 校验结构。
- Baseline Diagnostics JSON Schema 存放在 `docs/schema/baseline_diagnostics.schema.json`，CI 也会用它做回归校验（示例命令的域名请继续使用 `example.com`、`abc.yourdomain.com` 等占位符）。
- 需要进一步收敛敏感信息时，可追加 `--redact` 触发可选脱敏模式（域名、IP、邮箱、绝对路径会替换为 `<redacted-domain>`、`<redacted-ip>`、`<redacted-email>`、`<redacted-path>` 等占位符）。
  - 仅用 JSON 输出：`bash <(curl -fsSL https://raw.githubusercontent.com/Fat-Pork-Belly/hz-oneclick/main/modules/diagnostics/quick-triage.sh) --format json`
  - 仅用脱敏输出：`bash <(curl -fsSL https://raw.githubusercontent.com/Fat-Pork-Belly/hz-oneclick/main/modules/diagnostics/quick-triage.sh) --redact`
  - 同时开启：`bash <(curl -fsSL https://raw.githubusercontent.com/Fat-Pork-Belly/hz-oneclick/main/modules/diagnostics/quick-triage.sh) --format json --redact`

## Baseline Diagnostics 菜单入口

- 运行 `hz.sh` 后，可在主菜单中选择「Baseline Diagnostics / 基础诊断」进入单独的诊断子菜单（先选择语言、可选输入域名）。
- 子菜单提供一键 Quick Triage，也可以按组单独运行（DNS/IP、源站/防火墙、代理/CDN、TLS/HTTPS、LSWS/OLS、WP/App、缓存/Redis/OPcache、系统/资源）。
- 所有诊断脚本支持 `--format text|json`（默认 text），保持人类可读输出不变的同时提供 JSON 报告。
- 示例命令：

```bash
curl -fsSL https://raw.githubusercontent.com/Fat-Pork-Belly/hz-oneclick/main/hz.sh -o hz.sh
bash hz.sh
```

- 也可以直接拉取某个基线分组的封装脚本，例如只跑 DNS/IP 组：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Fat-Pork-Belly/hz-oneclick/main/modules/diagnostics/baseline-dns-ip.sh) "example.com" en
```
