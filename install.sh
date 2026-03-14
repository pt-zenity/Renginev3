#!/usr/bin/env bash
# =============================================================================
#  reNgine-ng  —  Auto Install Script for VPS
#  Repo   : https://github.com/pt-zenity/Renginev3
#  Target : Ubuntu 20.04 / 22.04 / 24.04  |  Debian 11 / 12
#  Run as : root  (or a user with sudo)
# =============================================================================
set -euo pipefail

# ─── Colour helpers ───────────────────────────────────────────────────────────
RED='\033[0;31m';  GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m';     RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; exit 1; }
step()    { echo -e "\n${BOLD}${CYAN}══════════════════════════════════════════${RESET}"; \
            echo -e "${BOLD}  $*${RESET}"; \
            echo -e "${BOLD}${CYAN}══════════════════════════════════════════${RESET}"; }

# ─── Banner ───────────────────────────────────────────────────────────────────
banner() {
cat << 'EOF'
  ____      _   _       _               _   _  _____ 
 |  _ \ ___| \ | | __ _(_)_ __   ___  | \ | |/ ____|
 | |_) / _ \  \| |/ _` | | '_ \ / _ \ |  \| | |  __ 
 |  _ <  __/ |\  | (_| | | | | |  __/ | |\  | | |_ |
 |_| \_\___|_| \_|\__, |_|_| |_|\___| |_| \_|\_____|
                  |___/                               
       Automated Reconnaissance Framework v3
       VPS Auto-Installer — github.com/pt-zenity/Renginev3
EOF
}

banner

# ─── Configuration — edit these or pass as env vars ──────────────────────────
INSTALL_DIR="${INSTALL_DIR:-/opt/rengine}"
RENGINE_VERSION="${RENGINE_VERSION:-latest}"

# Database
POSTGRES_DB="${POSTGRES_DB:-rengine}"
POSTGRES_USER="${POSTGRES_USER:-rengine}"
PGUSER="${PGUSER:-rengine}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9@#%^&*' | head -c 24)}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_HOST="${POSTGRES_HOST:-db}"

# Admin credentials
DJANGO_SUPERUSER_USERNAME="${DJANGO_SUPERUSER_USERNAME:-rengine}"
DJANGO_SUPERUSER_EMAIL="${DJANGO_SUPERUSER_EMAIL:-admin@rengine.local}"
DJANGO_SUPERUSER_PASSWORD="${DJANGO_SUPERUSER_PASSWORD:-$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c 18)}"

# SSL / domain
DOMAIN_NAME="${DOMAIN_NAME:-rengine.local}"
AUTHORITY_NAME="${AUTHORITY_NAME:-reNgine-ng}"
AUTHORITY_PASSWORD="${AUTHORITY_PASSWORD:-$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9' | head -c 12)}"
COUNTRY_CODE="${COUNTRY_CODE:-US}"
STATE="${STATE:-Georgia}"
CITY="${CITY:-Atlanta}"
COMPANY="${COMPANY:-reNgine-ng}"

# Celery / performance
MIN_CONCURRENCY="${MIN_CONCURRENCY:-5}"
MAX_CONCURRENCY="${MAX_CONCURRENCY:-30}"

# GPU
GPU="${GPU:-0}"
GPU_TYPE="${GPU_TYPE:-none}"
DOCKER_RUNTIME="${DOCKER_RUNTIME:-none}"

# Port exposed by nginx proxy (default 443)
PROXY_PORT="${PROXY_PORT:-443}"

# ─── Detect OS ───────────────────────────────────────────────────────────────
detect_os() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_ID="$ID"
    OS_VER="$VERSION_ID"
  else
    error "Cannot detect OS. /etc/os-release not found."
  fi

  case "$OS_ID" in
    ubuntu|debian) success "Detected OS: $OS_ID $OS_VER" ;;
    *) warn "Unsupported OS: $OS_ID. Continuing anyway — may require manual fixes." ;;
  esac
}

# ─── Ensure running as root ───────────────────────────────────────────────────
check_root() {
  if [ "$(id -u)" -ne 0 ]; then
    error "Please run this script as root:\n  sudo bash $0"
  fi
}

# ─── Check minimum RAM ────────────────────────────────────────────────────────
check_resources() {
  local ram_kb
  ram_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
  local ram_gb=$(( ram_kb / 1024 / 1024 ))
  if [ "$ram_gb" -lt 4 ]; then
    warn "System has only ~${ram_gb}GB RAM. reNgine-ng recommends ≥ 4GB (8GB+ for production)."
    read -rp "Continue anyway? [y/N] " confirm
    [[ "${confirm,,}" == "y" ]] || exit 1
  else
    success "RAM: ~${ram_gb}GB — OK"
  fi

  local disk_gb
  disk_gb=$(df -BG / | awk 'NR==2 {gsub("G","",$4); print $4}')
  if [ "$disk_gb" -lt 20 ]; then
    warn "Only ${disk_gb}GB free on /. Recommend ≥ 20GB."
  else
    success "Disk: ${disk_gb}GB free — OK"
  fi
}

# ─── Update system packages ───────────────────────────────────────────────────
update_system() {
  step "1/8  Updating system packages"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get upgrade -y -qq
  apt-get install -y -qq \
    curl wget git unzip gnupg2 ca-certificates \
    lsb-release apt-transport-https software-properties-common \
    openssl net-tools ufw
  success "System packages updated."
}

# ─── Install Docker ───────────────────────────────────────────────────────────
install_docker() {
  step "2/8  Installing Docker Engine"

  if command -v docker &>/dev/null; then
    success "Docker already installed: $(docker --version)"
    return
  fi

  # Official Docker convenience script
  curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
  sh /tmp/get-docker.sh
  rm -f /tmp/get-docker.sh

  systemctl enable docker
  systemctl start docker

  success "Docker installed: $(docker --version)"
}

# ─── Install Docker Compose ───────────────────────────────────────────────────
install_compose() {
  step "3/8  Installing Docker Compose v2"

  if docker compose version &>/dev/null 2>&1; then
    success "Docker Compose already installed: $(docker compose version)"
    return
  fi

  # Docker Compose v2 via plugin
  apt-get install -y -qq docker-compose-plugin 2>/dev/null || \
  curl -fsSL "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
       -o /usr/local/bin/docker-compose && \
  chmod +x /usr/local/bin/docker-compose && \
  ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose

  success "Docker Compose: $(docker compose version 2>/dev/null || docker-compose --version)"
}

# ─── Clone / update repository ───────────────────────────────────────────────
setup_repo() {
  step "4/8  Setting up reNgine-ng repository"

  REPO_URL="https://github.com/pt-zenity/Renginev3.git"

  if [ -d "$INSTALL_DIR/.git" ]; then
    info "Repository already exists at $INSTALL_DIR — pulling latest changes…"
    git -C "$INSTALL_DIR" pull --ff-only
  else
    info "Cloning repository to $INSTALL_DIR …"
    git clone --depth=1 "$REPO_URL" "$INSTALL_DIR"
  fi

  success "Repository ready at: $INSTALL_DIR"
}

# ─── Detect reNgine version ───────────────────────────────────────────────────
detect_version() {
  if [ "$RENGINE_VERSION" = "latest" ]; then
    if [ -f "$INSTALL_DIR/web/reNgine/version.py" ]; then
      RENGINE_VERSION=$(grep -oP "__version__\s*=\s*['\"]?\K[0-9]+\.[0-9]+\.[0-9]+" \
        "$INSTALL_DIR/web/reNgine/version.py" 2>/dev/null || echo "3.0.0")
    else
      RENGINE_VERSION="3.0.0"
    fi
  fi
  info "reNgine-ng version: $RENGINE_VERSION"
}

# ─── Generate .env file ───────────────────────────────────────────────────────
generate_env() {
  step "5/8  Generating environment configuration"

  ENV_FILE="$INSTALL_DIR/.env"

  # Backup existing .env
  if [ -f "$ENV_FILE" ]; then
    cp "$ENV_FILE" "${ENV_FILE}.bak.$(date +%Y%m%d%H%M%S)"
    warn "Existing .env backed up."
  fi

  cat > "$ENV_FILE" << EOF
# =============================================================
#  reNgine-ng — Environment Configuration
#  Generated by install.sh on $(date)
# =============================================================

COMPOSE_PROJECT_NAME=rengine
RENGINE_VERSION=${RENGINE_VERSION}

# ─── SSL / Domain ────────────────────────────────────────────
AUTHORITY_NAME=${AUTHORITY_NAME}
AUTHORITY_PASSWORD=${AUTHORITY_PASSWORD}
COMPANY=${COMPANY}
DOMAIN_NAME=${DOMAIN_NAME}
COUNTRY_CODE=${COUNTRY_CODE}
STATE=${STATE}
CITY=${CITY}

# ─── Database ────────────────────────────────────────────────
POSTGRES_DB=${POSTGRES_DB}
POSTGRES_USER=${POSTGRES_USER}
PGUSER=${PGUSER}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_PORT=${POSTGRES_PORT}
POSTGRES_HOST=${POSTGRES_HOST}

# ─── Django Superuser ────────────────────────────────────────
DJANGO_SUPERUSER_USERNAME=${DJANGO_SUPERUSER_USERNAME}
DJANGO_SUPERUSER_EMAIL=${DJANGO_SUPERUSER_EMAIL}
DJANGO_SUPERUSER_PASSWORD=${DJANGO_SUPERUSER_PASSWORD}

# ─── Celery ──────────────────────────────────────────────────
MIN_CONCURRENCY=${MIN_CONCURRENCY}
MAX_CONCURRENCY=${MAX_CONCURRENCY}

# ─── Installation ────────────────────────────────────────────
INSTALL_TYPE=prebuilt

# ─── GPU (set GPU=1 to enable) ───────────────────────────────
GPU=${GPU}
GPU_TYPE=${GPU_TYPE}
DOCKER_RUNTIME=${DOCKER_RUNTIME}

# ─── Ollama LLM ──────────────────────────────────────────────
OLLAMA_INSTANCE=http://ollama:11434
EOF

  chmod 600 "$ENV_FILE"
  success ".env file created at $ENV_FILE"
}

# ─── Generate SSL certificates ───────────────────────────────────────────────
generate_certs() {
  step "6/8  Generating SSL certificates"

  CERTS_DIR="$INSTALL_DIR/docker/secrets/certs"
  mkdir -p "$CERTS_DIR"

  if [ -f "$CERTS_DIR/rengine.pem" ]; then
    success "SSL certificates already exist — skipping generation."
    return
  fi

  cd "$INSTALL_DIR/docker"

  # Use docker-compose.setup.yml if it exists (official cert generator)
  if [ -f "docker-compose.setup.yml" ]; then
    info "Running certificate generator container…"
    docker compose -f docker-compose.setup.yml --env-file "$INSTALL_DIR/.env" up --no-build 2>&1 | tail -5 || true
    # Check if certs were generated
    if [ -f "$CERTS_DIR/rengine.pem" ]; then
      success "SSL certificates generated via Docker."
      return
    fi
  fi

  # Fallback: generate self-signed certs directly with openssl
  warn "Generating self-signed certificates with openssl (fallback)…"
  local subj="/C=${COUNTRY_CODE}/ST=${STATE}/L=${CITY}/O=${COMPANY}/CN=${DOMAIN_NAME}"

  # CA key + cert
  openssl genrsa -passout "pass:${AUTHORITY_PASSWORD}" -aes256 -out "$CERTS_DIR/ca.key" 4096 2>/dev/null
  openssl req -new -x509 -days 3650 \
    -passin "pass:${AUTHORITY_PASSWORD}" \
    -key "$CERTS_DIR/ca.key" \
    -out "$CERTS_DIR/rengine_chain.pem" \
    -subj "$subj/CN=${AUTHORITY_NAME} CA" 2>/dev/null

  # Server key + CSR
  openssl genrsa -out "$CERTS_DIR/rengine_rsa.key" 4096 2>/dev/null
  openssl req -new \
    -key "$CERTS_DIR/rengine_rsa.key" \
    -out "$CERTS_DIR/rengine.csr" \
    -subj "$subj" 2>/dev/null

  # Sign with CA
  openssl x509 -req -days 3650 \
    -in "$CERTS_DIR/rengine.csr" \
    -CA "$CERTS_DIR/rengine_chain.pem" \
    -CAkey "$CERTS_DIR/ca.key" \
    -passin "pass:${AUTHORITY_PASSWORD}" \
    -CAcreateserial \
    -out "$CERTS_DIR/rengine.pem" 2>/dev/null

  chmod 600 "$CERTS_DIR"/*.key "$CERTS_DIR"/*.pem 2>/dev/null || true
  success "Self-signed SSL certificates generated."
}

# ─── Configure firewall ───────────────────────────────────────────────────────
configure_firewall() {
  step "7/8  Configuring UFW firewall"

  if ! command -v ufw &>/dev/null; then
    warn "ufw not found — skipping firewall configuration."
    return
  fi

  ufw --force reset >/dev/null
  ufw default deny incoming >/dev/null
  ufw default allow outgoing >/dev/null
  ufw allow ssh         comment "SSH" >/dev/null
  ufw allow 443/tcp     comment "reNgine-ng HTTPS" >/dev/null
  ufw allow 8082/tcp    comment "reNgine-ng HTTP redirect" >/dev/null
  ufw --force enable >/dev/null

  success "Firewall configured: SSH, 443/tcp, 8082/tcp allowed."
}

# ─── Pull images and start services ──────────────────────────────────────────
start_services() {
  step "8/8  Pulling Docker images and starting reNgine-ng"

  cd "$INSTALL_DIR/docker"

  info "Pulling Docker images (this may take 5–15 minutes)…"
  docker compose --env-file "$INSTALL_DIR/.env" pull 2>&1 | \
    grep -E "^(Pull|Pulling|Pulled|Error)" || true

  info "Starting all services…"
  docker compose --env-file "$INSTALL_DIR/.env" up -d

  success "Docker services started."
}

# ─── Wait for web service to be healthy ──────────────────────────────────────
wait_healthy() {
  info "Waiting for reNgine-ng web service to become healthy…"
  local max_wait=180
  local waited=0
  local interval=10

  while [ $waited -lt $max_wait ]; do
    local status
    status=$(docker inspect --format='{{.State.Health.Status}}' rengine-web-1 2>/dev/null || echo "starting")
    if [ "$status" = "healthy" ]; then
      success "reNgine-ng is healthy and ready!"
      return
    fi
    info "Status: ${status} — waiting ${interval}s… (${waited}/${max_wait}s)"
    sleep $interval
    waited=$((waited + interval))
  done

  warn "Service did not become healthy within ${max_wait}s. Check logs: docker logs rengine-web-1"
}

# ─── Print summary ────────────────────────────────────────────────────────────
print_summary() {
  # Detect public IP
  local PUBLIC_IP
  PUBLIC_IP=$(curl -4 -s --max-time 5 https://ifconfig.me 2>/dev/null || \
              curl -4 -s --max-time 5 https://api.ipify.org 2>/dev/null || \
              hostname -I | awk '{print $1}')

  echo ""
  echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════╗${RESET}"
  echo -e "${BOLD}${GREEN}║       reNgine-ng Installation Complete! 🎉       ║${RESET}"
  echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════╝${RESET}"
  echo ""
  echo -e "${BOLD}  Access URL   :${RESET}  https://${PUBLIC_IP}"
  echo -e "${BOLD}  Domain       :${RESET}  ${DOMAIN_NAME}"
  echo -e "${BOLD}  Install Dir  :${RESET}  ${INSTALL_DIR}"
  echo ""
  echo -e "${BOLD}  ─── Login Credentials ──────────────────────────────${RESET}"
  echo -e "${BOLD}  Username     :${RESET}  ${DJANGO_SUPERUSER_USERNAME}"
  echo -e "${BOLD}  Password     :${RESET}  ${DJANGO_SUPERUSER_PASSWORD}"
  echo ""
  echo -e "${BOLD}  ─── Database ────────────────────────────────────────${RESET}"
  echo -e "${BOLD}  DB User      :${RESET}  ${POSTGRES_USER}"
  echo -e "${BOLD}  DB Password  :${RESET}  ${POSTGRES_PASSWORD}"
  echo ""
  echo -e "${YELLOW}  ⚠  IMPORTANT: Save these credentials now!${RESET}"
  echo -e "${YELLOW}     They are also stored in: ${INSTALL_DIR}/.env${RESET}"
  echo ""
  echo -e "${BOLD}  ─── Management Commands ─────────────────────────────${RESET}"
  echo -e "  Start    :  cd ${INSTALL_DIR}/docker && docker compose up -d"
  echo -e "  Stop     :  cd ${INSTALL_DIR}/docker && docker compose down"
  echo -e "  Restart  :  cd ${INSTALL_DIR}/docker && docker compose restart"
  echo -e "  Logs     :  cd ${INSTALL_DIR}/docker && docker compose logs -f"
  echo -e "  Update   :  cd ${INSTALL_DIR} && git pull && cd docker && docker compose pull && docker compose up -d"
  echo ""
  echo -e "${CYAN}  Certificate is self-signed — accept the browser warning on first visit.${RESET}"
  echo -e "${CYAN}  To use a real domain: update DOMAIN_NAME in ${INSTALL_DIR}/.env${RESET}"
  echo ""

  # Save summary to file
  cat > "${INSTALL_DIR}/INSTALL_SUMMARY.txt" << SUMMARY
reNgine-ng Install Summary — $(date)
======================================================
Access URL   : https://${PUBLIC_IP}
Domain       : ${DOMAIN_NAME}
Install Dir  : ${INSTALL_DIR}

Login Credentials
  Username   : ${DJANGO_SUPERUSER_USERNAME}
  Password   : ${DJANGO_SUPERUSER_PASSWORD}

Database
  DB User    : ${POSTGRES_USER}
  DB Password: ${POSTGRES_PASSWORD}

Management
  Start  : cd ${INSTALL_DIR}/docker && docker compose up -d
  Stop   : cd ${INSTALL_DIR}/docker && docker compose down
  Logs   : cd ${INSTALL_DIR}/docker && docker compose logs -f
SUMMARY
  chmod 600 "${INSTALL_DIR}/INSTALL_SUMMARY.txt"
  success "Summary saved to: ${INSTALL_DIR}/INSTALL_SUMMARY.txt"
}

# ─── Optional: interactive configuration ──────────────────────────────────────
interactive_config() {
  if [ "${NONINTERACTIVE:-0}" = "1" ]; then
    return
  fi

  echo ""
  echo -e "${BOLD}Configuration Setup (press Enter to accept defaults)${RESET}"
  echo ""

  read -rp "  Domain name [${DOMAIN_NAME}]: " input
  DOMAIN_NAME="${input:-$DOMAIN_NAME}"

  read -rp "  Admin username [${DJANGO_SUPERUSER_USERNAME}]: " input
  DJANGO_SUPERUSER_USERNAME="${input:-$DJANGO_SUPERUSER_USERNAME}"

  read -rp "  Admin password [auto-generated, press Enter]: " input
  if [ -n "$input" ]; then
    DJANGO_SUPERUSER_PASSWORD="$input"
  fi

  read -rp "  Admin email [${DJANGO_SUPERUSER_EMAIL}]: " input
  DJANGO_SUPERUSER_EMAIL="${input:-$DJANGO_SUPERUSER_EMAIL}"

  read -rp "  Install directory [${INSTALL_DIR}]: " input
  INSTALL_DIR="${input:-$INSTALL_DIR}"

  read -rp "  Enable GPU support? (requires NVIDIA/AMD) [y/N]: " input
  if [[ "${input,,}" == "y" ]]; then
    GPU=1
    GPU_TYPE="nvidia"
    DOCKER_RUNTIME="nvidia"
    warn "GPU enabled. Ensure nvidia-container-toolkit is installed."
  fi

  echo ""
}

# ─── Check Docker GPU runtime (optional) ──────────────────────────────────────
setup_gpu() {
  if [ "$GPU" != "1" ]; then
    return
  fi

  info "Checking NVIDIA GPU support…"
  if ! command -v nvidia-smi &>/dev/null; then
    warn "nvidia-smi not found. Disabling GPU support."
    GPU=0; GPU_TYPE=none; DOCKER_RUNTIME=none
    return
  fi

  # Install nvidia-container-toolkit
  distribution=$(. /etc/os-release; echo $ID$VERSION_ID)
  curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
    gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
  curl -fsSL "https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list" | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
    tee /etc/apt/sources.list.d/nvidia-container-toolkit.list >/dev/null
  apt-get update -qq
  apt-get install -y -qq nvidia-container-toolkit
  nvidia-ctk runtime configure --runtime=docker
  systemctl restart docker
  success "NVIDIA container toolkit installed."
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
  echo ""
  check_root
  detect_os
  check_resources

  # Ask questions before doing any work
  interactive_config

  update_system
  install_docker
  install_compose
  setup_gpu
  setup_repo
  detect_version
  generate_env
  generate_certs
  configure_firewall
  start_services
  wait_healthy
  print_summary
}

main "$@"
