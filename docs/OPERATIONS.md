# 64M sing-box VLESS + REALITY 运维说明

> 本文根据当前仓库的安装脚本 `setup-singbox-reality.sh`、GitHub Actions 工作流 `.github/workflows/sync-sing-box.yml` 以及最近的代码变更整理。
>
> 适用对象：使用 Alpine Linux、约 64 MB 内存 VPS 部署 sing-box VLESS + REALITY + Vision 的管理员。

## 1. 项目结构

```text
64M-sing-box-vless-vision/
├── .github/
│   └── workflows/
│       └── sync-sing-box.yml       # 同步官方 sing-box musl 核心
├── setup-singbox-reality.sh        # 安装、配置、更新、状态管理脚本
├── README.md                       # 快速开始
└── docs/
    └── OPERATIONS.md               # 本文：脚本与 CI/CD 运维说明
```

项目的核心职责可以分为两部分：

1. **服务器侧部署**：安装脚本负责 Alpine/OpenRC 环境中的 sing-box 安装、配置生成和服务管理。
2. **核心发布同步**：GitHub Actions 从官方 `SagerNet/sing-box` Release 获取 Linux musl 二进制，提取 amd64/arm64 核心并发布到本仓库的 Release，供安装脚本下载。

---

## 2. 安装脚本工作方式

脚本入口为 `setup-singbox-reality.sh`，解释器使用 Alpine 默认的 `ash`，并启用 `set -eu`，因此未定义变量或未处理的命令错误会终止脚本。

### 2.1 支持的运行方式

直接从仓库执行：

```sh
wget -qO- https://raw.githubusercontent.com/opyzzzz/64M-sing-box-vless-vision/refs/heads/main/setup-singbox-reality.sh | sh
```

或：

```sh
curl -fsSL https://raw.githubusercontent.com/opyzzzz/64M-sing-box-vless-vision/refs/heads/main/setup-singbox-reality.sh | sh
```

脚本要求 root 权限，并通过交互菜单提供安装、更新配置、查看状态以及 sing-box 核心更新等操作。

### 2.2 sing-box 版本解析

脚本默认核心版本为 `1.13.21`，同时支持：

- 默认版本：`1.13.21`
- `latest`：使用本仓库最新 Release
- 指定版本：例如 `1.13.22`

指定版本会被规范化为不带 `v` 的版本号；下载目标 Release tag 使用 `v<版本>-multi`。

`latest` 不直接下载官方 GitHub Release，而是使用本仓库的最新 Release。这是整个项目能够在低内存 VPS 上稳定使用的关键：GitHub Actions 先把官方 musl 包转换成仓库自己的轻量二进制 Release。

### 2.3 CPU 架构

目前脚本明确支持：

| 系统架构 | sing-box 架构 | 仓库 Release 文件 |
|---|---|---|
| `x86_64` / `amd64` | `amd64` | `sing-box-amd64` |
| `aarch64` / `arm64` | `arm64` | `sing-box-arm64` |

其他架构会直接终止并提示不支持。

### 2.4 下载与安全校验

安装/更新核心时，脚本会：

1. 检测 `wget` 或 `curl`。
2. 创建临时下载文件。
3. 下载对应架构的二进制。
4. 执行 `sing-box version` 验证文件可运行。
5. 读取实际版本号并与请求版本比较。
6. 如果已经存在配置，先使用新核心执行 `sing-box check -c config.json`。
7. 只有检查成功后才替换 `/usr/local/bin/sing-box`。

临时文件在脚本退出时通过 `trap` 清理。

因此，**核心更新不会先覆盖旧核心再发现新核心不可用**；配置检查失败时会保留当前正在使用的旧核心。

---

## 3. VLESS + REALITY + Vision 配置

默认部署参数为：

| 项目 | 默认值 |
|---|---|
| 协议 | VLESS |
| 传输 | TCP |
| TLS/安全层 | REALITY |
| Flow | `xtls-rprx-vision` |
| Fingerprint | Chrome（节点信息按当前脚本输出） |
| 监听地址 | `0.0.0.0` |
| 监听端口 | `443` |
| 默认 SNI | `www.cloudflare.com` |
| REALITY handshake 端口 | `443` |
| 出站 | `direct` |

脚本会在安装/更新配置时重新生成：

- UUID
- REALITY private key
- REALITY public key
- Short ID

配置文件写入后权限为 `600`。

### 3.1 更新配置与更新核心的区别

这是运维时最重要的区别：

**更新配置**会重新生成身份和 REALITY 参数，因此旧节点链接会失效。

**更新 sing-box 核心**只替换二进制，并检查现有配置；正常情况下会保留：

- UUID
- REALITY 密钥
- Short ID
- 现有 `config.json`

因此，如果只是升级 sing-box 版本，应使用“更新 sing-box 核心”，不要通过重新生成配置来实现版本升级。

---

## 4. OpenRC 服务

脚本会生成 `/etc/init.d/sing-box`，并加入 OpenRC 默认启动级别。

服务执行的核心命令等价于：

```sh
/usr/local/bin/sing-box run -c /usr/local/etc/sing-box/config.json
```

针对低内存 VPS，服务环境设置了：

```text
GOMEMLIMIT=32MiB
GOGC=25
```

同时脚本在更新核心前会尝试降低 SSH/当前进程被 OOM Killer 处理的风险，并在核心更新期间停止 sing-box，以减少 64 MB 内存环境中的峰值压力。

常用命令：

```sh
rc-service sing-box status
rc-service sing-box start
rc-service sing-box stop
rc-service sing-box restart
```

日志：

```sh
tail -f /var/log/sing-box/sing-box.log

tail -f /var/log/sing-box/error.log
```

---

## 5. 文件与敏感信息位置

| 文件 | 用途 |
|---|---|
| `/usr/local/bin/sing-box` | sing-box 可执行文件 |
| `/usr/local/etc/sing-box/config.json` | 服务端配置 |
| `/etc/init.d/sing-box` | OpenRC 服务定义 |
| `/root/singbox-vless-reality-info.txt` | 生成后的节点信息/VLESS 链接 |
| `/var/log/sing-box/sing-box.log` | 主日志 |
| `/var/log/sing-box/error.log` | 错误日志 |

其中 `config.json`、节点信息文件以及 REALITY private key 属于敏感信息，不应提交到 Git 仓库或公开粘贴。

---

## 6. GitHub Actions：核心同步流程

工作流文件：`.github/workflows/sync-sing-box.yml`

工作流名称：`Sync sing-box Release`

### 6.1 触发方式

支持两种触发方式：

#### 定时检查

每 6 小时执行一次：

```yaml
cron: "17 */6 * * *"
```

它检查官方 `SagerNet/sing-box` 的最新稳定 Release。

#### 手动执行

通过 `workflow_dispatch` 执行时，可以指定：

- `version`：`latest`、`1.13.21`、`v1.13.21` 等
- `force`：是否覆盖已经存在的目标 Release

### 6.2 版本映射

工作流的版本转换关系为：

```text
官方 Release
SagerNet/sing-box
        │
        │ v1.13.21
        ▼
本仓库 Release
v1.13.21-multi
```

例如官方版本为 `v1.13.21`，工作流生成的目标 Release tag 为：

```text
v1.13.21-multi
```

这样可以与官方 Release 清晰区分，同时保持安装脚本的下载地址稳定。

### 6.3 下载的官方资产

工作流首先检查官方 Release 是否存在以下 musl 包：

```text
sing-box-<version>-linux-amd64-musl.tar.gz
sing-box-<version>-linux-arm64-musl.tar.gz
```

然后执行：

1. 下载官方压缩包。
2. 使用 `gzip -t` 检查 gzip 数据完整性。
3. 使用 `tar -tzf` 检查 tar 包完整性。
4. 解压并定位 `sing-box` 二进制。
5. 重新命名为 `sing-box-amd64` 和 `sing-box-arm64`。
6. 使用 `file` 检查二进制。
7. 执行 amd64 二进制的 `version` 命令。
8. 将实际版本与预期版本比较。
9. 生成 `SHA256SUMS`。
10. 创建或更新目标 Release。

最终 Release 包含：

```text
sing-box-amd64
sing-box-arm64
SHA256SUMS
```

### 6.4 已存在 Release 时的行为

为了避免定时任务反复修改 Release，工作流默认采用幂等策略：

```text
目标 Release 已存在
        │
        ├── force=false → SKIP，不下载、不修改
        │
        └── force=true  → 重新上传资产并更新 Release
```

工作流使用 `concurrency` 将同步任务限制在同一个组内，并关闭取消进行中的任务，从而避免多个同步任务同时修改同一个 Release。

工作流需要：

```yaml
permissions:
  contents: write
```

因为它需要创建/更新本仓库 Release。

---

## 7. 端到端更新链路

整个项目的版本更新链路如下：

```text
官方 SagerNet/sing-box Release
              │
              ▼
GitHub Actions 每 6 小时检查
              │
              ▼
检查 amd64/arm64 musl 官方资产
              │
              ▼
下载 → 完整性检查 → 解压
              │
              ▼
运行 version 验证版本
              │
              ▼
生成 SHA256SUMS
              │
              ▼
创建 vX.Y.Z-multi Release
              │
              ▼
Alpine 安装脚本读取仓库 Release
              │
              ▼
下载对应架构 sing-box 二进制
              │
              ▼
sing-box version + config check
              │
              ▼
安装/更新 /usr/local/bin/sing-box
              │
              ▼
OpenRC 启动并执行运行状态检查
```

这个设计把“从上游 Release 获取完整压缩包”和“在 64 MB VPS 上实际运行核心”分离开来，VPS 不需要自行下载、解压官方 tar.gz，也不需要安装额外的构建工具。

---

## 8. 故障排查

### 8.1 核心下载失败

先确认服务器可以访问 GitHub Release，并检查：

```sh
command -v wget
command -v curl
```

然后手动查看当前脚本使用的 Release URL 是否可访问。

### 8.2 新核心无法通过配置检查

更新流程会执行：

```sh
/usr/local/bin/sing-box check -c /usr/local/etc/sing-box/config.json
```

如果失败，脚本不会用未通过检查的新核心替换现有核心。优先查看配置内容及 sing-box 版本兼容性。

### 8.3 服务无法启动

执行：

```sh
rc-service sing-box status
cat /var/log/sing-box/error.log
/usr/local/bin/sing-box check -c /usr/local/etc/sing-box/config.json
```

如果端口冲突，再检查：

```sh
ss -lntp
```

### 8.4 更新后客户端节点失效

如果执行的是“更新配置”而不是“更新核心”，这是预期行为：脚本会重新生成 UUID、REALITY 密钥和 Short ID。

重新读取：

```sh
cat /root/singbox-vless-reality-info.txt
```

然后重新导入新的 VLESS 节点。

---

## 9. 维护建议

1. **仅升级核心时，优先使用核心更新功能**，不要重新生成配置。
2. **升级前确认 VPS 有足够可用内存**；该项目已经针对 64 MB 环境设置了 Go 内存参数并在更新时停止服务，但极低内存环境仍可能受系统状态影响。
3. **不要把 `/root/singbox-vless-reality-info.txt` 或 `config.json` 提交到仓库**。
4. **变更 SNI 前先确认目标站点适合作为 REALITY handshake 目标**，并在实际客户端验证连通性。
5. **定期关注官方 sing-box Release 的兼容性变化**。自动同步只负责二进制发布，不会自动修改服务端配置格式。
6. **如果需要强制重新同步已经存在的版本**，手动运行工作流并将 `force` 设置为 `true`。

---

## 10. 当前实现摘要

截至本文编写时，仓库的实现重点为：

- Alpine Linux + OpenRC。
- VLESS + TCP + REALITY + `xtls-rprx-vision`。
- amd64 / arm64 两种架构。
- 默认 sing-box `1.13.21`。
- 本仓库通过 GitHub Actions 同步官方 musl Release。
- 自动检查下载核心是否可执行。
- 更新前检查现有配置。
- 更新配置与更新核心分离。
- OpenRC 开机启动。
- 低内存环境下设置 Go 内存参数。
- GitHub Actions 自动生成 SHA256 校验文件。
- 已存在 Release 默认跳过，手动 `force=true` 才覆盖。

> 版本号、工作流行为和脚本实现可能随仓库后续提交变化；如果本文与代码不一致，应以仓库当前的脚本和 workflow 为准。
