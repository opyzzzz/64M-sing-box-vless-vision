#!/bin/ash

# setup-singbox-reality.sh
# Alpine low-memory sing-box VLESS + REALITY installer/config updater.

set -eu

DEFAULT_SING_BOX_VERSION="1.13.21"
SING_BOX_REPO="opyzzzz/64M-sing-box-vless-vision"
RAW_SCRIPT_URL="https://raw.githubusercontent.com/${SING_BOX_REPO}/main/setup-singbox-reality.sh"
SB_SCRIPT="/usr/local/bin/sb"
BIN_DST="/usr/local/bin/sing-box"
BIN_TMP="/usr/local/tmp/sing-box-download.$$"
CONF_DIR="/usr/local/etc/sing-box"
CONF_FILE="${CONF_DIR}/config.json"
LOG_DIR="/var/log/sing-box"
INFO_FILE="/root/singbox-vless-reality-info.txt"
DEFAULT_PORT="${DEFAULT_PORT:-443}"
DEFAULT_DOMAIN="${DEFAULT_DOMAIN:-www.cloudflare.com}"

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

cleanup() { rm -f "$BIN_TMP" 2>/dev/null || true; }
trap cleanup EXIT INT TERM

detect_download_tool() {
  if command -v wget >/dev/null 2>&1; then DOWNLOAD_TOOL="wget"; return; fi
  if command -v curl >/dev/null 2>&1; then DOWNLOAD_TOOL="curl"; return; fi
  die "系统没有 wget 或 curl，无法下载文件。"
}

resolve_sing_box_version() {
  if [ "$SING_BOX_VERSION_INPUT" = "latest" ]; then
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

require_root() { [ "$(id -u)" = "0" ] || die "请使用 root 用户运行。"; }

protect_ssh() {
  echo -1000 > /proc/$$/oom_score_adj 2>/dev/null || true
  for p in $(pgrep -x sshd 2>/dev/null || true); do echo -1000 > /proc/$p/oom_score_adj 2>/dev/null || true; done
}

ensure_openrc_runtime() { mkdir -p /run/openrc; touch /run/openrc/softlevel 2>/dev/null || true; }

validate_port() {
  case "$1" in ""|*[!0-9]*) die "端口必须是数字。" ;; esac
  [ "$1" -ge 1 ] && [ "$1" -le 65535 ] || die "端口范围必须是 1-65535。"
}

validate_domain() {
  case "$1" in ""|*"/"*|*":"*|*" "*) die "域名格式不正确，请输入类似 www.cloudflare.com 的域名。" ;; esac
}

ask_port_domain() {
  echo
  printf "端口 [%s]: " "$DEFAULT_PORT"
  read -r PORT_INPUT </dev/tty || true
  PORT="${PORT_INPUT:-$DEFAULT_PORT}"
  validate_port "$PORT"
  printf "REALITY 域名 [%s]: " "$DEFAULT_DOMAIN"
  read -r DOMAIN_INPUT </dev/tty || true
  REALITY_DOMAIN="${DOMAIN_INPUT:-$DEFAULT_DOMAIN}"
  validate_domain "$REALITY_DOMAIN"
  HANDSHAKE_SERVER="$REALITY_DOMAIN"
  HANDSHAKE_PORT=443
}

select_version() {
  menu_title="$1"
  while true; do
    echo
    echo "=== ${menu_title} ==="
    echo "1) ${DEFAULT_SING_BOX_VERSION}"
    echo "2) Latest"
    echo "3) 指定版本"
    echo "0) 返回"
    printf "选择: "
    read -r VERSION_CHOICE </dev/tty || true
    case "$VERSION_CHOICE" in
      1) SING_BOX_VERSION_INPUT="$DEFAULT_SING_BOX_VERSION"; return 0 ;;
      2) SING_BOX_VERSION_INPUT="latest"; return 0 ;;
      3)
        printf "版本号: "
        read -r VERSION_INPUT </dev/tty || true
        VERSION_INPUT="${VERSION_INPUT#v}"
        case "$VERSION_INPUT" in
          ""|*[!0-9.]*) echo "版本号格式不正确。"; pause ;;
          *) SING_BOX_VERSION_INPUT="$VERSION_INPUT"; return 0 ;;
        esac
        ;;
      0) return 1 ;;
      *) echo "无效选择。"; pause ;;
    esac
  done
}

select_install_version() { select_version "安装 sing-box"; }
select_update_version() { select_version "更新核心"; }

detect_arch() {
  ARCH="$(uname -m)"
  case "$ARCH" in
    x86_64|amd64) SING_BOX_ARCH="amd64"; SING_BOX_FILE="sing-box-amd64" ;;
    aarch64|arm64) SING_BOX_ARCH="arm64"; SING_BOX_FILE="sing-box-arm64" ;;
    *) die "不支持的 CPU 架构：${ARCH}" ;;
  esac
  BIN_URL="${BIN_BASE_URL}/${SING_BOX_FILE}"
}

install_binary() {
  detect_arch
  detect_download_tool
  mkdir -p /usr/local/bin /usr/local/tmp "$CONF_DIR" "$LOG_DIR"
  rm -f "$BIN_TMP"
  echo
  log "下载 sing-box..."
  case "$DOWNLOAD_TOOL" in
    wget) wget -q --show-progress --tries=3 --timeout=20 -O "$BIN_TMP" "$BIN_URL" || die "sing-box 下载失败。" ;;
    curl) curl -fL --retry 3 --connect-timeout 20 --max-time 300 -o "$BIN_TMP" "$BIN_URL" || die "sing-box 下载失败。" ;;
  esac
  [ -s "$BIN_TMP" ] || die "下载失败：临时核心文件为空。"
  chmod 755 "$BIN_TMP"
  log "验证下载的 sing-box..."
  VERSION_OUTPUT="$("$BIN_TMP" version 2>&1)" || die "下载的 sing-box 核心无法正常执行。"
  printf '%s\n' "$VERSION_OUTPUT"
  ACTUAL_VERSION="$(printf '%s\n' "$VERSION_OUTPUT" | awk '/^sing-box version / {print $3; exit}')"
  [ -n "$ACTUAL_VERSION" ] || die "无法读取下载核心的实际版本号。"
  if [ "$SING_BOX_VERSION_INPUT" = "latest" ]; then
    SING_BOX_VERSION="$ACTUAL_VERSION"
    SING_BOX_RELEASE_TAG="$ACTUAL_VERSION"
    export SING_BOX_VERSION SING_BOX_RELEASE_TAG
    log "Latest 实际版本：${ACTUAL_VERSION}"
  else
    case "$ACTUAL_VERSION" in
      "$SING_BOX_VERSION"|v"$SING_BOX_VERSION") ;;
      *) die "版本校验失败：请求 ${SING_BOX_VERSION}，实际 ${ACTUAL_VERSION}。" ;;
    esac
  fi
  if [ -f "$CONF_FILE" ]; then
    log "检查现有配置..."
    "$BIN_TMP" check -c "$CONF_FILE" || die "新核心无法通过现有配置检查，旧核心保持不变。"
  fi
  mv -f "$BIN_TMP" "$BIN_DST"
  chmod 755 "$BIN_DST"
  log "核心已安装：${BIN_DST}"
}

check_binary_exists() { [ -x "$BIN_DST" ] || die "没有找到 ${BIN_DST}，请先安装。"; }

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
      "users": [{"uuid": "${UUID}", "flow": "xtls-rprx-vision"}],
      "tls": {
        "enabled": true,
        "server_name": "${REALITY_DOMAIN}",
        "reality": {
          "enabled": true,
          "handshake": {"server": "${HANDSHAKE_SERVER}", "server_port": ${HANDSHAKE_PORT}},
          "private_key": "${PRIVATE_KEY}",
          "short_id": ["${SHORT_ID}"]
        }
      }
    }
  ],
  "outbounds": [{"type": "direct", "tag": "direct"}]
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
depend() { need net; }
start_pre() {
  mkdir -p "${LOG_DIR}"
  touch "${LOG_DIR}/sing-box.log" "${LOG_DIR}/error.log"
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
    for pid in $pids; do kill -0 "$pid" 2>/dev/null || return 1; done
  else
    pgrep -x sing-box >/dev/null 2>&1 || return 1
  fi
}

get_sing_box_version() {
  [ -x "$BIN_DST" ] || { echo "未安装"; return; }
  version_output="$("$BIN_DST" version 2>/dev/null || true)"
  version="$(printf '%s\n' "$version_output" | awk '/^sing-box version / {print $3; exit}')"
  [ -n "$version" ] && echo "$version" || echo "未知"
}

get_service_state() {
  [ -x "$BIN_DST" ] || { echo "未安装"; return; }
  rc-service sing-box status >/dev/null 2>&1 || { echo "停止"; return; }
  sleep 1
  rc-service sing-box status >/dev/null 2>&1 || { echo "停止"; return; }
  if command -v pidof >/dev/null 2>&1; then
    pids="$(pidof sing-box 2>/dev/null || true)"
    [ -n "$pids" ] || { echo "停止"; return; }
    for pid in $pids; do kill -0 "$pid" 2>/dev/null || { echo "停止"; return; }; done
  else
    pgrep -x sing-box >/dev/null 2>&1 || { echo "停止"; return; }
  fi
  echo "运行"
}

status_badge() {
  case "$1" in
    运行) printf '\033[32m● 运行\033[0m' ;;
    停止) printf '\033[31m● 停止\033[0m' ;;
    *) printf '\033[90m● %s\033[0m' "$1" ;;
  esac
}

get_sing_box_pid() {
  if command -v pidof >/dev/null 2>&1; then pidof sing-box 2>/dev/null | awk '{print $1}'; else pgrep -x sing-box 2>/dev/null | awk 'NR==1{print;exit}'; fi
}

get_listen_info() {
  listen_info="$(ss -lntp 2>/dev/null | awk '/sing-box/ {print $4; exit}' || true)"
  [ -n "$listen_info" ] && echo "$listen_info" || echo "无"
}

get_info_value() {
  key="$1"
  [ -f "$INFO_FILE" ] || return 0
  awk -F': ' -v key="$key" '$1 == key {print $2; exit}' "$INFO_FILE"
}

show_status() {
  clear 2>/dev/null || true
  current_version="$(get_sing_box_version)"
  current_state="$(get_service_state)"
  current_badge="$(status_badge "$current_state")"
  current_pid="$(get_sing_box_pid)"
  current_listen="$(get_listen_info)"
  echo "========================================"
  echo "           sing-box 状态"
  echo "========================================"
  echo
  printf "核心版本    %s\n" "$current_version"
  printf "运行状态    %s\n" "$current_badge"
  printf "监听地址    %s\n" "$current_listen"
  printf "进程 PID    %s\n" "${current_pid:-无}"
  echo
  echo "----------------------------------------"
  echo "          VLESS + REALITY"
  echo "----------------------------------------"
  if [ -f "$INFO_FILE" ]; then
    printf "服务器      %s\n" "$(get_info_value 'Address')"
    printf "端口        %s\n" "$(get_info_value 'Port')"
    printf "UUID        %s\n" "$(get_info_value 'UUID')"
    printf "Flow        %s\n" "$(get_info_value 'Flow')"
    printf "Network     %s\n" "$(get_info_value 'Network')"
    printf "Security    %s\n" "$(get_info_value 'Security')"
    printf "SNI         %s\n" "$(get_info_value 'SNI / serverName')"
    printf "Handshake   %s\n" "$(get_info_value 'Handshake')"
    printf "PublicKey   %s\n" "$(get_info_value 'PublicKey / pbk')"
    printf "Short ID    %s\n" "$(get_info_value 'ShortId / sid')"
    printf "Fingerprint %s\n" "$(get_info_value 'Fingerprint')"
    echo
    echo "----------------------------------------"
    echo "客户端链接"
    echo "----------------------------------------"
    awk '/^Client link:$/ {getline; print; exit}' "$INFO_FILE"
  else
    echo "未找到节点信息文件：${INFO_FILE}"
  fi
  echo
  echo "----------------------------------------"
  printf "配置文件    %s\n" "$CONF_FILE"
  printf "日志文件    %s\n" "$LOG_DIR/sing-box.log"
  printf "错误日志    %s\n" "$LOG_DIR/error.log"
  echo "========================================"
  pause
}

install_sb_command() {
  detect_download_tool
  mkdir -p /usr/local/bin
  case "$DOWNLOAD_TOOL" in
    wget) wget -q --tries=3 --timeout=20 -O "$SB_SCRIPT" "$RAW_SCRIPT_URL" || die "注册 sb 快捷命令失败。" ;;
    curl) curl -fsSL --retry 3 --connect-timeout 20 --max-time 60 -o "$SB_SCRIPT" "$RAW_SCRIPT_URL" || die "注册 sb 快捷命令失败。" ;;
  esac
  chmod 755 "$SB_SCRIPT"
  log "快捷命令已注册：输入 sb 即可运行。"
}

test_and_restart() {
  log "检查 sing-box 配置..."
  "$BIN_DST" check -c "$CONF_FILE"
  log "启动 / 重启 sing-box..."
  rc-service sing-box restart
  service_is_healthy || die "sing-box 启动后未通过运行状态检查，请检查 ${LOG_DIR}/error.log"
}

update_core_mode() {
  echo
  echo "=== 更新核心 ==="
  select_update_version || return 0
  echo
  echo "版本：${SING_BOX_VERSION_INPUT}"
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
      rc-service sing-box start || die "新核心启动失败。"
      service_is_healthy || die "新核心启动后未通过运行状态检查。"
    else
      log "更新前 sing-box 已停止，保持停止。"
    fi
  else
    warn "未发现现有配置：${CONF_FILE}"
    warn "核心已经更新，但不会自动生成新配置。"
  fi
  echo
  echo "核心更新完成。"
}

detect_server_ip() {
  SERVER_ADDR="${SERVER_ADDR:-}"
  if [ -z "$SERVER_ADDR" ]; then SERVER_ADDR="$(wget -qO- https://api.ipify.org 2>/dev/null || true)"; fi
  if [ -z "$SERVER_ADDR" ]; then SERVER_ADDR="$(wget -qO- https://ipinfo.io/ip 2>/dev/null || true)"; fi
  if [ -z "$SERVER_ADDR" ]; then SERVER_ADDR="你的服务器IP"; warn "未能自动获取公网 IP，请手动替换服务器地址。"; fi
}

write_info() {
  detect_server_ip
  LINK="vless://${UUID}@${SERVER_ADDR}:${PORT}?encryption=none&security=reality&sni=${REALITY_DOMAIN}&fp=chrome&type=tcp&flow=xtls-rprx-vision&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}#singbox-reality"
  cat > "$INFO_FILE" <<EOF
sing-box VLESS + REALITY

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
  echo "=== 安装 sing-box ==="
  select_install_version || return 0
  echo
  echo "版本：${SING_BOX_VERSION_INPUT}"
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
  install_sb_command
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

main_menu() {
  while true; do
    clear 2>/dev/null || true
    current_version="$(get_sing_box_version)"
    current_state="$(get_service_state)"
    current_badge="$(status_badge "$current_state")"
    echo "========================================"
    echo "           sing-box 状态"
    echo "========================================"
    echo
    printf "核心版本    %s\n" "$current_version"
    printf "运行状态    %s\n" "$current_badge"
    echo
    echo "----------------------------------------"
    echo "1) 安装"
    echo "2) 更新核心"
    echo "3) 更新配置"
    echo "4) 查看状态"
    echo "0) 退出"
    echo "----------------------------------------"
    printf "选择: "
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
