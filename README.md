# 64M-sing-box-vless-vision

轻量级 sing-box VLESS + REALITY 部署项目，面向 Alpine Linux 低内存 VPS 环境。

项目目标：在约 64MB RAM 的服务器上快速部署、稳定运行 sing-box，并通过 GitHub Actions 自动维护可用核心版本。

## 特性

- 🚀 一键安装 sing-box
- 🔐 VLESS + REALITY + Vision
- 🐧 Alpine Linux + OpenRC 支持
- 🧠 64MB 内存环境优化
- 🔄 核心更新与配置更新分离
- 🏗️ 自动支持 amd64 / arm64
- ✅ 更新前配置检查
- 📦 自动同步 sing-box musl 核心 Release

## 快速安装

```bash
wget -qO- https://raw.githubusercontent.com/opyzzzz/64M-sing-box-vless-vision/main/setup-singbox-reality.sh | sh
```

或：

```bash
curl -fsSL https://raw.githubusercontent.com/opyzzzz/64M-sing-box-vless-vision/main/setup-singbox-reality.sh | sh
```

## 管理功能

脚本支持：

- 安装 sing-box
- 更新 sing-box 核心
- 生成/更新 REALITY 配置
- 查看运行状态

核心升级不会重新生成节点信息，会保留已有 UUID、REALITY 密钥和 Short ID。

## GitHub Actions

工作流：

```
.github/workflows/sync-sing-box.yml
```

功能：

- 定时检查官方 sing-box Latest Release
- 下载官方 Linux musl 核心
- 校验版本与完整性
- 发布 amd64 / arm64 二进制
- 生成 SHA256 校验文件

## 文件说明

```
.
├── setup-singbox-reality.sh
├── .github/workflows/
│   └── sync-sing-box.yml
└── docs/
    └── OPERATIONS.md
```

## 文档

详细运维说明：

```
docs/OPERATIONS.md
```

包含：

- 安装流程
- 更新机制
- 工作流说明
- 文件结构
- 故障排查

## 项目地址

https://github.com/opyzzzz/64M-sing-box-vless-vision
