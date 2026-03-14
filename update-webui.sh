#!/usr/bin/env bash
# =============================================================================
#  reNgine-ng  —  Web UI Update Script
#  Repo    : https://github.com/pt-zenity/Renginev3
#  Purpose : Update Web UI files only (templates, static CSS/JS, collectstatic)
#            WITHOUT touching the database, migrations, Docker, or system deps.
#
#  Safe to run:  ✅ production / ✅ dev / ✅ Docker / ✅ bare-metal
#  No git remote required — downloads directly via GitHub archive (tarball)
#
#  Usage   : bash update-webui.sh [OPTIONS]
#
#  Options :
#    --dir  <path>    Path to rengine-ng installation  (auto-detect if omitted)
#    --branch <name>  Git branch to pull from           (default: main)
#    --no-pull        Skip download, just re-run collectstatic + restart
#    --no-restart     Skip web server restart
#    --yes  | -y      Non-interactive, assume yes to all prompts
#    --rollback       Rollback to the most recent backup
#    -h | --help      Show this help
#
#  What this script updates:
#    • web/templates/         — Django HTML templates
#    • web/static/custom/     — Custom CSS & JS  (rengine-pro.css, custom.js …)
#    • web/static/assets/     — Bundled vendor assets  (Bootstrap, icons …)
#    • python manage.py collectstatic
#    • Restarts web server (PM2 / Gunicorn / Docker — auto-detected)
#
#  What this script does NOT touch:
#    ✗  Database / migrations
#    ✗  Python packages / pip
#    ✗  Docker images
#    ✗  Celery / Redis workers
#    ✗  System packages / .env files
# =============================================================================

set -euo pipefail
IFS=$'\n\t'

# ─── Colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m';  GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; MAGENTA='\033[0;35m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[ OK ]${RESET}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERR ]${RESET}  $*" >&2; exit 1; }
skipped() { echo -e "${YELLOW}[SKIP]${RESET}  $*"; }
step()    {
  echo -e "\n${BOLD}${CYAN}══════════════════════════════════════════════${RESET}"
  echo -e "${BOLD}  $*${RESET}"
  echo -e "${BOLD}${CYAN}══════════════════════════════════════════════${RESET}"
}

# ─── Banner ───────────────────────────────────────────────────────────────────
echo -e "${BOLD}${CYAN}"
cat << 'BANNER'

  __        __   _     _   _ ___   _   _ ____  ____    _  _____ _____
  \ \      / /__| |__ | | | |_ _| | | | |  _ \|  _ \  / \|_   _| ____|
   \ \ /\ / / _ \ '_ \| | | || |  | | | | |_) | | | |/ _ \ | | |  _|
    \ V  V /  __/ |_) | |_| || |  | |_| |  __/| |_| / ___ \| | | |___
     \_/\_/ \___|_.__/ \___/|___|  \___/|_|   |____/_/   \_\_| |_____|

         reNgine-ng  —  Web UI Only Update
         github.com/pt-zenity/Renginev3
BANNER
echo -e "${RESET}"

# ─── Defaults ─────────────────────────────────────────────────────────────────
INSTALL_DIR=""
BRANCH="main"
DO_PULL=true
DO_RESTART=true
DO_ROLLBACK=false
YES=false
REPO_OWNER="pt-zenity"
REPO_NAME="Renginev3"
REPO_URL="https://github.com/${REPO_OWNER}/${REPO_NAME}"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

# UI paths inside the repo that will be updated
UI_PATHS=(
  "web/templates"
  "web/static/custom"
  "web/static/assets"
)

# ─── Argument parsing ─────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)        INSTALL_DIR="$2"; shift 2 ;;
    --branch)     BRANCH="$2";      shift 2 ;;
    --no-pull)    DO_PULL=false;    shift   ;;
    --no-restart) DO_RESTART=false; shift   ;;
    --rollback)   DO_ROLLBACK=true; shift   ;;
    --yes|-y)     YES=true;         shift   ;;
    -h|--help)
      grep '^#  ' "$0" | cut -c4-
      exit 0
      ;;
    *) warn "Unknown option: $1 (ignored)"; shift ;;
  esac
done

# ─── Helpers ──────────────────────────────────────────────────────────────────
confirm() {
  [[ "$YES" == true ]] && return 0
  echo -en "${MAGENTA}[ASK ]${RESET}  $* [Y/n]: "
  read -r ans
  [[ -z "$ans" || "$ans" =~ ^[Yy] ]]
}

cmd_exists() { command -v "$1" &>/dev/null; }

# Download helper — tries curl then wget
download() {
  local url="$1" dest="$2"
  if cmd_exists curl; then
    curl -fsSL "$url" -o "$dest"
  elif cmd_exists wget; then
    wget -qO "$dest" "$url"
  else
    error "Neither curl nor wget found. Install one and retry."
  fi
}

# ─── Auto-detect installation directory ──────────────────────────────────────
detect_install_dir() {
  # 1. current working directory
  [[ -f "$(pwd)/web/manage.py" ]] && { echo "$(pwd)"; return; }

  # 2. well-known paths
  local candidates=(
    "$HOME/rengine"
    "$HOME/rengine-ng"
    "$HOME/Renginev3"
    "$HOME/webapp"
    "/opt/rengine"
    "/opt/rengine-ng"
    "/var/www/rengine"
  )
  for d in "${candidates[@]}"; do
    [[ -f "$d/web/manage.py" ]] && { echo "$d"; return; }
  done

  # 3. search common roots
  local found
  found=$(find /opt /home /root /var/www -maxdepth 5 \
            -name "manage.py" -path "*/web/manage.py" \
            2>/dev/null | head -1)
  [[ -n "$found" ]] && { dirname "$(dirname "$found")"; return; }

  echo ""
}

# ─── Detect running environment ───────────────────────────────────────────────
detect_env() {
  if cmd_exists docker && docker ps 2>/dev/null | grep -qE "rengine"; then
    echo "docker"
  elif cmd_exists pm2 && pm2 list --no-color 2>/dev/null | grep -qE "rengine|webapp"; then
    echo "pm2"
  elif pgrep -fa "gunicorn" 2>/dev/null | grep -qE "rengine|wsgi"; then
    echo "gunicorn"
  else
    echo "dev"
  fi
}

# ─── Find Docker web container name (for restart only) ───────────────────────
find_docker_container() {
  # Returns the name of the running rengine web/nginx container (for restart).
  docker ps --format '{{.Names}}' 2>/dev/null \
    | grep -Ei "(rengine.*(web|nginx)|rengine-web)" \
    | head -1 || true
}

# ─── Find Docker Django/app container (has Python + manage.py) ───────────────
find_django_container() {
  # Strategy: iterate ALL rengine containers, test for manage.py existence.
  # We do NOT probe `python` via PATH (it may not be in $PATH inside container).
  # Instead we check for manage.py file which is a reliable Django indicator.
  local candidates
  candidates=$(docker ps --format '{{.Names}}' 2>/dev/null \
    | grep -Ei "rengine" 2>/dev/null || true)

  [[ -z "$candidates" ]] && { echo ""; return; }

  local cname
  while IFS= read -r cname; do
    [[ -z "$cname" ]] && continue
    # Test 1: check if manage.py exists in known locations
    for D in /home/rengine/rengine /home/rengine/web /usr/src/app /app /rengine/web; do
      if docker exec "$cname" test -f "$D/manage.py" 2>/dev/null; then
        echo "$cname"
        return
      fi
    done
  done <<< "$candidates"

  # Fallback: return any rengine container that is NOT nginx/redis/postgres
  while IFS= read -r cname; do
    [[ -z "$cname" ]] && continue
    echo "$cname" | grep -vEi "nginx|redis|postgres|db|rabbitmq|flower" && return
  done <<< "$candidates"

  echo ""
}

# ─── Find Python binary inside a container ───────────────────────────────────
find_python_in_container() {
  local cname="$1"
  # Try common Python paths in order — handles venv, system, custom installs
  for py in \
    "/usr/local/bin/python3" \
    "/usr/bin/python3" \
    "/home/rengine/.venv/bin/python3" \
    "/venv/bin/python3" \
    "/opt/venv/bin/python3" \
    "/usr/local/bin/python" \
    "/usr/bin/python"; do
    if docker exec "$cname" test -x "$py" 2>/dev/null; then
      echo "$py"
      return
    fi
  done
  # Last resort: ask the container to find it
  local found
  found=$(docker exec "$cname" sh -c 'command -v python3 2>/dev/null || command -v python 2>/dev/null || find /usr /home /opt -name "python3" -type f 2>/dev/null | head -1' 2>/dev/null || true)
  echo "${found:-}"
}

# ─── Find Python interpreter ──────────────────────────────────────────────────
find_python() {
  local web_dir="$1"
  for py in \
    "$web_dir/../venv/bin/python3" \
    "$web_dir/../../venv/bin/python3" \
    "/opt/rengine/venv/bin/python3" \
    "$(command -v python3 2>/dev/null || true)"; do
    [[ -x "$py" ]] && { echo "$py"; return; }
  done
  echo "python3"
}

# ─── Find Django settings module ──────────────────────────────────────────────
find_settings() {
  local web_dir="$1"
  [[ -f "$web_dir/reNgine/settings_local.py" ]] && { echo "reNgine.settings_local"; return; }
  [[ -f "$web_dir/reNgine/settings.py"       ]] && { echo "reNgine.settings";       return; }
  echo ""
}

# ══════════════════════════════════════════════════════════════════════════════
#  STEP 0 — Locate installation
# ══════════════════════════════════════════════════════════════════════════════
step "0/5  Locating reNgine-ng installation"

[[ -z "$INSTALL_DIR" ]] && INSTALL_DIR="$(detect_install_dir)"

[[ -z "$INSTALL_DIR" || ! -f "$INSTALL_DIR/web/manage.py" ]] && \
  error "Cannot find reNgine-ng installation.
  Run with:  --dir /path/to/rengine-ng
  Expected:  <dir>/web/manage.py"

WEB_DIR="$INSTALL_DIR/web"
TEMPLATES_DIR="$WEB_DIR/templates"
STATIC_CUSTOM_DIR="$WEB_DIR/static/custom"
BACKUP_ROOT="$INSTALL_DIR/.webui-backups"
BACKUP_DIR="$BACKUP_ROOT/$TIMESTAMP"

ENV_TYPE="$(detect_env)"
PYTHON="$(find_python "$WEB_DIR")"
DJANGO_SETTINGS="$(find_settings "$WEB_DIR")"

success "Installation : ${BOLD}$INSTALL_DIR${RESET}"
info    "Web dir      : $WEB_DIR"
info    "Environment  : ${BOLD}$ENV_TYPE${RESET}"
info    "Python       : $PYTHON"
info    "Settings     : ${DJANGO_SETTINGS:-not found}"
info    "Branch       : $BRANCH"
echo ""

# ══════════════════════════════════════════════════════════════════════════════
#  ROLLBACK MODE
# ══════════════════════════════════════════════════════════════════════════════
if [[ "$DO_ROLLBACK" == true ]]; then
  step "ROLLBACK  Restoring previous Web UI"

  # Find the most recent backup
  LATEST_BACKUP=$(ls -1dt "$BACKUP_ROOT"/[0-9]* 2>/dev/null | head -1 || true)
  [[ -z "$LATEST_BACKUP" ]] && error "No backups found in $BACKUP_ROOT"

  info "Restoring from: $LATEST_BACKUP"
  confirm "Rollback Web UI to backup from $(basename "$LATEST_BACKUP")?" || { echo "Aborted."; exit 0; }

  [[ -d "$LATEST_BACKUP/templates" ]] && {
    rm -rf "$TEMPLATES_DIR"
    cp -r  "$LATEST_BACKUP/templates" "$TEMPLATES_DIR"
    success "Templates restored"
  }
  [[ -d "$LATEST_BACKUP/static_custom" ]] && {
    rm -rf "$STATIC_CUSTOM_DIR"
    cp -r  "$LATEST_BACKUP/static_custom" "$STATIC_CUSTOM_DIR"
    success "Custom static restored"
  }

  success "Rollback complete — restart your web server to apply."
  exit 0
fi

# ══════════════════════════════════════════════════════════════════════════════
#  Normal update flow
# ══════════════════════════════════════════════════════════════════════════════
confirm "Update Web UI in ${BOLD}$INSTALL_DIR${RESET}?" || { echo "Aborted."; exit 0; }

# ══════════════════════════════════════════════════════════════════════════════
#  STEP 1 — Backup
# ══════════════════════════════════════════════════════════════════════════════
step "1/5  Backing up current UI files"

mkdir -p "$BACKUP_DIR"

[[ -d "$TEMPLATES_DIR" ]] && {
  cp -r "$TEMPLATES_DIR" "$BACKUP_DIR/templates"
  success "Templates  → $BACKUP_DIR/templates"
}
[[ -d "$STATIC_CUSTOM_DIR" ]] && {
  cp -r "$STATIC_CUSTOM_DIR" "$BACKUP_DIR/static_custom"
  success "CSS/JS     → $BACKUP_DIR/static_custom"
}

info "Backup saved: $BACKUP_DIR"

# ══════════════════════════════════════════════════════════════════════════════
#  STEP 2 — Download & apply latest UI files from GitHub
# ══════════════════════════════════════════════════════════════════════════════
step "2/5  Downloading latest Web UI from GitHub"

if [[ "$DO_PULL" == false ]]; then
  skipped "Download skipped (--no-pull)"
else
  TARBALL_URL="${REPO_URL}/archive/refs/heads/${BRANCH}.tar.gz"
  TMPDIR_DL="$(mktemp -d)"
  TARBALL="$TMPDIR_DL/webui.tar.gz"
  EXTRACT_DIR="$TMPDIR_DL/repo"

  # Cleanup on exit
  trap 'rm -rf "$TMPDIR_DL"' EXIT

  info "Source : $TARBALL_URL"
  info "Saving to temp: $TARBALL"

  # Download
  download "$TARBALL_URL" "$TARBALL" \
    || error "Download failed. Check internet connection or try --no-pull."

  success "Download complete"

  # Extract
  mkdir -p "$EXTRACT_DIR"
  tar -xzf "$TARBALL" -C "$EXTRACT_DIR" --strip-components=1 \
    || error "Failed to extract tarball."

  success "Extracted to: $EXTRACT_DIR"

  # Copy only UI paths
  info "Applying UI files…"
  for rel_path in "${UI_PATHS[@]}"; do
    SRC="$EXTRACT_DIR/$rel_path"
    DEST="$INSTALL_DIR/$rel_path"

    if [[ -d "$SRC" ]]; then
      # Merge: overwrite existing files, keep any local-only files
      mkdir -p "$DEST"
      cp -r "$SRC/." "$DEST/"
      success "Updated : $rel_path"
    elif [[ -f "$SRC" ]]; then
      mkdir -p "$(dirname "$DEST")"
      cp "$SRC" "$DEST"
      success "Updated : $rel_path"
    else
      skipped "$rel_path — not found in downloaded archive"
    fi
  done

  # Cleanup temp (trap will handle it, but be explicit)
  rm -rf "$TMPDIR_DL"
  trap - EXIT
fi

# ══════════════════════════════════════════════════════════════════════════════
#  STEP 3 — collectstatic
#  Docker env  → run INSIDE the container (all Python deps live there)
#  Non-Docker  → run on host with detected Python
# ══════════════════════════════════════════════════════════════════════════════
step "3/5  Running collectstatic"

run_collectstatic() {
  local out
  out=$("$@" 2>&1) && {
    local summary
    summary=$(echo "$out" | grep -E "static file|copied|unmodified" | tail -1 || true)
    success "collectstatic done${summary:+ — $summary}"
    return 0
  } || {
    warn "collectstatic error (non-fatal):"
    echo "$out" | tail -10 | sed 's/^/    /'
    return 1
  }
}

if [[ "$ENV_TYPE" == "docker" ]]; then
  # ── Docker: find the container that has manage.py, then run collectstatic ────
  info "Scanning rengine containers for manage.py…"
  DJANGO_CTR="$(find_django_container)"

  if [[ -z "$DJANGO_CTR" ]]; then
    warn "No Django container found — skipping collectstatic (non-fatal)"
    warn "Templates & static CSS/JS are already updated on the host volume."
    warn "Run manually: docker exec <container> python manage.py collectstatic --noinput"
  else
    info "Found Django container: ${BOLD}$DJANGO_CTR${RESET}"

    # Find Python binary inside the container
    CONTAINER_PY="$(find_python_in_container "$DJANGO_CTR")"
    if [[ -z "$CONTAINER_PY" ]]; then
      warn "Python binary not found inside $DJANGO_CTR — skipping collectstatic"
      warn "Run manually: docker exec $DJANGO_CTR <python_path> manage.py collectstatic --noinput"
    else
      info "Python binary in container: $CONTAINER_PY"
      info "Running collectstatic inside $DJANGO_CTR …"

      # Shell script that runs INSIDE the container:
      #   1. Locate manage.py
      #   2. Set DJANGO_SETTINGS_MODULE
      #   3. Run collectstatic, show summary
      COLLECT_CMD="
set -e
# ── locate manage.py ──────────────────────────────────────────
MANAGE_DIR=''
for D in /home/rengine/rengine /home/rengine/web /usr/src/app /app /rengine/web; do
  if [ -f \"\$D/manage.py\" ]; then MANAGE_DIR=\"\$D\"; break; fi
done
if [ -z \"\$MANAGE_DIR\" ]; then
  echo '[ERR] manage.py not found'; exit 1
fi
cd \"\$MANAGE_DIR\"
echo \"[INFO] Working dir: \$MANAGE_DIR\"

# ── settings module ───────────────────────────────────────────
if [ -f 'reNgine/settings_local.py' ]; then
  export DJANGO_SETTINGS_MODULE='reNgine.settings_local'
elif [ -f 'reNgine/settings.py' ]; then
  export DJANGO_SETTINGS_MODULE='reNgine.settings'
fi
echo \"[INFO] Settings: \$DJANGO_SETTINGS_MODULE\"

# ── run collectstatic ─────────────────────────────────────────
\"$CONTAINER_PY\" manage.py collectstatic --noinput 2>&1 \\
  | grep -E 'static file|copied|unmodified|[Ee]rror|Traceback' \\
  | tail -5
echo '[DONE] collectstatic finished'
"
      if docker exec "$DJANGO_CTR" sh -c "$COLLECT_CMD"; then
        success "collectstatic done inside $DJANGO_CTR"
      else
        warn "collectstatic failed — templates updated, but static files may be stale"
        warn "Manual fix: docker exec $DJANGO_CTR $CONTAINER_PY manage.py collectstatic --noinput"
      fi
    fi
  fi

elif [[ -z "$DJANGO_SETTINGS" ]]; then
  # ── No settings found ────────────────────────────────────────────────────────
  warn "Django settings not found — skipping collectstatic"
  warn "Run manually: cd $WEB_DIR && python3 manage.py collectstatic --noinput"

else
  # ── Host Python (PM2 / bare-metal / dev) ─────────────────────────────────────
  cd "$WEB_DIR"
  info "Running collectstatic on host…"
  run_collectstatic \
    env DJANGO_SETTINGS_MODULE="$DJANGO_SETTINGS" \
    "$PYTHON" manage.py collectstatic --noinput
fi

# ══════════════════════════════════════════════════════════════════════════════
#  STEP 4 — Clear caches
# ══════════════════════════════════════════════════════════════════════════════
step "4/5  Clearing caches"

# Remove compiled template bytecode
find "$TEMPLATES_DIR" -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
success "__pycache__ cleared"

# Django file-based cache
DJANGO_CACHE_DIR="$INSTALL_DIR/.django_cache"
if [[ -d "$DJANGO_CACHE_DIR" ]]; then
  rm -rf "${DJANGO_CACHE_DIR:?}/"*
  success "Django file cache cleared"
fi

# Optional: flush Redis cache if CLEAR_CACHE=true env var is set
if [[ "${CLEAR_CACHE:-false}" == "true" ]] && cmd_exists redis-cli; then
  redis-cli FLUSHDB &>/dev/null \
    && success "Redis cache flushed" \
    || warn "Redis flush failed (non-fatal)"
fi

success "Cache cleanup done"

# ══════════════════════════════════════════════════════════════════════════════
#  STEP 5 — Restart web server
# ══════════════════════════════════════════════════════════════════════════════
step "5/5  Restarting web server"

if [[ "$DO_RESTART" == false ]]; then
  skipped "Restart skipped (--no-restart)"
  warn "Restart your web server manually to apply changes."
else
  case "$ENV_TYPE" in

    # ── Docker ──────────────────────────────────────────────────────────────
    docker)
      CONTAINER="$(find_docker_container)"

      if [[ -n "$CONTAINER" ]]; then
        info "Restarting container: $CONTAINER"
        docker restart "$CONTAINER" \
          && success "Container '$CONTAINER' restarted" \
          || warn "docker restart failed — try: docker restart $CONTAINER"
      else
        # Fallback: try docker-compose / docker compose
        info "No single container found — trying docker-compose…"
        COMPOSE_TRIED=false
        for COMPOSE_FILE in \
          "$INSTALL_DIR/docker/docker-compose.yml" \
          "$INSTALL_DIR/docker-compose.yml" \
          "$(pwd)/docker-compose.yml"; do
          if [[ -f "$COMPOSE_FILE" ]]; then
            COMPOSE_TRIED=true
            (docker compose -f "$COMPOSE_FILE" restart web 2>/dev/null \
              || docker-compose -f "$COMPOSE_FILE" restart web 2>/dev/null) \
              && { success "docker-compose web restarted via $COMPOSE_FILE"; break; } \
              || warn "docker-compose restart failed for $COMPOSE_FILE"
          fi
        done
        [[ "$COMPOSE_TRIED" == false ]] && \
          warn "No compose file found — restart the web container manually"
      fi
      ;;

    # ── PM2 ─────────────────────────────────────────────────────────────────
    pm2)
      PM2_NAME=$(pm2 list --no-color 2>/dev/null \
        | grep -oE "rengine-web|rengine[^ ]*|webapp" | head -1 || true)
      PM2_NAME="${PM2_NAME:-rengine-web}"
      info "PM2 restart: $PM2_NAME"
      pm2 restart "$PM2_NAME" \
        && success "PM2 '$PM2_NAME' restarted" \
        || warn "PM2 restart failed — try: pm2 restart $PM2_NAME"
      ;;

    # ── Gunicorn ────────────────────────────────────────────────────────────
    gunicorn)
      PID=$(pgrep -f "gunicorn" | head -1 || true)
      if [[ -n "$PID" ]]; then
        info "Sending HUP to gunicorn PID $PID (graceful reload)…"
        kill -HUP "$PID" \
          && success "Gunicorn gracefully reloaded" \
          || warn "HUP failed — try: kill -HUP $PID"
      else
        warn "Gunicorn process not found — restart manually"
      fi
      ;;

    # ── Dev / fallback ───────────────────────────────────────────────────────
    dev)
      if cmd_exists pm2 && pm2 list --no-color 2>/dev/null | grep -qE "rengine|webapp"; then
        PM2_NAME=$(pm2 list --no-color 2>/dev/null | grep -oE "rengine[^ ]*|webapp" | head -1)
        pm2 restart "${PM2_NAME:-rengine-web}" \
          && success "PM2 dev server restarted" \
          || warn "PM2 restart failed"
      else
        warn "Dev mode — Django runserver auto-reloads on file change."
        warn "If changes not visible, restart: cd $WEB_DIR && python3 manage.py runserver"
      fi
      ;;
  esac
fi

# ══════════════════════════════════════════════════════════════════════════════
#  Done
# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo -e "${BOLD}${GREEN}╔═══════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${GREEN}║   ✅  Web UI Update Complete!                         ║${RESET}"
echo -e "${BOLD}${GREEN}╚═══════════════════════════════════════════════════════╝${RESET}"
echo ""
echo -e "  ${BOLD}Files updated:${RESET}"
for p in "${UI_PATHS[@]}"; do echo "  • $p"; done
echo -e "  • staticfiles_collected/ (collectstatic)"
echo ""
echo -e "  ${BOLD}Backup saved:${RESET}"
echo -e "  ${CYAN}  $BACKUP_DIR${RESET}"
echo ""
echo -e "  ${BOLD}Rollback (if needed):${RESET}"
echo -e "  ${CYAN}  bash $(basename "$0") --rollback${RESET}"
echo ""
