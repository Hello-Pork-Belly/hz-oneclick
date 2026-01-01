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

## Features

- 🛡️ 运维与安全中心 (Ops & Security Center)
  - Fail2Ban：保护 SSH + WordPress 登录/接口免受暴力破解（基于日志自动封禁）。
  - Postfix Relay：邮件告警发送（Null Client / 仅发送，通过 Brevo/Gmail 等 SMTP 中继）。
  - Rclone Backup：每日备份（数据库 + 网站文件）同步到云端（Google Drive/OneDrive 等，取决于你的 rclone remote）。
  - HealthCheck：每日健康检查（“Silence is Golden”：只有异常才发邮件）。

## Quick Start (Public)

安装器负责搭建基础环境；运维中心负责安全/备份/告警/监控。你也可以在已有服务器上独立运行这些模块，无需完整走一遍安装流程。

## Version / Changelog / Release Notes

- v2.2.1 (2026-01-01)
  - New Ops & Security Center menu
  - New security layer (Fail2Ban)
  - New notification layer (Postfix relay)
  - New backup layer (Rclone backup job)
  - New observability layer (daily healthcheck alerts)

示例目标（规划中）：

- Immich 部署到 VPS
- rclone 网盘挂载（OneDrive 等）
- Plex / Transmission / Tailscale / 反向代理隧道等常用组件

## 预计使用方式（规划中）

未来会提供类似命令：

```bash
bash <(curl -fsSL https://sh.horizontech.eu.org)

```

可选备用（GitHub Raw）：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Hello-Pork-Belly/hz-oneclick/main/hz.sh)
```

安装后可在 Optimize → 运维与安全中心 中启用 Fail2Ban / 邮件告警 / 备份 / 健康检查。

## 贡献与提交流程

- 每个步骤或独立功能对应一个 PR，保持范围小、便于 review 和回滚。
- 推荐使用前缀命名 PR 标题（如 `feat/xxx`、`fix/xxx`、`chore/xxx`、`docs/xxx` 或 `refactor/xxx`）。
- 合并前必须通过 CI 检查。
- PR 描述需严格按照模板填写，并确保 Summary、Testing 等必填项完整。

## 本地开发快速入口（canonical entrypoints）

使用 Makefile 作为本地执行入口（canonical entrypoints）：

- `make help`
- `make lint`
- `make lint-strict`（需要 shellcheck/shfmt；CI 会安装）
- `make smoke`
- `make ci`

规则：Use Makefile targets and `scripts/lint.sh`/`scripts/ci_local.sh`; do not reference deprecated CI helpers.

## 贡献指南

贡献说明请见 [`docs/CONTRIBUTING.md`](docs/CONTRIBUTING.md)。

## CI 说明

CI 与 GitHub Actions/self-hosted runners 仅供维护者与验证使用，公开用户通过 curl 安装时不需要配置任何 runner。维护者说明见 `docs/CONTRIBUTING.md` 的 Maintainers / CI notes 章节。

Smoke 在本地或 CI 中会在临时目录生成 `smoke-report.txt` 与 `smoke-report.json`；CI 会上传 `smoke-triage-reports` artifact 供排查。

## Sensitive docs policy

- 规划文档、架构图、环境与基础设施细节必须保存在私有位置，不得提交到公共仓库。
- 如需参考结构，可使用 `docs/templates/wp-architecture-plan.template.md` 中的公共占位模板，在本地复制后填充实际信息。

## Baseline Quick Triage

- 直接运行：`bash <(curl -fsSL https://raw.githubusercontent.com/Hello-Pork-Belly/hz-oneclick/main/modules/diagnostics/quick-triage.sh)`（可选语言 en/zh），按提示输入要诊断的域名（示例：`abc.yourdomain.com`）。Replace placeholder domains with your real domain.
- 终端会输出 `VERDICT:` / `KEY:` / `REPORT:` 行，完整报告会写到 `/tmp/` 目录，文件名带时间戳和域名（示例：`/tmp/hz-baseline-triage-abc.yourdomain.com-20240101-120000.txt`）。
- 报告内容已脱敏，反馈问题时优先提供 `KEY:` 行以及 `REPORT:` 路径或内容，方便他人复现和定位，无需粘贴整份日志。
- 需要机器可读的结果时，追加 `--format json`（保持默认的人类可读输出不变）：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Hello-Pork-Belly/hz-oneclick/main/modules/diagnostics/quick-triage.sh) --format json
```

- JSON 模式会同时生成文本报告和 JSON 报告（同目录、文件名带 `.json`），末尾输出四行摘要，便于 CI 或日志采集解析：
  - `VERDICT: <PASS|WARN|FAIL>`
  - `KEY: <关键词列表>`
  - `REPORT: <文本报告路径>`
  - `REPORT_JSON: <JSON 报告路径>`
- JSON 与文本报告同样经过脱敏处理，措辞保持供应商中立（以 `abc.yourdomain.com` 等占位符为例）。
- JSON 输出包含 `schema_version`、`generated_at` 等标准字段，方便脚本或 CI 校验结构。
- Baseline Diagnostics JSON Schema 存放在 `docs/schema/baseline_diagnostics.schema.json`，CI 也会用它做回归校验（示例命令的域名请继续使用 `abc.yourdomain.com`、`123.yourdomain.com` 等占位符）。
- 需要进一步收敛敏感信息时，可追加 `--redact` 触发可选脱敏模式（域名、IP、邮箱、绝对路径会替换为 `<redacted-domain>`、`<redacted-ip>`、`<redacted-email>`、`<redacted-path>` 等占位符）。
  - 仅用 JSON 输出：`bash <(curl -fsSL https://raw.githubusercontent.com/Hello-Pork-Belly/hz-oneclick/main/modules/diagnostics/quick-triage.sh) --format json`
  - 仅用脱敏输出：`bash <(curl -fsSL https://raw.githubusercontent.com/Hello-Pork-Belly/hz-oneclick/main/modules/diagnostics/quick-triage.sh) --redact`
  - 同时开启：`bash <(curl -fsSL https://raw.githubusercontent.com/Hello-Pork-Belly/hz-oneclick/main/modules/diagnostics/quick-triage.sh) --format json --redact`

## Baseline Diagnostics 菜单入口

- 运行 `hz.sh` 后，可在主菜单中选择「Baseline Diagnostics / 基础诊断」进入单独的诊断子菜单（先选择语言、可选输入域名）。
- 子菜单提供一键 Quick Triage，也可以按组单独运行（DNS/IP、源站/防火墙、代理/CDN、TLS/HTTPS、LSWS/OLS、WP/App、缓存/Redis/OPcache、系统/资源）。
- 所有诊断脚本支持 `--format text|json`（默认 text），保持人类可读输出不变的同时提供 JSON 报告。
- 示例命令：

```bash
curl -fsSL https://raw.githubusercontent.com/Hello-Pork-Belly/hz-oneclick/main/hz.sh -o hz.sh
bash hz.sh
```

- 也可以直接拉取某个基线分组的封装脚本，例如只跑 DNS/IP 组：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Hello-Pork-Belly/hz-oneclick/main/modules/diagnostics/baseline-dns-ip.sh) "abc.yourdomain.com" en
```
