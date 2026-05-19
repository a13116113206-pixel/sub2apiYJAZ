#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="sub2api"
APP_DIR="/opt/${APP_NAME}"
ENV_FILE="${APP_DIR}/.env"
COMPOSE_FILE="${APP_DIR}/docker-compose.yml"
INFO_FILE="/root/${APP_NAME}-info.txt"
LOG_FILE="/root/${APP_NAME}-install.log"

BT_PORT="${BT_PORT:-8888}"
BT_INSTALL_URL="${BT_INSTALL_URL:-https://download.bt.cn/install/install_panel.sh}"
BT_INSTALL_ARGS="${BT_INSTALL_ARGS:-ed8484bec}"
SUB2API_PORT="${SUB2API_PORT:-8080}"
ADMIN_EMAIL="${ADMIN_EMAIL:-admin@example.com}"
DOMAIN="${DOMAIN:-}"
INSTALL_BT="${INSTALL_BT:-1}"
SERVER_REGION="${SERVER_REGION:-}"
ACCESS_MODE="${ACCESS_MODE:-}"
DOCKER_REGISTRY_MIRROR="${DOCKER_REGISTRY_MIRROR:-https://mirror.ccs.tencentyun.com}"
SUB2API_DEPLOY_BASE_CN="${SUB2API_DEPLOY_BASE_CN:-https://cdn.jsdelivr.net/gh/Wei-Shaw/sub2api@main/deploy}"
SUB2API_DEPLOY_BASE_GLOBAL="${SUB2API_DEPLOY_BASE_GLOBAL:-https://raw.githubusercontent.com/Wei-Shaw/sub2api/main/deploy}"
SUB2API_DEPLOY_BASE=""

msg() {
  printf '\n[%s] %s\n' "$(date '+%F %T')" "$*"
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

need_root() {
  if [ "$(id -u)" -ne 0 ]; then
    die "请使用 root 运行：sudo bash $0"
  fi
}

detect_os() {
  if [ -r /etc/os-release ]; then
    . /etc/os-release
    OS_ID="${ID:-}"
    OS_VERSION_ID="${VERSION_ID:-}"
  else
    die "无法识别系统。建议使用 Ubuntu 20.04+/Debian 11+/CentOS 7+/Rocky/AlmaLinux。"
  fi
}

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

ask_choice() {
  local prompt="$1"
  local default_choice="$2"
  local choice=""

  while true; do
    if [ -r /dev/tty ]; then
      read -r -p "${prompt}" choice </dev/tty
    else
      read -r -p "${prompt}" choice
    fi
    choice="${choice:-${default_choice}}"
    case "${choice}" in
      1|2)
        printf '%s' "${choice}"
        return
        ;;
      *)
        echo "请输入 1 或 2。"
        ;;
    esac
  done
}

ask_questions() {
  if [ -z "${SERVER_REGION}" ]; then
    echo
    echo "请选择服务器网络位置："
    echo "1) 国内服务器：使用 CDN/系统源，适合腾讯云、阿里云、华为云中国区"
    echo "2) 国外服务器：使用 GitHub/Docker 官方源，海外机器通常更快"
    SERVER_REGION="$(ask_choice "请输入 1 或 2 [默认 1]: " "1")"
  fi

  case "${SERVER_REGION}" in
    1|cn|CN|china|China)
      SERVER_REGION="cn"
      SUB2API_DEPLOY_BASE="${SUB2API_DEPLOY_BASE_CN}"
      ;;
    2|global|GLOBAL|foreign|Foreign|abroad|Abroad)
      SERVER_REGION="global"
      SUB2API_DEPLOY_BASE="${SUB2API_DEPLOY_BASE_GLOBAL}"
      ;;
    *)
      die "SERVER_REGION 只能是 1/cn 或 2/global。"
      ;;
  esac

  if [ -z "${ACCESS_MODE}" ]; then
    echo
    echo "请选择访问方式："
    echo "1) 使用本机公网 IP 访问"
    echo "2) 填写域名访问"
    ACCESS_MODE="$(ask_choice "请输入 1 或 2 [默认 1]: " "1")"
  fi

  case "${ACCESS_MODE}" in
    1|ip|IP)
      ACCESS_MODE="ip"
      ;;
    2|domain|DOMAIN)
      ACCESS_MODE="domain"
      if [ -z "${DOMAIN}" ]; then
        if [ -r /dev/tty ]; then
          read -r -p "请输入你的域名，例如 api.example.com: " DOMAIN </dev/tty
        else
          read -r -p "请输入你的域名，例如 api.example.com: " DOMAIN
        fi
        [ -n "${DOMAIN}" ] || die "选择域名访问时，域名不能为空。"
      fi
      ;;
    *)
      die "ACCESS_MODE 只能是 1/ip 或 2/domain。"
      ;;
  esac
}

install_packages() {
  msg "安装基础依赖"
  if has_cmd apt-get; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y ca-certificates curl gnupg lsb-release openssl tar
  elif has_cmd dnf; then
    dnf install -y ca-certificates curl gnupg2 openssl tar
  elif has_cmd yum; then
    yum install -y ca-certificates curl gnupg2 openssl tar
  else
    die "找不到 apt-get/dnf/yum，无法自动安装依赖。"
  fi
}

install_bt_panel() {
  if [ "${INSTALL_BT}" != "1" ]; then
    msg "跳过宝塔安装，因为 INSTALL_BT=${INSTALL_BT}"
    return
  fi

  if [ -x /etc/init.d/bt ] || has_cmd bt; then
    msg "检测到宝塔面板已安装，跳过安装"
    return
  fi

  msg "安装宝塔面板"
  curl -fsSL "${BT_INSTALL_URL}" -o /tmp/install_bt_panel.sh
  yes y | bash /tmp/install_bt_panel.sh "${BT_INSTALL_ARGS}"
}

install_docker_from_system_repo() {
  if has_cmd apt-get; then
    apt-get update -y
    apt-get install -y docker.io
    if apt-cache show docker-compose-v2 >/dev/null 2>&1; then
      apt-get install -y docker-compose-v2
    elif apt-cache show docker-compose-plugin >/dev/null 2>&1; then
      apt-get install -y docker-compose-plugin
    else
      die "系统软件源里没有 Docker Compose v2。建议换 Ubuntu 22.04/24.04 或 Debian 12 后重试。"
    fi
  elif has_cmd dnf; then
    dnf install -y docker docker-compose-plugin
  elif has_cmd yum; then
    yum install -y docker docker-compose-plugin
  else
    die "无法自动安装 Docker：找不到 apt-get/dnf/yum。"
  fi
}

install_docker_from_official() {
  if curl -fsSL https://get.docker.com | sh; then
    msg "Docker 官方安装脚本执行完成"
  else
    msg "Docker 官方安装脚本失败，尝试使用系统软件源安装 Docker"
    install_docker_from_system_repo
  fi
}

configure_docker_mirror() {
  if [ "${SERVER_REGION}" != "cn" ]; then
    return
  fi

  msg "配置 Docker 镜像加速"
  mkdir -p /etc/docker
  if [ ! -f /etc/docker/daemon.json ]; then
    cat > /etc/docker/daemon.json <<EOF
{
  "registry-mirrors": ["${DOCKER_REGISTRY_MIRROR}"]
}
EOF
  elif ! grep -q "registry-mirrors" /etc/docker/daemon.json; then
    cp /etc/docker/daemon.json "/etc/docker/daemon.json.bak.$(date +%s)"
    cat > /etc/docker/daemon.json <<EOF
{
  "registry-mirrors": ["${DOCKER_REGISTRY_MIRROR}"]
}
EOF
    msg "已备份旧 Docker daemon.json，并写入镜像加速配置"
  else
    msg "检测到已有 Docker registry-mirrors，保留原配置"
  fi
}

install_docker() {
  if has_cmd docker; then
    msg "检测到 Docker 已安装，跳过 Docker 安装"
  else
    msg "安装 Docker"
    if [ "${SERVER_REGION}" = "cn" ]; then
      install_docker_from_system_repo
    else
      install_docker_from_official
    fi
  fi

  configure_docker_mirror

  if has_cmd systemctl; then
    systemctl daemon-reload || true
    systemctl enable --now docker || true
    systemctl restart docker || true
  else
    service docker start || true
  fi

  if ! docker compose version >/dev/null 2>&1; then
    die "Docker 已安装，但 docker compose 不可用。请升级 Docker 后重试。"
  fi
}

random_secret() {
  openssl rand -hex 32
}

public_ip() {
  local ip=""
  ip="$(curl -fsS --max-time 8 https://api.ipify.org || true)"
  if [ -z "${ip}" ]; then
    ip="$(curl -fsS --max-time 8 https://ifconfig.me || true)"
  fi
  printf '%s' "${ip}"
}

first_private_ip() {
  hostname -I 2>/dev/null | awk '{print $1}'
}

env_get() {
  local key="$1"
  if [ ! -f "${ENV_FILE}" ]; then
    return 0
  fi
  grep -E "^${key}=" "${ENV_FILE}" | tail -n 1 | cut -d= -f2-
}

env_set() {
  local key="$1"
  local value="$2"
  local escaped

  escaped="$(printf '%s' "${value}" | sed 's/[\/&]/\\&/g')"
  if grep -qE "^${key}=" "${ENV_FILE}"; then
    sed -i "s/^${key}=.*/${key}=${escaped}/" "${ENV_FILE}"
  else
    printf '%s=%s\n' "${key}" "${value}" >> "${ENV_FILE}"
  fi
}

download_file() {
  local url="$1"
  local output="$2"

  curl -fsSL --connect-timeout 20 -m 180 "${url}" -o "${output}"
}

prepare_sub2api_files() {
  mkdir -p "${APP_DIR}"
  cd "${APP_DIR}"

  if [ -f "${COMPOSE_FILE}" ] && [ -f "${ENV_FILE}" ]; then
    msg "检测到已有 sub2api 部署文件，保留原配置并补齐关键变量"
  else
    msg "下载并准备 sub2api 官方 Docker Compose 部署文件"
    download_file "${SUB2API_DEPLOY_BASE}/docker-compose.local.yml" "${COMPOSE_FILE}"
    download_file "${SUB2API_DEPLOY_BASE}/.env.example" "${APP_DIR}/.env.example"
    cp "${APP_DIR}/.env.example" "${ENV_FILE}"
  fi

  [ -f "${COMPOSE_FILE}" ] || die "没有找到 ${COMPOSE_FILE}"
  [ -f "${ENV_FILE}" ] || die "没有找到 ${ENV_FILE}"

  msg "写入 sub2api 管理账号、端口和固定密钥"
  env_set "BIND_HOST" "0.0.0.0"
  env_set "SERVER_PORT" "${SUB2API_PORT}"
  env_set "ADMIN_EMAIL" "${ADMIN_EMAIL}"

  ADMIN_PASSWORD="$(env_get ADMIN_PASSWORD)"
  if [ -z "${ADMIN_PASSWORD}" ]; then
    ADMIN_PASSWORD="$(random_secret)"
    env_set "ADMIN_PASSWORD" "${ADMIN_PASSWORD}"
  fi

  POSTGRES_PASSWORD="$(env_get POSTGRES_PASSWORD)"
  if [ -z "${POSTGRES_PASSWORD}" ] || [ "${POSTGRES_PASSWORD}" = "change_this_secure_password" ]; then
    POSTGRES_PASSWORD="$(random_secret)"
    env_set "POSTGRES_PASSWORD" "${POSTGRES_PASSWORD}"
  fi

  JWT_SECRET="$(env_get JWT_SECRET)"
  if [ -z "${JWT_SECRET}" ]; then
    JWT_SECRET="$(random_secret)"
    env_set "JWT_SECRET" "${JWT_SECRET}"
  fi

  TOTP_ENCRYPTION_KEY="$(env_get TOTP_ENCRYPTION_KEY)"
  if [ -z "${TOTP_ENCRYPTION_KEY}" ]; then
    TOTP_ENCRYPTION_KEY="$(random_secret)"
    env_set "TOTP_ENCRYPTION_KEY" "${TOTP_ENCRYPTION_KEY}"
  fi

  mkdir -p "${APP_DIR}/data" "${APP_DIR}/postgres_data" "${APP_DIR}/redis_data"
  chmod 600 "${ENV_FILE}"
}

deploy_app() {
  msg "启动 sub2api"
  mkdir -p "${APP_DIR}/data"
  cd "${APP_DIR}"
  docker compose pull
  docker compose up -d
}

bt_default_url() {
  local ip="$1"
  if [ -x /etc/init.d/bt ]; then
    /etc/init.d/bt default 2>/dev/null | sed -n 's/.*\(http[^ ]*\).*/\1/p' | head -n 1
  elif has_cmd bt; then
    bt default 2>/dev/null | sed -n 's/.*\(http[^ ]*\).*/\1/p' | head -n 1
  else
    printf 'http://%s:%s' "${ip}" "${BT_PORT}"
  fi
}

bt_panel_port() {
  local url="$1"
  local port=""

  port="$(printf '%s' "${url}" | sed -n 's#^[a-zA-Z][a-zA-Z0-9+.-]*://[^/:]*:\([0-9]\+\).*#\1#p')"
  [ -n "${port}" ] || port="${BT_PORT}"
  printf '%s' "${port}"
}

write_outputs() {
  local ip private_ip base_url bt_url domain_url bt_actual_port region_label access_label
  ip="$(public_ip)"
  private_ip="$(first_private_ip)"
  [ -n "${ip}" ] || ip="${private_ip}"

  base_url="http://${ip}:${SUB2API_PORT}"
  domain_url=""
  if [ -n "${DOMAIN}" ]; then
    domain_url="http://${DOMAIN}:${SUB2API_PORT}"
  fi

  bt_url="$(bt_default_url "${ip}")"
  [ -n "${bt_url}" ] || bt_url="http://${ip}:${BT_PORT}"
  bt_actual_port="$(bt_panel_port "${bt_url}")"

  if [ "${SERVER_REGION}" = "cn" ]; then
    region_label="国内服务器"
  else
    region_label="国外服务器"
  fi

  if [ "${ACCESS_MODE}" = "domain" ]; then
    access_label="域名访问"
  else
    access_label="本机IP访问"
  fi

  cat > "${INFO_FILE}" <<EOF
sub2api 部署信息
生成时间: $(date '+%F %T')

sub2api 访问地址:
- IP访问: ${base_url}
$(if [ -n "${domain_url}" ]; then printf -- '- 域名访问: %s\n' "${domain_url}"; fi)

sub2api 管理账号:
- 邮箱: ${ADMIN_EMAIL}
- 密码: ${ADMIN_PASSWORD}

宝塔面板:
- 面板入口: ${bt_url}
- 查看宝塔默认账号密码命令: bt default

服务器信息:
- 服务器网络: ${region_label}
- 访问方式: ${access_label}
- sub2api部署文件下载源: ${SUB2API_DEPLOY_BASE}
- 公网IP: ${ip}
- 内网IP: ${private_ip}
- 部署目录: ${APP_DIR}
- Compose文件: ${COMPOSE_FILE}
- 环境变量: ${ENV_FILE}
- PostgreSQL数据: ${APP_DIR}/postgres_data
- Redis数据: ${APP_DIR}/redis_data
- 信息总览: ${INFO_FILE}
- 安装日志: ${LOG_FILE}

常用命令:
- 查看 sub2api 状态: cd ${APP_DIR} && docker compose ps
- 查看 sub2api 日志: cd ${APP_DIR} && docker compose logs -f
- 重启 sub2api: cd ${APP_DIR} && docker compose restart
- 更新 sub2api: cd ${APP_DIR} && docker compose pull && docker compose up -d

============================================================

需要在云服务器安全组/防火墙开放的端口
生成时间: $(date '+%F %T')

必须开放:
- TCP 22      SSH 登录服务器
- TCP ${bt_actual_port}    宝塔面板入口，以 bt default 输出为准
- TCP ${SUB2API_PORT}    sub2api 访问端口

可选开放:
- TCP 80      如果你要用域名 HTTP 访问，或后续在宝塔/Nginx 配反向代理
- TCP 443     如果你要用域名 HTTPS 访问，或申请 SSL 证书

建议来源:
- 22: 只允许你的办公/家用公网 IP
- ${bt_actual_port}: 只允许你的办公/家用公网 IP
- ${SUB2API_PORT}: 如果要公开服务可允许 0.0.0.0/0；如果只自己用，限制为你的 IP
- 80/443: 绑定域名对外访问时允许 0.0.0.0/0

当前脚本开放的是服务器本机端口；云厂商安全组仍需你在控制台手动放行。
常见位置:
- 阿里云: ECS -> 安全组 -> 入方向
- 腾讯云: CVM -> 安全组 -> 入站规则
- AWS: EC2 -> Security Groups -> Inbound rules
- Azure: VM -> Networking -> Inbound port rules
- Google Cloud: VPC network -> Firewall
EOF
  chmod 600 "${INFO_FILE}"

  msg "安装完成"
  echo
  cat "${INFO_FILE}"
  echo
  echo "全部部署信息已写入: ${INFO_FILE}"
}

main() {
  need_root
  exec > >(tee -a "${LOG_FILE}") 2>&1
  detect_os
  ask_questions
  msg "系统: ${OS_ID} ${OS_VERSION_ID}"
  msg "服务器网络: ${SERVER_REGION}"
  msg "访问方式: ${ACCESS_MODE}"
  install_packages
  install_bt_panel
  install_docker
  prepare_sub2api_files
  deploy_app
  write_outputs
}

main "$@"
