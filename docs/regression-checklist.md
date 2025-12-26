# 回归测试清单

适用于 hz-oneclick 仓库在合并前的基础回归验证，每次改动都需覆盖以下检查。

## 通用预检
- **脚本语法**：对关键脚本执行 `bash -n`，至少覆盖 `modules/wp` 的标准 WP 安装脚本，按需补充入口脚本（如 `hz.sh`）。
- **静态扫描**：运行 `shellcheck`（需启用 `-x` 以跟踪引用）覆盖与改动相关的脚本。
- **禁止词校验**：在脚本的用户输出（`echo` / `printf` 文案）中 grep，确保不含具体云厂商名称；提示关于解析、端口、入站/出站规则需保持中性描述。
- **Loopback 预检**：确认标准 WP 安装脚本包含本机 HTTPS loopback/REST API 预检，且使用 `openssl s_client` + `curl --resolve` 进行 SNI/回环检查。
- **Loopback hosts 标记**：使用 `rg` 确认脚本中存在 `# hz-oneclick loopback begin` / `# hz-oneclick loopback end` 标记字符串。
- **中性输出**：新增/调整的 loopback/hosts 修复提示保持中性描述，不出现云厂商名称。
- **菜单标识**：进入中英文菜单确认展示 Version/Build 与 Source/Base URL 行，确保与本次构建一致。
- **DB Grant 源地址**：使用 `rg` 确认脚本中不存在硬编码的 DB 用户来源 IP/Host（例如 `100.x.x.x`）。

## 场景回归
- **安装菜单 13（LOMP/LNMP 档位选择）**
  - 选择 13 后应进入档位选择子菜单。
  - LOMP-Lite / LOMP-Standard 会启动 WordPress 安装流程。
  - 其余档位显示 “Coming soon”/“敬请期待” 并安全返回主菜单。
  - Lite/Standard 安装后应自动生成 wp-config.php，不再需要通过浏览器 setup-config.php 配置数据库。

- **低内存节点 (<4G RAM)**
  - 推荐档位应为 **Lite（Frontend-only）**，理由需展示为“内存 <4G”并提示仅部署前端。
  - 路径确认：Lite 流程不触碰数据库/Redis 本地安装与清理入口，仅保留前端部署；如需 DB/Redis，应在外部节点提前就绪并通过内网/隧道访问。
  - 输出确认：说明下一步需准备可达的数据库与 Redis 连接信息，提示保持端口/防火墙文案中性，不带云厂商名称。
  - Lite 预检：数据库 DNS/IP 可达、端口 TCP 可达、MySQL 认证通过；提示 DB_USER_HOST 策略并完成连接预检；Redis 选择启用时需完成 TCP/PING 检查或提示缺少 redis-cli；缺失客户端时可选安装 default-mysql-client/mariadb-client 与 redis-tools。
  - Lite 预检失败时：输出包含 DB Host-side Fix Guide（SQL 模板 + Docker 端口/防火墙提示），文本仍保持中性。

- **高配 ARM 节点 (>=16G RAM)**
  - 推荐档位应遵循现有逻辑自动给出 **Standard / Hub** 方案，输出需包含内存判定理由与下一步指引。
    - Standard：单站前后端一体，可选将 DB/Redis 外置以提升稳定性。
    - Hub：集中承载 DB/Redis、多站复用的场景，或按需继续使用 Standard。
  - 输出确认：描述应保持中性（仅引用内存/端口/连接等客观信息），不出现云厂商名称，并给出后续准备动作（资源预留、连接校验等）。

## 结果记录
- 在 PR 的 **Testing** 小节列出已执行的命令（如 `bash -n ...`、`shellcheck ...`、禁止词 grep 等），确保可复现。
