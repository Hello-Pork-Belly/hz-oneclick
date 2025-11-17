# hz-oneclick

HorizonTech 的一键安装脚本合集。

> ⚠️ 重要说明  
> 这些脚本目前 **只在 Oracle Cloud 免费 VPS（ARM / x86）+ Ubuntu 22.04 / 24.04 上做过测试**。  
> 其它云厂商或发行版可能可以用，但需要你自己多做验证。  
> **所有脚本都视为实验性质（Experimental），请在可回滚环境中使用，并自行做好备份。**

## 仓库定位

- 为 HorizonTech 各篇教程提供「一行命令」的安装入口  
- 把共用步骤（比如 rclone、Docker、基础优化）做成可复用模块  
- 方便读者 fork 后根据自己的环境修改

示例目标（规划中）：

- Immich 部署到 VPS / OCI
- rclone 网盘挂载（OneDrive 等）
- Plex / Transmission / Tailscale / Cloudflare Tunnel 等常用组件

## 预计使用方式（规划中）

未来会提供类似命令：

```bash
bash <(curl -fsSL https://sh.horizontech.page)

```
或直接从 GitHub Raw 调用：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Fat-Pork-Belly/hz-oneclick/main/hz.sh)
