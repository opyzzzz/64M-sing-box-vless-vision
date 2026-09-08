#!/bin/ash

# setup-singbox-reality.sh
# Alpine low-memory sing-box VLESS + REALITY installer/config updater.

set -eu

DEFAULT_SING_BOX_VERSION="1.13.21"
SING_BOX_REPO="opyzzzz/64M-sing-box-vless-vision"

if [ "${1:-}" != "" ]; then
  SING_BOX_VERSION_INPUT="$1"
elif [ "${SING_BOX_VERSION:-}" != "" ]; then
  SING_BOX_VERSION_INPUT="$SING_BOX_VERSION"
else
  SING_BOX_VERSION_INPUT="$DEFAULT_SING_BOX_VERSION"
fi

SING_BOX_VERSION_INPUT="${SING_BOX_VERSION_INPUT#v}"
SING_BOX_VERSION=""
SING_BOX_RELEASE_TAG=""
BIN_BASE_URL=""
BIN_DST="/usr/local/bin/sing-box"
BIN_TMP="/usr/local/tmp/sing-box-download.$$"
CONF_DIR="/usr/local/etc/sing-box"
CONF_FILE="${CONF_DIR}/config.json"
LOG_DIR="/var/log/sing-box"
INFO_FILE="/root/singbox-vless-reality-info.txt"
DEFAULT_PORT="${DEFAULT_PORT:-443}"
DEFAULT_DOMAIN="${DEFAULT_DOMAIN:-www.cloudflare.com}"
ARCH=""
SING_BOX_ARCH=""
SING_BOX_FILE=""
BIN_URL=""
DOWNLOAD_TOOL=""
UPDATE_SERVICE_WAS_RUNNING="no"

log() { echo "[+] $*"; }
warn() { echo "[!] $*" >&2; }
die() { echo "[x] $*" >&2; exit 1; }

pause() {
  echo
  printf "按回车键继续..."
  read -r _ </dev/tty || true
}

cleanup() {
  rm -f "$BIN_TMP" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

detect_download_tool() {
  if command -v wget >/dev/null 2>&1; then
    DOWNLOAD_TOOL="wget"
    return
  fi
  if command -v curl >/dev/null 2>&1; then
    DOWNLOAD_TOOL="curl"
    return
  fi
  die "系统没有 wget 或 curl，无法下载 sing-box。"
}

resolve_sing_box_version() {
  if [ "$SING_BOX_VERSION_INPUT" = "latest" ]; then
    log "使用本仓库最新 Release..."
    SING_BOX_VERSION="latest"
    SING_BOX_RELEASE_TAG="latest"
    BIN_BASE_URL="https://github.com/${SING_BOX_REPO}/releases/latest/download"
  else
    SING_BOX_VERSION="$SING_BOX_VERSION_INPUT"
    case "$SING_BOX_VERSION" in
      ""|*[!0-9.]*) die "sing-box 版本格式不正确：${SING_BOX_VERSION}" ;;
    esac
    SING_BOX_RELEASE_TAG="$SING_BOX_VERSION"
    BIN_BASE_URL="https://github.com/${SING_BOX_REPO}/releases/download/${SING_BOX_RELEASE_TAG}"
  fi
  export SING_BOX_VERSION SING_BOX_RELEASE_TAG BIN_BASE_URL
}

require_root() {
  [ "$(id -u)" = "0" ] || die "请使用 root 用户运行。"
}

protect_ssh() {
  echo -1000 > /proc/$$/oom_score_adj 2>/dev/null || true
  for p in $(pgrep -x sshd 2>/dev/null || true); do
    echo -1000 > /proc/$p/oom_score_adj 2>/dev/null || true
  done
}

ensure_openrc_runtime() {
  mkdir -p /run/openrc
  touch /run/openrc/softlevel 2>/dev/null || true
}

validate_port() {
  port="$1"
  case "$port" in
    ""|*[!0-9]*) die "端口必须是数字。" ;;
  esac
  if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
    die "端口范围必须是 1-65535。"
  fi
}

validate_domain() {
  domain="$1"
  case "$domain" in
    ""|*"/"*|*":"*|*" "*) die "域名格式不正确，请输入类似 www.cloudflare.com 的域名。" ;;
  esac
}

ask_port_domain() {
  echo
  printf "请输入监听端口 [%s]: " "$DEFAULT_PORT"
  read -r PORT_INPUT </dev/tty || true
  PORT="${PORT_INPUT:-$DEFAULT_PORT}"
  validate_port "$PORT"

  printf "请输入 REALITY 域名 / SNI [%s]: " "$DEFAULT_DOMAIN"
  read -r DOMAIN_INPUT </dev/tty || true
  REALITY_DOMAIN="${DOMAIN_INPUT:-$DEFAULT_DOMAIN}"
  validate_domain "$REALITY_DOMAIN"
  HANDSHAKE_SERVER="$REALITY_DOMAIN"
  HANDSHAKE_PORT="443"
}

select_version() {
  menu_title="$1"
  while true; do
    echo
    echo "=============================================="
    echo " ${menu_title} - 版本选择"
    echo "=============================================="
    echo " 1) 默认版本：${DEFAULT_SING_BOX_VERSION}"
    echo " 2) Latest（本仓库最新 Release）"
    echo " 3) 指定版本号"
    echo " 0) 返回上一级"
    echo "=============================================="
    printf "请选择: "
    read -r VERSION_CHOICE </dev/tty || true

    case "$VERSION_CHOICE" in
      1)
        SING_BOX_VERSION_INPUT="$DEFAULT_SING_BOX_VERSION"
        return 0
        ;;
      2)
        SING_BOX_VERSION_INPUT="latest"
        return 0
        ;;
      3)
        printf "请输入 sing-box 版本号，例如 1.13.22: "
        read -r VERSION_INPUT </dev/tty || true
        VERSION_INPUT="${VERSION_INPUT#v}"
        case "$VERSION_INPUT" in
          ""|*[!0-9.]*) echo "版本号格式不正确。"; pause ;;
          *) SING_BOX_VERSION_INPUT="$VERSION_INPUT"; return 0 ;;
        esac
        ;;
      0)
        return 1
        ;;
      *)
        echo "无效选择。"
        pause
        ;;
    esac
  done
}

select_install_version() { select_version "安装 sing-box"; }
select_update_version() { select_version "更新 sing-box 核心"; }

detect_arch() {
  ARCH="$(uname -m)"
  case "$ARCH" in
    x86_64|amd64)
      SING_BOX_ARCH="amd64"
      SING_BOX_FILE="sing-box-amd64"
      ;;
    aarch64|arm64)
      SING_BOX_ARCH="arm64"
      SING_BOX_FILE="sing-box-arm64"
      ;;
    *)
      die "不支持的 CPU 架构：${ARCH}"
      ;;
  esac
  BIN_URL="${BIN_BASE_URL}/${SING_BOX_FILE}"
  log "CPU 架构：${ARCH}"
  log "目标架构：${SING_BOX_ARCH}"
  log "核心文件：${SING_BOX_FILE}"
}

install_binary() {
  detect_arch
  detect_download_tool
  mkdir -p /usr/local/bin /usr/local/tmp "$CONF_DIR" "$LOG_DIR"
  rm -f "$BIN_TMP"

  echo
  log "下载 sing-box..."
  case "$DOWNLOAD_TOOL" in
    wget)
      wget -q --show-progress --tries=3 --timeout=20 -O "$BIN_TMP" "$BIN_URL" || die "sing-box 下载失败。"
      ;;
    curl)
      curl -fL --retry 3 --connect-timeout 20 --max-time 300 -o "$BIN_TMP" "$BIN_URL" || die "sing-box 下载失败。"
      ;;
  esac

  [ -s "$BIN_TMP" ] || die "下载失败：临时核心文件为空。"
  chmod 755 "$BIN_TMP"

  log "验证下载的 sing-box..."
  VERSION_OUTPUT="$("$BIN_TMP" version 2>&1)" || die "下载的 sing-box 核心无法正常执行。"
  printf '%s\n' "$VERSION_OUTPUT"

  ACTUAL_VERSION="$(printf '%s\n' "$VERSION_OUTPUT" | awk '/^sing-box version / { print $3; exit }')"
  [ -n "$ACTUAL_VERSION" ] || die "无法读取下载核心的实际版本号。"

  if [ "$SING_BOX_VERSION_INPUT" = "latest" ]; then
    SING_BOX_VERSION="$ACTUAL_VERSION"
    SING_BOX_RELEASE_TAG="$ACTUAL_VERSION"
    export SING_BOX_VERSION SING_BOX_RELEASE_TAG
    log "本仓库 Latest 实际版本：${ACTUAL_VERSION}"
  else
    case "$ACTUAL_VERSION" in
      "$SING_BOX_VERSION"|v"$SING_BOX_VERSION") ;;
      *) die "版本校验失败：请求 ${SING_BOX_VERSION}，实际 ${ACTUAL_VERSION}。" ;;
    esac
  fi

  if [ -f "$CONF_FILE" ]; then
    log "使用下载的新核心检查现有配置..."
    "$BIN_TMP" check -c "$CONF_FILE" || die "新核心无法通过现有配置检查，旧核心保持不变。"
  fi

  mv -f "$BIN_TMP" "$BIN_DST"
  chmod 755 "$BIN_DST"
  log "sing-box 核心已安装：${BIN_DST}"
}

check_binary_exists() {
  [ -x "$BIN_DST" ] || die "没有找到 ${BIN_DST}。请先选择安装。"
}

stop_conflicting_services() {
  log "停止可能占用端口的旧服务..."
  rc-service xray stop 2>/dev/null || true
  rc-update del xray default 2>/dev/null || true
  pkill -f 'xray run' 2>/dev/null || true
  rc-service sing-box stop 2>/dev/null || true
  pkill -f 'sing-box run' 2>/dev/null || true
}

generate_reality_values() {
  UUID="$(cat /proc/sys/kernel/random/uuid)"
  KEYPAIR="$("$BIN_DST" generate reality-keypair)"
  PRIVATE_KEY="$(echo "$KEYPAIR" | awk -F': *' 'tolower($1) ~ /private/ {print $2; exit}')"
  PUBLIC_KEY="$(echo "$KEYPAIR" | awk -F': *' 'tolower($1) ~ /public/ {print $2; exit}')"
  SHORT_ID="$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')"
  [ -n "$PRIVATE_KEY" ] || die "REALITY private_key 生成失败。"
  [ -n "$PUBLIC_KEY" ] || die "REALITY public_key 生成失败。"
  [ -n "$SHORT_ID" ] || die "REALITY short_id 生成失败。"
}

write_config() {
  mkdir -p "$CONF_DIR" "$LOG_DIR"
  cat > "$CONF_FILE" <<EOF
{
  "log": {
    "level": "warn",
    "output": "${LOG_DIR}/sing-box.log",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-reality-in",
      "listen": "0.0.0.0",
      "listen_port": ${PORT},
      "users": [
        {
          "uuid": "${UUID}",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${REALITY_DOMAIN}",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "${HANDSHAKE_SERVER}",
            "server_port": ${HANDSHAKE_PORT}
          },
          "private_key": "${PRIVATE_KEY}",
          "short_id": [
            "${SHORT_ID}"
          ]
        }
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ]
}
EOF
  chmod 600 "$CONF_FILE"
}

write_openrc_service() {
  cat > /etc/init.d/sing-box <<EOF
#!/sbin/openrc-run

name="sing-box"
description="sing-box VLESS REALITY"

command="${BIN_DST}"
command_args="run -c ${CONF_FILE}"
command_background="yes"
pidfile="/run/sing-box.pid"
output_log="/dev/null"
error_log="${LOG_DIR}/error.log"

export GOMEMLIMIT="32MiB"
export GOGC="25"

depend() {
  need net
}

start_pre() {
  mkdir -p "${LOG_DIR}"
  touch "${LOG_DIR}/sing-box.log"
  touch "${LOG_DIR}/error.log"
}
EOF
  chmod +x /etc/init.d/sing-box
  ensure_openrc_runtime
  rc-update add sing-box default >/dev/null 2>&1 || true
}

service_is_healthy() {
  rc-service sing-box status >/dev/null 2>&1 || return 1
  sleep 1
  rc-service sing-box status >/dev/null 2>&1 || return 1
  if command -v pidof >/dev/null 2>&1; then
    pids="$(pidof sing-box 2>/dev/null || true)"
    [ -n "$pids" ] || return 1
    for pid in $pids; do
      kill -0 "$pid" 2>/dev/null || return 1
    done
  else
    pgrep -x sing-box >/dev/null 2>&1 || return 1
  fi
}

test_and_restart() {
  log "检查 sing-box 配置..."
  "$BIN_DST" check -c "$CONF_FILE"
  log "启动 / 重启 sing-box..."
  rc-service sing-box restart
  service_is_healthy || die "sing-box 启动后未通过运行状态检查，请检查 ${LOG_DIR}/error.log"
  rc-service sing-box status || true
}

update_core_mode() {
  echo
  echo "=== 更新 sing-box 核心 ==="

  if ! select_update_version; then
    return 0
  fi

  echo
  echo "已选择版本：${SING_BOX_VERSION_INPUT}"
  echo

  protect_ssh
  check_binary_exists
  resolve_sing_box_version

  if rc-service sing-box status >/dev/null 2>&1; then
    UPDATE_SERVICE_WAS_RUNNING="yes"
    log "停止 sing-box 以降低内存占用..."
    rc-service sing-box stop || die "停止 sing-box 失败，取消更新。"
  else
    log "sing-box 当前未运行，直接更新。"
  fi

  install_binary

  if [ -f "$CONF_FILE" ]; then
    log "现有配置检查通过，保留 UUID / REALITY 密钥 / Short ID。"
    if [ "$UPDATE_SERVICE_WAS_RUNNING" = "yes" ]; then
      log "启动新核心并进行运行验证..."
      rc-service sing-box start || die "新核心启动失败。"
      service_is_healthy || die "新核心启动后未通过运行状态检查。"
      rc-service sing-box status || true
    else
      log "更新前 sing-box 本来就是停止状态，保持停止。"
    fi
  else
    warn "未发现现有配置：${CONF_FILE}"
    warn "核心已经更新，但不会自动生成新配置。"
  fi

  echo
  echo "核心更新完成，配置未重新生成。"
}

detect_server_ip() {
  SERVER_ADDR="${SERVER_ADDR:-}"
  if [ -z "$SERVER_ADDR" ]; then
    SERVER_ADDR="$(wget -qO- https://api.ipify.org 2>/dev/null || true)"
  fi
  if [ -z "$SERVER_ADDR" ]; then
    SERVER_ADDR="$(wget -qO- https://ipinfo.io/ip 2>/dev/null || true)"
  fi
  if [ -z "$SERVER_ADDR" ]; then
    SERVER_ADDR="你的服务器IP"
    warn "未能自动获取公网 IP，请手动替换服务器地址。"
  fi
}

write_info() {
  detect_server_ip
  LINK="vless://${UUID}@${SERVER_ADDR}:${PORT}?encryption=none&security=reality&sni=${REALITY_DOMAIN}&fp=chrome&type=tcp&flow=xtls-rprx-vision&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}#singbox-reality"
  cat > "$INFO_FILE" <<EOF
sing-box VLESS + REALITY

sing-box Version:
${SING_BOX_VERSION}

Release:
${SING_BOX_RELEASE_TAG}

Address: ${SERVER_ADDR}
Port: ${PORT}
UUID: ${UUID}
Flow: xtls-rprx-vision
Network: tcp
Security: reality
SNI / serverName: ${REALITY_DOMAIN}
Handshake: ${HANDSHAKE_SERVER}:${HANDSHAKE_PORT}
PublicKey / pbk: ${PUBLIC_KEY}
ShortId / sid: ${SHORT_ID}
Fingerprint: chrome

Client link:
${LINK}

Config:
${CONF_FILE}

Service:
rc-service sing-box status
rc-service sing-box restart
rc-service sing-box stop

Logs:
${LOG_DIR}/sing-box.log
${LOG_DIR}/error.log
EOF
  chmod 600 "$INFO_FILE"
  echo
  echo "==================== 完成 ===================="
  cat "$INFO_FILE"
  echo "=============================================="
  echo
  echo "提示：请确认云服务器安全组 / 防火墙已放行 TCP ${PORT}。"
}

install_mode() {
  echo
  echo "=== 安装 sing-box + 生成配置 ==="
  if ! select_install_version; then
    return 0
  fi
  echo
  echo "已选择版本：${SING_BOX_VERSION_INPUT}"
  ask_port_domain
  protect_ssh
  stop_conflicting_services
  resolve_sing_box_version
  install_binary
  generate_reality_values
  write_config
  write_openrc_service
  test_and_restart
  write_info
}

update_config_mode() {
  echo
  echo "=== 更新配置 ==="
  ask_port_domain
  protect_ssh
  check_binary_exists
  generate_reality_values
  write_config
  write_openrc_service
  test_and_restart
  write_info
}

show_status() {
  echo
  echo "=== 当前状态 ==="
  if [ -x "$BIN_DST" ]; then
    "$BIN_DST" version || true
  else
    warn "未安装 sing-box：${BIN_DST} 不存在。"
  fi
  echo
  rc-service sing-box status 2>/dev/null || true
  echo
  ss -lntp 2>/dev/null | grep sing-box || true
  echo
  if [ -f "$INFO_FILE" ]; then
    cat "$INFO_FILE"
  else
    warn "未找到节点信息文件：${INFO_FILE}"
  fi
  pause
}

main_menu() {
  while true; do
    clear 2>/dev/null || true
    echo "=============================================="
    echo " sing-box VLESS + REALITY for Alpine"
    echo "=============================================="
    echo " 默认版本：${DEFAULT_SING_BOX_VERSION}"
    echo " Latest：本仓库最新 Release"
    echo "=============================================="
    echo " 1) 安装 sing-box"
    echo " 2) 更新 sing-box 核心"
    echo " 3) 更新配置"
    echo " 4) 查看状态"
    echo " 0) 退出"
    echo "=============================================="
    printf "请选择: "
    read -r choice </dev/tty || true
    case "$choice" in
      1) install_mode; break ;;
      2) update_core_mode; break ;;
      3) update_config_mode; break ;;
      4) show_status ;;
      0) exit 0 ;;
      *) echo "无效选择。"; pause ;;
    esac
  done
}

main() {
  require_root
  main_menu
}

main "$@"
