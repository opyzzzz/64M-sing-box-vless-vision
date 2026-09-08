# 64M sing-box VLESS + REALITY 运维说明

> 本文根据当前仓库的安装脚本 `setup-singbox-reality.sh` 和 GitHub Actions 工作流 `.github/workflows/sync-sing-box.yml` 编写。
>
> 适用对象：使用 Alpine Linux、OpenRC、约 64 MB 内存 VPS 部署 sing-box VLESS + REALITY + Vision 的管理员。

## 1. 项目结构

```text
64M-sing-box-vless-vision/
├── .github/
│   └── workflows/
│       └── sync-sing-box.yml       # 同步官方 sing-box musl 核心
├── setup-singbox-reality.sh        # 安装、配置、更新、状态管理脚本
├── README.md                       # 快速开始
└── docs/
    └── OPERATIONS.md               # 本文：运维说明
```

项目分为两部分：

1. **服务器侧部署**：安装脚本负责 Alpine/OpenRC 环境中的 sing-box 安装、配置生成、核心更新和服务管理。
2. **核心发布同步**：GitHub Actions 从官方 `SagerNet/sing-box` Release 获取 Linux musl 压缩包，提取 amd64/arm64 二进制并发布到本仓库 Release，供安装脚本下载。

---

## 2. 安装脚本

脚本入口：`setup-singbox-reality.sh`

脚本使用 Alpine 的 `ash`，启用 `set -eu`，要求 root 权限。

### 2.1 远程执行

使用 wget：

```sh
wget -qO- https://raw.githubusercontent.com/opyzzzz/64M-sing-box-vless-vision/refs/heads/main/setup-singbox-reality.sh | sh
```

使用 curl：

```sh
curl -fsSL https://raw.githubusercontent.com/opyzzzz/64M-sing-box-vless-vision/refs/heads/main/setup-singbox-reality.sh | sh
```

主菜单：

```text
1) 安装 sing-box
2) 更新 sing-box 核心
3) 更新配置
4) 查看状态
0) 退出
```

---

## 3. sing-box 版本与 Release 规则

当前默认版本为：

```text
1.13.21
```

脚本支持三种选择：

```text
1) 默认版本 1.13.21
2) Latest（本仓库最新 Release）
3) 指定版本号
```

指定版本可以输入：

```text
1.13.21
```

也兼容：

```text
v1.13.21
```

脚本内部会去掉开头的 `v`，统一使用纯版本号。

### 3.1 本仓库 Release 命名

新版 Release 采用非常简单的命名方式：

| 项目 | 示例 |
|---|---|
| Tag | `1.13.21` |
| Release title | `1.13.21-musl` |
| amd64 | `sing-box-amd64` |
| arm64 | `sing-box-arm64` |
| 校验文件 | `SHA256SUMS` |

**Tag 不使用 `v`，也不再使用 `-multi`。**

例如版本 `1.13.21` 的实际下载地址为：

```text
https://github.com/opyzzzz/64M-sing-box-vless-vision/releases/download/1.13.21/sing-box-amd64
```

ARM64：

```text
https://github.com/opyzzzz/64M-sing-box-vless-vision/releases/download/1.13.21/sing-box-arm64
```

Latest 则使用 GitHub 的 latest 下载入口：

```text
https://github.com/opyzzzz/64M-sing-box-vless-vision/releases/latest/download/sing-box-amd64
https://github.com/opyzzzz/64M-sing-box-vless-vision/releases/latest/download/sing-box-arm64
```

因此安装脚本不需要预先知道 Latest 的版本号。

### 3.2 版本校验

脚本下载二进制后执行：

```sh
sing-box version
```

然后读取实际版本号。

- 指定版本：实际版本必须与请求版本一致。
- Latest：以下载到的二进制实际版本作为当前版本。

这样可以避免“检测到一个版本、实际下载另一个版本”的问题。

---

## 4. 支持的 CPU 架构

当前项目只考虑两种架构：

| 系统架构 | Release 文件 |
|---|---|
| `x86_64` / `amd64` | `sing-box-amd64` |
| `aarch64` / `arm64` | `sing-box-arm64` |

其他架构不在当前项目范围内，脚本会直接提示不支持。

不考虑 i386、ARMv7、MIPS、RISC-V、PPC64LE、s390x 等架构。

---

## 5. 安装与核心更新

### 5.1 安装 sing-box

选择：

```text
1) 安装 sing-box
```

安装流程会：

1. 选择版本。
2. 检测 CPU 架构。
3. 检测 `wget` 或 `curl`。
4. 从本仓库 Release 下载对应二进制。
5. 验证二进制可以执行。
6. 验证实际版本。
7. 生成 VLESS + REALITY 配置所需参数。
8. 写入 OpenRC 服务。
9. 检查配置并启动服务。
10. 输出节点信息和 VLESS 链接。

### 5.2 更新 sing-box 核心

选择：

```text
2) 更新 sing-box 核心
```

更新核心与更新配置是两件不同的事情。

核心更新流程：

```text
选择版本
   ↓
停止正在运行的 sing-box
   ↓
下载新核心到临时文件
   ↓
验证 sing-box version
   ↓
检查现有 config.json
   ↓
替换 /usr/local/bin/sing-box
   ↓
如果更新前正在运行，则启动并检查状态
```

如果已有配置，脚本会先使用下载的新核心执行：

```sh
/usr/local/tmp/sing-box-download... check -c /usr/local/etc/sing-box/config.json
```

只有配置检查通过后才会替换现有核心。

因此，**新核心无法通过现有配置检查时，旧核心不会被替换。**

核心更新不会重新生成：

- UUID
- REALITY private key
- REALITY public key
- Short ID
- `config.json`

如果更新前 sing-box 已经是停止状态，更新后也保持停止状态。

### 5.3 更新配置

选择：

```text
3) 更新配置
```

该操作会重新生成：

- UUID
- REALITY private key
- REALITY public key
- Short ID

因此旧的客户端节点链接会失效。

**仅仅想升级 sing-box 版本时，不要使用“更新配置”，应使用“更新 sing-box 核心”。**

---

## 6. VLESS + REALITY + Vision 配置

默认参数：

| 项目 | 默认值 |
|---|---|
| 协议 | VLESS |
| 传输 | TCP |
| 安全层 | REALITY |
| Flow | `xtls-rprx-vision` |
| Fingerprint | `chrome` |
| 监听地址 | `0.0.0.0` |
| 默认监听端口 | `443` |
| 默认 SNI | `www.cloudflare.com` |
| REALITY handshake 端口 | `443` |
| 出站 | `direct` |

配置文件：

```text
/usr/local/etc/sing-box/config.json
```

配置文件权限：

```text
600
```

### 6.1 节点信息

脚本会生成：

```text
/root/singbox-vless-reality-info.txt
```

其中包含服务器地址、端口、UUID、REALITY 公钥、Short ID 和 VLESS 链接。

该文件包含敏感信息，不要提交到 Git 仓库，也不要公开发布。

---

## 7. OpenRC 服务

服务文件：

```text
/etc/init.d/sing-box
```

实际运行命令等价于：

```sh
/usr/local/bin/sing-box run -c /usr/local/etc/sing-box/config.json
```

服务环境针对低内存 VPS 设置：

```text
GOMEMLIMIT=32MiB
GOGC=25
```

更新核心时，如果 sing-box 正在运行，脚本会先停止服务，以降低更新期间的内存峰值。

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
```

```sh
tail -f /var/log/sing-box/error.log
```

---

## 8. 文件位置与敏感信息

| 文件 | 用途 |
|---|---|
| `/usr/local/bin/sing-box` | sing-box 二进制 |
| `/usr/local/etc/sing-box/config.json` | 服务端配置 |
| `/etc/init.d/sing-box` | OpenRC 服务定义 |
| `/root/singbox-vless-reality-info.txt` | 节点信息 / VLESS 链接 |
| `/var/log/sing-box/sing-box.log` | 主日志 |
| `/var/log/sing-box/error.log` | 错误日志 |

`config.json`、节点信息文件以及 REALITY private key 都属于敏感数据。

---

## 9. GitHub Actions：核心同步

工作流：

```text
.github/workflows/sync-sing-box.yml
```

工作流名称：

```text
Sync sing-box Release
```

### 9.1 自动同步

工作流每 6 小时检查一次官方 sing-box 最新稳定 Release：

```yaml
cron: "17 */6 * * *"
```

官方仓库：

```text
SagerNet/sing-box
```

### 9.2 手动同步

支持 `workflow_dispatch`，输入：

```text
version
```

可以使用：

```text
latest
1.13.21
v1.13.21
```

以及：

```text
force=false
force=true
```

`force=false`：目标 Release 已存在时跳过。

`force=true`：允许重新上传资产并更新已有 Release。

### 9.3 官方版本到本仓库 Release 的映射

例如官方 Release：

```text
v1.13.21
```

同步到本仓库后：

```text
Tag:
1.13.21

Release title:
1.13.21-musl
```

即：

```text
官方 SagerNet/sing-box
v1.13.21
        │
        ▼
本仓库
1.13.21
1.13.21-musl
```

**Tag 与 Release title 是两个独立概念：**

- Tag 用纯版本号，方便下载 URL 简洁稳定。
- Title 加 `-musl`，明确表示这是本仓库发布的 musl 二进制。

### 9.4 发布资产

工作流只处理 amd64 和 arm64：

官方输入：

```text
sing-box-<version>-linux-amd64-musl.tar.gz
sing-box-<version>-linux-arm64-musl.tar.gz
```

本仓库最终发布：

```text
sing-box-amd64
sing-box-arm64
SHA256SUMS
```

工作流不会发布 i386、ARMv7、MIPS 等其他架构。

### 9.5 同步验证流程

工作流依次执行：

1. 解析官方 Release 版本。
2. 检查官方 amd64/arm64 musl 包是否存在。
3. 下载官方压缩包。
4. 使用 `gzip -t` 检查完整性。
5. 使用 `tar -tzf` 检查 tar 内容。
6. 解压并定位 `sing-box` 二进制。
7. 重命名为 `sing-box-amd64` / `sing-box-arm64`。
8. 使用 `file` 检查二进制。
9. 执行 amd64 二进制的 `version` 命令。
10. 将实际版本与目标版本比较。
11. 生成 `SHA256SUMS`。
12. 创建或更新本仓库 Release。

Release notes 保持当前工作流生成的内容，不因 Tag/title 命名调整而改变。

---

## 10. 端到端版本更新链路

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
生成 sing-box-amd64 / sing-box-arm64
              │
              ▼
version 校验 + SHA256SUMS
              │
              ▼
创建 <版本号> Release
Title = <版本号>-musl
              │
              ▼
Alpine 安装脚本
              │
              ├── 默认版本 → releases/download/<版本号>/...
              ├── 指定版本 → releases/download/<版本号>/...
              └── Latest   → releases/latest/download/...
              │
              ▼
sing-box version + config check
              │
              ▼
安装/更新 /usr/local/bin/sing-box
              │
              ▼
OpenRC 启动并进行运行状态检查
```

这种设计将“官方压缩包同步”和“64 MB VPS 实际运行”分离。VPS 不需要自行下载、解压官方 tar.gz，也不需要安装构建工具。

---

## 11. 故障排查

### 11.1 核心下载失败

检查下载工具：

```sh
command -v wget
command -v curl
```

确认服务器能够访问：

```text
https://github.com/opyzzzz/64M-sing-box-vless-vision/releases/
```

如果是指定版本，确认 Release Tag 使用的是纯版本号，例如：

```text
1.13.21
```

而不是：

```text
v1.13.21
v1.13.21-multi
1.13.21-multi
```

### 11.2 版本校验失败

查看当前核心：

```sh
/usr/local/bin/sing-box version
```

脚本下载新核心后也会自行执行 `version`，如果实际版本与指定版本不一致，会终止更新。

### 11.3 新核心无法通过配置检查

手动执行：

```sh
/usr/local/bin/sing-box check -c /usr/local/etc/sing-box/config.json
```

检查失败时，不要直接重新生成配置。先确认当前 sing-box 版本与配置格式是否兼容。

### 11.4 服务无法启动

执行：

```sh
rc-service sing-box status
```

```sh
cat /var/log/sing-box/error.log
```

```sh
/usr/local/bin/sing-box check -c /usr/local/etc/sing-box/config.json
```

检查端口：

```sh
ss -lntp
```

### 11.5 更新后客户端节点失效

如果执行的是“更新配置”，UUID、REALITY 密钥和 Short ID 会重新生成，这是正常行为。

重新查看：

```sh
cat /root/singbox-vless-reality-info.txt
```

然后重新导入新的 VLESS 节点。

如果只是执行“更新 sing-box 核心”，正常情况下不会改变上述节点身份参数。

---

## 12. 64 MB VPS 运维注意事项

该项目针对约 64 MB RAM 的 Alpine 环境设计。

服务端设置：

```text
GOMEMLIMIT=32MiB
GOGC=25
```

核心更新时会停止 sing-box，以降低下载和替换核心过程中的内存压力。

需要注意：`GOMEMLIMIT` 和 `GOGC` 只影响 sing-box 进程本身，不能限制 `wget`、`curl`、shell 或其他系统进程的内存使用。因此 64 MB 环境仍然可能受到系统整体内存压力影响。

不要将 `VmSize` / `VmPeak` 直接当作实际 RAM 使用量；判断内存压力时应结合 `memory.current`、进程 RSS 以及系统/cgroup OOM 状态综合判断。

---

## 13. 维护建议

1. **只升级核心时使用“更新 sing-box 核心”**，不要通过“更新配置”实现升级。
2. **不要把 `config.json`、节点信息文件或 REALITY private key 提交到仓库。**
3. **64 MB VPS 更新核心前尽量保持系统空闲**，避免同时运行不必要的高内存进程。
4. **修改 SNI / REALITY handshake 前先确认目标站点适合作为 handshake 目标，并实际验证客户端连通性。**
5. **关注官方 sing-box Release 的配置兼容性变化**；自动同步只负责二进制发布，不会自动修改服务端配置。
6. **需要重新同步已经存在的版本时**，手动运行 workflow 并设置 `force=true`。
7. **当前架构范围固定为 amd64 + arm64**，不为其他架构增加额外发布和脚本逻辑。

---

## 14. 当前实现摘要

当前仓库的主要设计：

- Alpine Linux + OpenRC。
- VLESS + TCP + REALITY + `xtls-rprx-vision`。
- amd64 / arm64 两种架构。
- 默认 sing-box `1.13.21`。
- GitHub Actions 从官方 Release 同步 Linux musl 核心。
- 本仓库 Release Tag 使用纯版本号，例如 `1.13.21`。
- Release title 使用 `<版本号>-musl`，例如 `1.13.21-musl`。
- Release 资产为 `sing-box-amd64`、`sing-box-arm64` 和 `SHA256SUMS`。
- Latest 只指向本仓库最新 Release。
- 指定版本按纯版本号访问对应 Release。
- 安装/更新后进行二进制版本校验。
- 已有配置时，更新核心前使用新核心检查现有配置。
- 核心更新不会重新生成 UUID、REALITY 密钥和 Short ID。
- 服务使用 `GOMEMLIMIT=32MiB` 和 `GOGC=25`。

该文档以仓库当前 `main` 分支代码为准；如果脚本或 workflow 后续发生行为变化，应同步更新本文。