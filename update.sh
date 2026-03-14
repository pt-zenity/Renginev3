#!/usr/bin/env bash
# =============================================================================
#  reNgine-ng  —  Update / Upgrade Script
#  Repo    : https://github.com/pt-zenity/Renginev3
#  Purpose : Upgrade an existing reNgine-ng installation to the latest version
#            Supports: v1.x → v2.x → v3.x migration paths
#  Run as  : root (or user with sudo)
#  Usage   : sudo bash update.sh [OPTIONS]
#
#  Options:
#    --dir <path>       Override installation directory (default: auto-detect)
#    --version <ver>    Target version tag  (default: latest from GitHub)
#    --backup-only      Create backup then exit, no upgrade
#    --skip-backup      Skip backup step (NOT recommended)
#    --skip-pull        Skip git pull / image pull (use local code only)
#    --force            Force update even if already on latest version
#    --yes              Non-interactive / assume yes to all prompts
#    --rollback         Rollback to the last backup
#    -h, --help         Show this help
# =============================================================================
set -euo pipefail

# ─── Colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m';  GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; MAGENTA='\033[0;35m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[ OK ]${RESET}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERR ]${RESET}  $*" >&2; exit 1; }
step()    { echo -e "\n${BOLD}${CYAN}══════════════════════════════════════════════════${RESET}"
            echo -e "${BOLD}  $*${RESET}"
            echo -e "${BOLD}${CYAN}══════════════════════════════════════════════════${RESET}"; }
ask()     { echo -e "${MAGENTA}[ASK ]${RESET}  $*"; }

# ─── Banner ───────────────────────────────────────────────────────────────────
banner() {
cat << 'EOF'
  _   _           _       _         ____            _____           _
 | | | |_ __   __| | __ _| |_ ___  |  _ \ ___  _ _|_   _|__   ___ | |___
 | | | | '_ \ / _` |/ _` | __/ _ \ | |_) / _ \| '_ \| |/ _ \ / _ \| / __|
 | |_| | |_) | (_| | (_| | ||  __/ |  _ <  __/| | | | | (_) | (_) | \__ \
  \___/| .__/ \__,_|\__,_|\__\___| |_| \_\___||_| |_|_|\___/ \___/|_|___/
       |_|
         reNgine-ng — Update Script  |  github.com/pt-zenity/Renginev3
EOF
}

banner
echo ""

# ─── Default configuration ────────────────────────────────────────────────────
INSTALL_DIR=""           # auto-detect
TARGET_VERSION=""        # auto-detect latest
BACKUP_ONLY=false
SKIP_BACKUP=false
SKIP_PULL=false
FORCE_UPDATE=false
ASSUME_YES=false
ROLLBACK=false

GITHUB_REPO="https://github.com/Security-Tools-Alliance/rengine-ng"
CUSTOM_REPO="https://github.com/pt-zenity/Renginev3"
BACKUP_BASE="/opt/rengine-backups"
LOG_FILE="/var/log/rengine-update-$(date +%Y%m%d_%H%M%S).log"
COMPOSE_FILE=""

# ─── Argument parsing ─────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)      INSTALL_DIR="$2"; shift 2 ;;
    --version)  TARGET_VERSION="$2"; shift 2 ;;
    --backup-only)   BACKUP_ONLY=true; shift ;;
    --skip-backup)   SKIP_BACKUP=true; shift ;;
    --skip-pull)     SKIP_PULL=true; shift ;;
    --force)         FORCE_UPDATE=true; shift ;;
    --yes|-y)        ASSUME_YES=true; shift ;;
    --rollback)      ROLLBACK=true; shift ;;
    -h|--help)
      echo "Usage: sudo bash update.sh [OPTIONS]"
      echo ""
      echo "  --dir <path>       Installation directory (auto-detected)"
      echo "  --version <ver>    Target version (default: latest)"
      echo "  --backup-only      Backup only, then exit"
      echo "  --skip-backup      Skip backup step (not recommended)"
      echo "  --skip-pull        Skip git pull / docker pull"
      echo "  --force            Force update even if on latest"
      echo "  --yes              Non-interactive mode"
      echo "  --rollback         Rollback to last backup"
      echo "  -h, --help         Show this help"
      exit 0 ;;
    *) warn "Unknown option: $1"; shift ;;
  esac
done

# ─── Logging setup ────────────────────────────────────────────────────────────
exec > >(tee -a "$LOG_FILE") 2>&1
info "Update log: $LOG_FILE"

# ─── Helper: confirm prompt ───────────────────────────────────────────────────
confirm() {
  local msg="$1"
  local default="${2:-y}"
  if [[ "$ASSUME_YES" == "true" ]]; then
    return 0
  fi
  local prompt
  if [[ "$default" == "y" ]]; then
    prompt="[Y/n]"
  else
    prompt="[y/N]"
  fi
  ask "$msg $prompt "
  read -r answer
  answer="${answer:-$default}"
  [[ "${answer,,}" == "y" ]]
}

# ─── Prerequisite checks ──────────────────────────────────────────────────────
check_prerequisites() {
  step "Checking prerequisites"

  # Must run as root
  if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root. Try: sudo bash update.sh"
  fi
  success "Running as root"

  # Docker
  if ! command -v docker &>/dev/null; then
    error "Docker is not installed. Run install.sh first."
  fi
  success "Docker found: $(docker --version | head -1)"

  # Docker Compose (v2 plugin preferred, v1 standalone fallback)
  if docker compose version &>/dev/null 2>&1; then
    DOCKER_COMPOSE="docker compose"
    success "Docker Compose (v2 plugin): $(docker compose version --short)"
  elif command -v docker-compose &>/dev/null; then
    DOCKER_COMPOSE="docker-compose"
    success "Docker Compose (v1 standalone): $(docker-compose --version)"
  else
    error "Docker Compose is not installed. Run install.sh first."
  fi

  # git (optional — needed if using source install)
  if command -v git &>/dev/null; then
    success "git found: $(git --version)"
  else
    warn "git not found — source-based pull will be skipped"
  fi

  # curl / wget
  if command -v curl &>/dev/null; then
    HTTP_CMD="curl -fsSL"
  elif command -v wget &>/dev/null; then
    HTTP_CMD="wget -qO-"
  else
    warn "Neither curl nor wget found — remote version check unavailable"
    HTTP_CMD=""
  fi
}

# ─── Auto-detect installation directory ──────────────────────────────────────
detect_install_dir() {
  step "Detecting installation directory"

  if [[ -n "$INSTALL_DIR" ]]; then
    [[ -d "$INSTALL_DIR" ]] || error "Specified --dir does not exist: $INSTALL_DIR"
    success "Using specified directory: $INSTALL_DIR"
    return
  fi

  local candidates=(
    "/opt/rengine"
    "/opt/rengine-ng"
    "$HOME/rengine"
    "$HOME/rengine-ng"
    "/srv/rengine"
    "/home/rengine/rengine"
  )

  # Also check if docker containers are running and get their mount paths
  local running_dir
  running_dir=$(docker inspect rengine-web-1 2>/dev/null \
    | python3 -c "
import sys, json
data = json.load(sys.stdin)
if data:
    mounts = data[0].get('Mounts', [])
    for m in mounts:
        if m.get('Destination') == '/home/rengine/rengine':
            print(m.get('Source', ''))
            break
" 2>/dev/null || true)

  if [[ -n "$running_dir" && -d "$running_dir" ]]; then
    # Go up one level (web dir → project root)
    INSTALL_DIR="$(dirname "$running_dir")"
    success "Detected from running container: $INSTALL_DIR"
    return
  fi

  for dir in "${candidates[@]}"; do
    if [[ -f "$dir/docker/docker-compose.yml" || -f "$dir/.env" ]]; then
      INSTALL_DIR="$dir"
      success "Detected installation directory: $INSTALL_DIR"
      return
    fi
  done

  error "Could not auto-detect installation directory. Use --dir <path>"
}

# ─── Determine docker-compose file path ──────────────────────────────────────
detect_compose_file() {
  local candidates=(
    "$INSTALL_DIR/docker/docker-compose.yml"
    "$INSTALL_DIR/docker-compose.yml"
    "$INSTALL_DIR/docker-compose.yaml"
  )
  for f in "${candidates[@]}"; do
    if [[ -f "$f" ]]; then
      COMPOSE_FILE="$f"
      success "docker-compose file: $COMPOSE_FILE"
      return
    fi
  done
  error "docker-compose file not found in $INSTALL_DIR"
}

# ─── Read current version ─────────────────────────────────────────────────────
get_current_version() {
  local ver_candidates=(
    "$INSTALL_DIR/web/reNgine/version.txt"
    "$INSTALL_DIR/reNgine/version.txt"
  )
  for f in "${ver_candidates[@]}"; do
    if [[ -f "$f" ]]; then
      CURRENT_VERSION=$(cat "$f" | tr -d '[:space:]')
      info "Current installed version: v$CURRENT_VERSION"
      return
    fi
  done
  CURRENT_VERSION="unknown"
  warn "Could not determine current version"
}

# ─── Fetch latest version from GitHub ────────────────────────────────────────
get_latest_version() {
  if [[ -n "$TARGET_VERSION" ]]; then
    info "Target version (manual): $TARGET_VERSION"
    return
  fi

  if [[ -z "$HTTP_CMD" ]]; then
    warn "Cannot fetch latest version (no curl/wget). Use --version to specify."
    TARGET_VERSION="latest"
    return
  fi

  local api_url="https://api.github.com/repos/Security-Tools-Alliance/rengine-ng/releases/latest"
  local latest
  latest=$($HTTP_CMD "$api_url" 2>/dev/null \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tag_name','').lstrip('v'))" \
    2>/dev/null || echo "")

  if [[ -n "$latest" ]]; then
    TARGET_VERSION="$latest"
    info "Latest upstream version: v$TARGET_VERSION"
  else
    warn "Could not fetch latest version from GitHub API. Using 'latest' tag."
    TARGET_VERSION="latest"
  fi
}

# ─── Compare versions ─────────────────────────────────────────────────────────
version_lt() {
  # Returns 0 (true) if $1 < $2
  [[ "$1" == "$2" ]] && return 1
  local IFS=.
  local i ver1=($1) ver2=($2)
  for (( i=0; i<${#ver1[@]}; i++ )); do
    [[ "${ver1[i]:-0}" -lt "${ver2[i]:-0}" ]] && return 0
    [[ "${ver1[i]:-0}" -gt "${ver2[i]:-0}" ]] && return 1
  done
  return 1
}

check_version_change() {
  if [[ "$CURRENT_VERSION" == "unknown" ]] || [[ "$TARGET_VERSION" == "latest" ]]; then
    return  # proceed
  fi
  if [[ "$CURRENT_VERSION" == "$TARGET_VERSION" ]] && [[ "$FORCE_UPDATE" == "false" ]]; then
    info "Already on version v$CURRENT_VERSION. Use --force to re-run update."
    exit 0
  fi
  info "Upgrading: v$CURRENT_VERSION  →  v$TARGET_VERSION"
}

# ─── Read .env ────────────────────────────────────────────────────────────────
load_env() {
  local env_file="$INSTALL_DIR/.env"
  if [[ -f "$env_file" ]]; then
    # Export all non-comment lines (safely, ignoring errors)
    set -a
    # shellcheck disable=SC1090
    source <(grep -v '^\s*#' "$env_file" | grep -v '^\s*$') 2>/dev/null || true
    set +a
    success "Loaded .env from $env_file"
  else
    warn ".env not found at $env_file"
  fi
}

# ─── Create backup ────────────────────────────────────────────────────────────
BACKUP_DIR=""
create_backup() {
  if [[ "$SKIP_BACKUP" == "true" ]]; then
    warn "Skipping backup (--skip-backup specified)"
    return
  fi

  step "Creating backup"
  mkdir -p "$BACKUP_BASE"

  local ts
  ts=$(date +%Y%m%d_%H%M%S)
  local ver_slug="${CURRENT_VERSION//./}"
  BACKUP_DIR="$BACKUP_BASE/rengine-v${ver_slug}-${ts}"
  mkdir -p "$BACKUP_DIR"

  # 1. Dump PostgreSQL database
  info "Dumping PostgreSQL database..."
  local pg_container
  pg_container=$(docker ps --filter "name=rengine-db" --format "{{.Names}}" | head -1 || true)
  if [[ -n "$pg_container" ]]; then
    docker exec "$pg_container" \
      pg_dumpall -U "${POSTGRES_USER:-rengine}" \
      > "$BACKUP_DIR/postgres_full_dump.sql" 2>/dev/null \
      && success "PostgreSQL dump: $BACKUP_DIR/postgres_full_dump.sql" \
      || warn "PostgreSQL dump failed — continuing"
  else
    warn "PostgreSQL container not running — skipping DB dump"
  fi

  # 2. Copy config files
  info "Backing up configuration files..."
  cp -p "$INSTALL_DIR/.env" "$BACKUP_DIR/.env.bak" 2>/dev/null || true
  cp -p "$INSTALL_DIR/docker/docker-compose.yml" \
        "$BACKUP_DIR/docker-compose.yml.bak" 2>/dev/null || true

  # 3. Backup custom wordlists and nuclei templates
  if [[ -d "$INSTALL_DIR/wordlists" ]]; then
    info "Backing up custom wordlists..."
    tar -czf "$BACKUP_DIR/wordlists.tar.gz" \
      -C "$INSTALL_DIR" wordlists/ 2>/dev/null \
      && success "Wordlists backed up" || warn "Wordlist backup skipped"
  fi

  if [[ -d "$INSTALL_DIR/nuclei-templates" ]]; then
    info "Backing up custom nuclei templates..."
    tar -czf "$BACKUP_DIR/nuclei-templates.tar.gz" \
      -C "$INSTALL_DIR" nuclei-templates/ 2>/dev/null \
      && success "Nuclei templates backed up" || warn "Nuclei templates backup skipped"
  fi

  # 4. Backup web directory (excluding large dirs)
  info "Backing up web application code..."
  tar -czf "$BACKUP_DIR/web.tar.gz" \
    --exclude="$INSTALL_DIR/web/__pycache__" \
    --exclude="$INSTALL_DIR/web/*.pyc" \
    --exclude="$INSTALL_DIR/web/staticfiles_collected" \
    --exclude="$INSTALL_DIR/web/db_local.sqlite3" \
    -C "$INSTALL_DIR" web/ 2>/dev/null \
    && success "Web directory backed up" || warn "Web backup skipped"

  # 5. Backup named Docker volumes (optional — can be large)
  info "Creating Docker volume manifest..."
  docker volume ls --filter "name=rengine_" --format "{{.Name}}" \
    > "$BACKUP_DIR/docker_volumes.txt" 2>/dev/null || true
  success "Volume list saved"

  # Write backup manifest
  cat > "$BACKUP_DIR/BACKUP_INFO.txt" << EOF
reNgine-ng Backup
=================
Date        : $(date)
Version     : v${CURRENT_VERSION}
Target      : v${TARGET_VERSION}
Install Dir : ${INSTALL_DIR}
Hostname    : $(hostname -f 2>/dev/null || hostname)
Backup Dir  : ${BACKUP_DIR}

Files:
$(ls -lh "$BACKUP_DIR" 2>/dev/null | tail -n +2)
EOF

  success "Backup complete: $BACKUP_DIR"
}

# ─── Rollback ─────────────────────────────────────────────────────────────────
do_rollback() {
  step "Rolling back to last backup"

  if [[ ! -d "$BACKUP_BASE" ]] || [[ -z "$(ls -A "$BACKUP_BASE" 2>/dev/null)" ]]; then
    error "No backups found in $BACKUP_BASE"
  fi

  # Find the most recent backup
  local last_backup
  last_backup=$(ls -td "$BACKUP_BASE"/rengine-* 2>/dev/null | head -1 || true)
  if [[ -z "$last_backup" ]]; then
    error "No backup directories found in $BACKUP_BASE"
  fi

  info "Last backup: $last_backup"
  cat "$last_backup/BACKUP_INFO.txt" 2>/dev/null || true
  echo ""

  if ! confirm "Rollback to this backup? All current data will be overwritten!"; then
    info "Rollback cancelled."
    exit 0
  fi

  # Stop services
  info "Stopping services..."
  $DOCKER_COMPOSE -f "$COMPOSE_FILE" down --timeout 30 2>/dev/null || true

  # Restore PostgreSQL
  if [[ -f "$last_backup/postgres_full_dump.sql" ]]; then
    info "Restoring PostgreSQL database..."
    $DOCKER_COMPOSE -f "$COMPOSE_FILE" up -d db
    sleep 10
    local pg_container
    pg_container=$(docker ps --filter "name=rengine-db" --format "{{.Names}}" | head -1)
    if [[ -n "$pg_container" ]]; then
      docker exec -i "$pg_container" \
        psql -U "${POSTGRES_USER:-rengine}" \
        < "$last_backup/postgres_full_dump.sql" 2>/dev/null \
        && success "Database restored" \
        || warn "Database restore had errors — check manually"
    fi
  fi

  # Restore config
  [[ -f "$last_backup/.env.bak" ]] && \
    cp "$last_backup/.env.bak" "$INSTALL_DIR/.env" && \
    info ".env restored"

  # Restore web directory
  if [[ -f "$last_backup/web.tar.gz" ]]; then
    info "Restoring web directory..."
    rm -rf "$INSTALL_DIR/web" 2>/dev/null || true
    tar -xzf "$last_backup/web.tar.gz" -C "$INSTALL_DIR/" \
      && success "Web directory restored" \
      || warn "Web directory restore had errors"
  fi

  # Restart services
  info "Restarting services..."
  $DOCKER_COMPOSE -f "$COMPOSE_FILE" up -d
  success "Rollback complete. Services starting..."
  exit 0
}

# ─── Stop services gracefully ─────────────────────────────────────────────────
stop_services() {
  step "Stopping reNgine-ng services"
  local compose_dir
  compose_dir="$(dirname "$COMPOSE_FILE")"

  info "Stopping containers gracefully (60s timeout)..."
  cd "$compose_dir"
  $DOCKER_COMPOSE down --timeout 60 2>/dev/null \
    && success "All containers stopped" \
    || warn "Some containers may not have stopped cleanly"
}

# ─── Pull new code ────────────────────────────────────────────────────────────
pull_code() {
  if [[ "$SKIP_PULL" == "true" ]]; then
    warn "Skipping code pull (--skip-pull specified)"
    return
  fi

  step "Pulling latest code"

  # Check if this is a git repository
  if [[ -d "$INSTALL_DIR/.git" ]] && command -v git &>/dev/null; then
    info "Git repository detected — pulling latest changes..."
    cd "$INSTALL_DIR"

    # Stash local changes (e.g., .env modifications)
    git stash --include-untracked 2>/dev/null || true

    local branch
    branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
    info "Current branch: $branch"

    git fetch origin 2>/dev/null || warn "git fetch failed — using local code"
    git reset --hard "origin/$branch" 2>/dev/null || \
      git reset --hard HEAD 2>/dev/null || true

    success "Code updated from git"

    # Restore stashed .env changes
    git stash pop 2>/dev/null || true

  else
    info "No git repo detected — pulling Docker images directly"
  fi

  # Pull new Docker images
  info "Pulling new Docker images..."
  local compose_dir
  compose_dir="$(dirname "$COMPOSE_FILE")"
  cd "$compose_dir"

  local ver="${TARGET_VERSION:-latest}"
  export RENGINE_VERSION="$ver"

  if $DOCKER_COMPOSE pull 2>/dev/null; then
    success "Docker images pulled: v$ver"
  else
    warn "Docker image pull failed — will attempt to build locally"
    if [[ -f "$compose_dir/docker-compose.build.yml" ]]; then
      info "Building from source..."
      $DOCKER_COMPOSE \
        -f "$COMPOSE_FILE" \
        -f "$compose_dir/docker-compose.build.yml" \
        build --no-cache 2>/dev/null \
        && success "Local build complete" \
        || warn "Build failed — will try with existing images"
    fi
  fi
}

# ─── Update .env ──────────────────────────────────────────────────────────────
update_env() {
  step "Validating .env configuration"

  local env_file="$INSTALL_DIR/.env"
  local env_dist="$INSTALL_DIR/.env-dist"

  if [[ ! -f "$env_file" ]]; then
    if [[ -f "$env_dist" ]]; then
      warn ".env not found — copying from .env-dist"
      cp "$env_dist" "$env_file"
    else
      warn ".env not found and no .env-dist available"
      return
    fi
  fi

  # Check if RENGINE_VERSION key exists, if not add it
  if ! grep -q "^RENGINE_VERSION=" "$env_file" 2>/dev/null; then
    echo "" >> "$env_file"
    echo "# reNgine version" >> "$env_file"
    echo "RENGINE_VERSION=${TARGET_VERSION:-latest}" >> "$env_file"
    info "Added RENGINE_VERSION to .env"
  else
    # Update version in .env
    sed -i "s|^RENGINE_VERSION=.*|RENGINE_VERSION=${TARGET_VERSION:-latest}|" "$env_file"
    info "Updated RENGINE_VERSION=${TARGET_VERSION:-latest} in .env"
  fi

  # Merge any new keys from .env-dist that are missing in .env
  if [[ -f "$env_dist" ]]; then
    info "Merging new keys from .env-dist..."
    local added=0
    while IFS= read -r line; do
      # Skip comments and empty lines
      [[ "$line" =~ ^#.*$ ]] && continue
      [[ -z "${line// }" ]] && continue

      local key
      key=$(echo "$line" | cut -d= -f1)
      if ! grep -q "^${key}=" "$env_file" 2>/dev/null; then
        echo "" >> "$env_file"
        echo "# Added by update.sh" >> "$env_file"
        echo "$line" >> "$env_file"
        info "  + New key added: $key"
        ((added++))
      fi
    done < "$env_dist"
    [[ $added -gt 0 ]] && success "$added new key(s) merged from .env-dist" \
      || info "No new keys needed"
  fi

  success ".env validated"
}

# ─── SSL certificates check ───────────────────────────────────────────────────
check_ssl_certs() {
  step "Checking SSL certificates"

  local certs_dir="$INSTALL_DIR/docker/secrets/certs"
  local required_certs=(
    "rengine.pem"
    "rengine_rsa.key"
    "rengine_chain.pem"
  )

  local missing=false
  for cert in "${required_certs[@]}"; do
    if [[ ! -f "$certs_dir/$cert" ]]; then
      warn "Missing certificate: $certs_dir/$cert"
      missing=true
    fi
  done

  if [[ "$missing" == "true" ]]; then
    info "Regenerating self-signed SSL certificates..."
    mkdir -p "$certs_dir"

    local domain="${DOMAIN_NAME:-rengine-ng.example.com}"
    local country="${COUNTRY_CODE:-US}"
    local state="${STATE:-Georgia}"
    local city="${CITY:-Atlanta}"
    local org="${COMPANY:-reNgine-ng}"
    local auth="${AUTHORITY_NAME:-reNgine-ng}"
    local auth_pass="${AUTHORITY_PASSWORD:-changeme}"

    if command -v openssl &>/dev/null; then
      # Generate CA key + cert
      openssl genrsa -out "$certs_dir/ca.key" 4096 2>/dev/null
      openssl req -new -x509 -days 3650 -key "$certs_dir/ca.key" \
        -out "$certs_dir/rengine_chain.pem" \
        -subj "/C=$country/ST=$state/L=$city/O=$org/CN=$auth CA" \
        2>/dev/null

      # Generate server key + CSR
      openssl genrsa -out "$certs_dir/rengine_rsa.key" 4096 2>/dev/null
      openssl req -new -key "$certs_dir/rengine_rsa.key" \
        -out "$certs_dir/rengine.csr" \
        -subj "/C=$country/ST=$state/L=$city/O=$org/CN=$domain" \
        2>/dev/null

      # Sign cert with CA
      openssl x509 -req -days 3650 \
        -in "$certs_dir/rengine.csr" \
        -CA "$certs_dir/rengine_chain.pem" \
        -CAkey "$certs_dir/ca.key" \
        -CAcreateserial \
        -out "$certs_dir/rengine.pem" \
        2>/dev/null

      rm -f "$certs_dir/rengine.csr" "$certs_dir/ca.srl"
      chmod 600 "$certs_dir"/*.key 2>/dev/null || true
      success "SSL certificates regenerated"
    else
      # Run the certs container
      local compose_dir
      compose_dir="$(dirname "$COMPOSE_FILE")"
      cd "$compose_dir"
      if grep -q "certs:" "$COMPOSE_FILE" 2>/dev/null || \
         [[ -f "$compose_dir/docker-compose.setup.yml" ]]; then
        $DOCKER_COMPOSE -f "$compose_dir/docker-compose.setup.yml" run --rm certs 2>/dev/null \
          && success "SSL certificates generated via Docker" \
          || warn "Could not generate SSL certs — proxy may not start"
      else
        warn "openssl not available and no certs service found"
      fi
    fi
  else
    # Check certificate expiry
    local cert="$certs_dir/rengine.pem"
    if command -v openssl &>/dev/null; then
      local expiry
      expiry=$(openssl x509 -enddate -noout -in "$cert" 2>/dev/null \
        | cut -d= -f2 || echo "unknown")
      info "SSL cert expires: $expiry"

      local days_left
      days_left=$(openssl x509 -checkend 0 -noout -in "$cert" 2>/dev/null \
        && echo "valid" || echo "EXPIRED")
      if [[ "$days_left" == "EXPIRED" ]]; then
        warn "SSL certificate has EXPIRED! Regenerating..."
        rm -f "$certs_dir"/*.pem "$certs_dir"/*.key 2>/dev/null || true
        check_ssl_certs  # recurse once
      else
        success "SSL certificates valid"
      fi
    else
      success "SSL certificates present"
    fi
  fi
}

# ─── Database migration ───────────────────────────────────────────────────────
run_db_migrations() {
  step "Running database migrations"

  local compose_dir
  compose_dir="$(dirname "$COMPOSE_FILE")"
  cd "$compose_dir"

  # Wait for DB to be healthy
  info "Waiting for database to be healthy..."
  local retries=30
  local pg_healthy=false
  for (( i=0; i<retries; i++ )); do
    local pg_container
    pg_container=$(docker ps --filter "name=rengine-db" --format "{{.Names}}" | head -1 || true)
    if [[ -n "$pg_container" ]]; then
      if docker exec "$pg_container" \
          pg_isready -U "${POSTGRES_USER:-rengine}" -d "${POSTGRES_DB:-rengine}" \
          &>/dev/null; then
        pg_healthy=true
        break
      fi
    fi
    sleep 3
    printf "."
  done
  echo ""

  if [[ "$pg_healthy" == "false" ]]; then
    warn "Database not ready after ${retries} retries — migrations will run inside containers"
    return
  fi

  success "Database is healthy"

  # Run migrations via the web container (once it's up)
  # Migrations are also run by entrypoint.sh automatically on container start
  info "Migrations will be applied automatically by container entrypoints"
  info "  web container:    makemigrations + migrate + collectstatic"
  info "  celery container: migrate + loaddefaultengines + loaddata fixtures"
}

# ─── Start services ───────────────────────────────────────────────────────────
start_services() {
  step "Starting reNgine-ng services"

  local compose_dir
  compose_dir="$(dirname "$COMPOSE_FILE")"
  cd "$compose_dir"

  local ver="${TARGET_VERSION:-latest}"
  export RENGINE_VERSION="$ver"

  info "Starting services (RENGINE_VERSION=$ver)..."
  $DOCKER_COMPOSE up -d 2>/dev/null \
    && success "Services started" \
    || error "Failed to start services — check: $DOCKER_COMPOSE logs"
}

# ─── Health check ─────────────────────────────────────────────────────────────
health_check() {
  step "Running health checks"

  local compose_dir
  compose_dir="$(dirname "$COMPOSE_FILE")"
  cd "$compose_dir"

  local all_healthy=true

  # Check each service
  local services=("rengine-db-1" "rengine-redis-1" "rengine-celery-1" "rengine-web-1" "rengine-proxy-1")
  for svc in "${services[@]}"; do
    local state
    state=$(docker inspect --format='{{.State.Status}}' "$svc" 2>/dev/null || echo "not found")
    if [[ "$state" == "running" ]]; then
      success "$svc: running"
    else
      warn "$svc: $state"
      all_healthy=false
    fi
  done

  # Wait for web to accept connections
  info "Waiting for web service on port 8082..."
  local web_ready=false
  for i in {1..20}; do
    if curl -sf -k --max-time 5 "https://localhost:8082" &>/dev/null || \
       curl -sf --max-time 5 "http://localhost:8082" &>/dev/null; then
      web_ready=true
      break
    fi
    sleep 5
    printf "."
  done
  echo ""

  if [[ "$web_ready" == "true" ]]; then
    success "Web service is responding on port 8082"
  else
    warn "Web service is not yet responding — it may still be starting"
    info "Tip: watch logs with: docker compose -f $COMPOSE_FILE logs -f web"
  fi

  echo ""
  info "Container status:"
  docker ps --filter "name=rengine" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || true
}

# ─── Post-update tasks ────────────────────────────────────────────────────────
post_update_tasks() {
  step "Running post-update tasks"

  # Update version file if changed
  local new_ver_file="$INSTALL_DIR/web/reNgine/version.txt"
  if [[ -f "$new_ver_file" ]] && [[ "$TARGET_VERSION" != "latest" ]]; then
    local detected
    detected=$(cat "$new_ver_file" | tr -d '[:space:]')
    info "Version file reports: v$detected"
  fi

  # Remove dangling images to free space
  info "Cleaning up unused Docker images..."
  docker image prune -f --filter "label=org.opencontainers.image.title=rengine" 2>/dev/null || true
  docker image prune -f 2>/dev/null || true
  success "Docker cleanup done"

  # Show disk usage
  info "Docker disk usage:"
  docker system df 2>/dev/null || true
}

# ─── Show final summary ───────────────────────────────────────────────────────
show_summary() {
  step "Update Summary"

  local new_version
  local ver_file="$INSTALL_DIR/web/reNgine/version.txt"
  if [[ -f "$ver_file" ]]; then
    new_version=$(cat "$ver_file" | tr -d '[:space:]')
  else
    new_version="$TARGET_VERSION"
  fi

  local access_ip
  access_ip=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "your-server-ip")

  cat << EOF

${GREEN}${BOLD}╔══════════════════════════════════════════════════════╗
║            reNgine-ng Update Complete!               ║
╚══════════════════════════════════════════════════════╝${RESET}

  Previous version : ${YELLOW}v${CURRENT_VERSION}${RESET}
  Current version  : ${GREEN}v${new_version}${RESET}
  Install directory: ${INSTALL_DIR}

${BOLD}Access URLs:${RESET}
  Web UI  : ${CYAN}https://${access_ip}${RESET}       (port 443)
  Alt port: ${CYAN}https://${access_ip}:8082${RESET}

${BOLD}Credentials:${RESET}  (unchanged — see ${INSTALL_DIR}/.env)
  Username: ${DJANGO_SUPERUSER_USERNAME:-rengine}

${BOLD}Management:${RESET}
  View logs   : docker compose -f ${COMPOSE_FILE} logs -f
  Stop        : bash manage.sh stop
  Restart     : bash manage.sh restart
  Full status : bash manage.sh status

${BOLD}Backup stored at:${RESET}  ${BACKUP_DIR:-none}
${BOLD}Update log:${RESET}        ${LOG_FILE}

EOF
  success "Update completed successfully!"
}

# ─── Main flow ────────────────────────────────────────────────────────────────
main() {
  check_prerequisites

  detect_install_dir
  detect_compose_file
  load_env
  get_current_version
  get_latest_version
  check_version_change

  # Handle special modes
  if [[ "$ROLLBACK" == "true" ]]; then
    do_rollback
  fi

  # Show plan
  step "Update Plan"
  info "Installation : $INSTALL_DIR"
  info "Compose file : $COMPOSE_FILE"
  info "From version : v$CURRENT_VERSION"
  info "To version   : v$TARGET_VERSION"
  [[ "$SKIP_BACKUP" == "false" ]] && info "Backup dir   : $BACKUP_BASE"

  if [[ "$BACKUP_ONLY" == "false" ]]; then
    if ! confirm "Proceed with update?"; then
      info "Update cancelled by user."
      exit 0
    fi
  fi

  # Execute steps
  create_backup

  if [[ "$BACKUP_ONLY" == "true" ]]; then
    success "Backup-only mode — stopping here."
    info "Backup location: $BACKUP_DIR"
    exit 0
  fi

  stop_services
  pull_code
  update_env
  check_ssl_certs
  start_services
  run_db_migrations
  health_check
  post_update_tasks
  show_summary
}

main "$@"
