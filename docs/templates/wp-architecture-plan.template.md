# WP 架构阶段计划（模板）

本模板用于记录 WP 架构规划和落地进度。请在私有环境中填写，并将所有示例占位符替换为实际信息后，避免提交到公共仓库。

章节完成状态标识：
- 🟩 已完成 / Done
- 🟨 进行中 / In Progress
- 🟥 未开始 / Not Started

🟩 十九、LOMP / LNMP 生产环境落地
【第十九章里程碑（示例占位）】
- 🟩 Step19-1: 完成 LOMP / LNMP 生产形态落地与基础硬化的验证与记录（示例环境：`arm-node-1.example.com`、`x86-node-1.example.com`；示例路径：`/var/www/<site>/html`）。

🟩 二十、Baseline Diagnostics 统一基线诊断
【第二十章里程碑（示例占位）】
- 🟩 Step20-1: 明确 Baseline Diagnostics 范围与交付物，梳理各分组诊断入口。
- 🟩 Step20-2: 补充语言选择与域名输入提示，统一交互体验（示例域名：`abc.yourdomain.com`）。
- 🟩 Step20-3: 提供 DNS/IP 诊断分组，覆盖解析、连通性与地域链路。
- 🟩 Step20-4: 提供源站 / 防火墙分组，涵盖回源连通性与阻断排查。
- 🟩 Step20-5: 提供 Proxy/CDN 分组，覆盖常见 30x/40x/50x 以及缓存命中检查。
- 🟩 Step20-6: 提供 TLS/HTTPS 分组，聚焦证书、协议与加密套件检测（示例证书域名：`example.com`）。
- 🟩 Step20-7: 将 Proxy/CDN（521/TLS）检查项纳入菜单流程，便于快速选择。
- 🟩 Step20-8: 将 TLS/CERT（SNI/SAN/链/到期）检查项纳入菜单流程，形成标准化清单。
- 🟩 Step20-9: 将 WP/App（运行态 + HTTP）检查项纳入菜单流程，覆盖核心运行健康度。
- 🟩 Step20-10: 将 LSWS/OLS（服务/端口/配置/日志）检查项纳入菜单流程，便于定位服务异常。
- 🟩 Step20-11: 将 Cache/Redis/OPcache 检查项纳入菜单流程，覆盖缓存与 opcode 协同。
- 🟩 Step20-12: 将 System/Resource（CPU/内存/磁盘/Swap/日志）检查项纳入菜单流程，补齐资源维度。
- 🟩 Step20-13: 输出 Quick Triage 结构化报告（VERDICT/KEY/REPORT），方便人工与自动解析。
- 🟩 Step20-14: 封装 Quick Triage 独立入口，统一临时文件生成与路径提示（示例路径：`/tmp/hz-baseline-triage-abc.yourdomain.com-YYYYMMDD-HHMMSS.txt`）。
- 🟩 Step20-15: 对文本输出与日志进行脱敏与中立化，避免暴露环境特征。
- 🟩 Step20-16: 收紧敏感词扫描范围，仅覆盖终端可见的脚本与输出。
- 🟩 Step20-17: 对齐 Baseline 分组脚本与菜单封装，确保多语言与参数透传一致。
- 🟩 Step20-18: 为 Quick Triage 增加 JSON 输出模式，补充机器可读的报告与摘要。
- 🟩 Step20-19: 扩展 Baseline Diagnostics 的 JSON 输出（菜单/格式透传 + 封装脚本产出 JSON 报告）。
- 🟩 Step20-20: 稳定 JSON contract 并增加校验（`schema_version` / `generated_at` 等必填字段 + 冒烟校验）。
- 🟩 Step20-21: 提供 JSON Schema 与 CI 校验（示例路径：`docs/schema/baseline_diagnostics.schema.json`；示例域名：`example.com`）。

> 提示：请根据实际环境在私有文档中填写真实主机名、域名、路径等信息。公共仓库仅保留此模板，不应包含任何敏感细节。
