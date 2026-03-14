#!/usr/bin/env bash
# =============================================================================
#  reNgine-ng  —  Web UI Update Script
#  Repo    : https://github.com/pt-zenity/Renginev3
#  Purpose : Update Web UI files only (templates, static CSS/JS, collectstatic)
#            WITHOUT touching the database, migrations, Docker, or system deps.
#
#  Safe to run:  ✅ production / ✅ dev / ✅ Docker / ✅ bare-metal
#
#  Usage   : bash update-webui.sh [OPTIONS]
#
#  Options :
#    --dir  <path>    Path to rengine-ng installation  (auto-detect if omitted)
#    --branch <name>  Git branch to pull from           (default: main)
#    --no-pull        Skip git pull  (use local files only, just re-apply)
#    --no-restart     Skip PM2 / Gunicorn / Django restart
#    --yes            Non-interactive, assume yes to all prompts
#    -h, --help       Show this help
#
#  What this script updates:
#    • web/templates/         — Django HTML templates
#    • web/static/custom/     — Custom CSS & JS  (rengine-pro.css, custom.js …)
#    • web/static/assets/     — Bundled vendor assets  (Bootstrap, icons …)
#    • python manage.py collectstatic  — Copies static files to staticfiles_collected/
#    • Restarts web server via PM2 (or gunicorn / Docker depending on setup)
#
#  What this script does NOT touch:
#    ✗  Database / migrations
#    ✗  Python packages / pip
#    ✗  Docker images
#    ✗  Celery / Redis workers
#    ✗  System packages
# =============================================================================

set -euo pipefail

# ─── Colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[ OK ]${RESET}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERR ]${RESET}  $*" >&2; exit 1; }
step()    { echo -e "\n${BOLD}${CYAN}══════════════════════════════════════════════${RESET}"
            echo -e "${BOLD}  $*${RESET}"
            echo -e "${BOLD}${CYAN}══════════════════════════════════════════════${RESET}"; }
ask()     { echo -e "${MAGENTA}[ASK ]${RESET}  $*"; }
skipped() { echo -e "${YELLOW}[SKIP]${RESET}  $*"; }

# ─── Banner ───────────────────────────────────────────────────────────────────
banner() {
cat << 'BANNER'

  __        __   _     _   _ ___   _   _ ____  ____    _  _____ _____
  \ \      / /__| |__ | | | |_ _| | | | |  _ \|  _ \  / \|_   _| ____|
   \ \ /\ / / _ \ '_ \| | | || |  | | | | |_) | | | |/ _ \ | | |  _|
    \ V  V /  __/ |_) | |_| || |  | |_| |  __/| |_| / ___ \| | | |___
     \_/\_/ \___|_.__/ \___/|___|  \___/|_|   |____/_/   \_\_| |_____|

         reNgine-ng  —  Web UI Only Update
         github.com/pt-zenity/Renginev3
BANNER
}

banner
echo ""

# ─── Defaults ─────────────────────────────────────────────────────────────────
INSTALL_DIR=""
BRANCH="main"
DO_PULL=true
DO_RESTART=true
YES=false
REPO_URL="https://github.com/pt-zenity/Renginev3.git"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

# ─── Argument parsing ─────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)      INSTALL_DIR="$2"; shift 2 ;;
    --branch)   BRANCH="$2";      shift 2 ;;
    --no-pull)  DO_PULL=false;    shift   ;;
    --no-restart) DO_RESTART=false; shift ;;
    --yes|-y)   YES=true;         shift   ;;
    -h|--help)
      grep '^#  ' "$0" | cut -c4-
      exit 0
      ;;
    *) warn "Unknown option: $1"; shift ;;
  esac
done

# ─── Helpers ──────────────────────────────────────────────────────────────────
confirm() {
  # confirm "message" → returns 0 (yes) or 1 (no)
  local msg="$1"
  if [[ "$YES" == true ]]; then return 0; fi
  ask "$msg [Y/n]: "
  read -r ans
  [[ -z "$ans" || "$ans" =~ ^[Yy] ]]
}

command_exists() { command -v "$1" &>/dev/null; }

# ─── Auto-detect installation directory ──────────────────────────────────────
detect_install_dir() {
  local candidates=(
    "/opt/rengine-ng"
    "/opt/rengine"
    "$HOME/rengine-ng"
    "$HOME/webapp"
    "$(pwd)"
  )

  # Check if current dir looks like the repo
  if [[ -f "$(pwd)/web/manage.py" ]]; then
    echo "$(pwd)"
    return
  fi

  for d in "${candidates[@]}"; do
    if [[ -f "$d/web/manage.py" ]]; then
      echo "$d"
      return
    fi
  done

  # Try to find via find command
  local found
  found=$(find /opt /home /root -maxdepth 4 -name "manage.py" -path "*/web/manage.py" 2>/dev/null | head -1)
  if [[ -n "$found" ]]; then
    dirname "$(dirname "$found")"
    return
  fi

  echo ""
}

# ─── Detect environment type ──────────────────────────────────────────────────
detect_env() {
  # Returns: docker | pm2 | gunicorn | dev
  if command_exists docker && docker ps 2>/dev/null | grep -q "rengine"; then
    echo "docker"
  elif command_exists pm2 && pm2 list 2>/dev/null | grep -q "rengine"; then
    echo "pm2"
  elif pgrep -f "gunicorn.*rengine\|uvicorn.*rengine" &>/dev/null; then
    echo "gunicorn"
  else
    echo "dev"
  fi
}

# ─── Find Python & Django manage.py ──────────────────────────────────────────
find_python() {
  local web_dir="$1"
  # Priority: venv > system python3
  for py in "$web_dir/../venv/bin/python3" \
            "$web_dir/../../venv/bin/python3" \
            "/opt/rengine/venv/bin/python3" \
            "$(command -v python3 2>/dev/null)"; do
    if [[ -x "$py" ]]; then
      echo "$py"
      return
    fi
  done
  echo "python3"
}

find_django_settings() {
  local web_dir="$1"
  # Check for local settings first, then production
  if [[ -f "$web_dir/reNgine/settings_local.py" ]]; then
    echo "reNgine.settings_local"
  elif [[ -f "$web_dir/reNgine/settings.py" ]]; then
    echo "reNgine.settings"
  else
    echo ""
  fi
}

# ─── Step 0: Resolve install dir ─────────────────────────────────────────────
step "0/5  Locating reNgine-ng installation"

if [[ -z "$INSTALL_DIR" ]]; then
  INSTALL_DIR="$(detect_install_dir)"
fi

if [[ -z "$INSTALL_DIR" || ! -f "$INSTALL_DIR/web/manage.py" ]]; then
  error "Could not find reNgine-ng installation.
  Please specify with: --dir /path/to/rengine-ng
  Expected structure:   <dir>/web/manage.py"
fi

WEB_DIR="$INSTALL_DIR/web"
TEMPLATES_DIR="$WEB_DIR/templates"
STATIC_CUSTOM_DIR="$WEB_DIR/static/custom"
STATIC_ASSETS_DIR="$WEB_DIR/static/assets"
STATICFILES_DIR="$WEB_DIR/staticfiles_collected"

success "Installation found: ${BOLD}$INSTALL_DIR${RESET}"
info    "Web directory     : $WEB_DIR"
info    "Templates         : $TEMPLATES_DIR"
info    "Custom static     : $STATIC_CUSTOM_DIR"

ENV_TYPE="$(detect_env)"
PYTHON="$(find_python "$WEB_DIR")"
DJANGO_SETTINGS="$(find_django_settings "$WEB_DIR")"

info "Environment       : ${BOLD}$ENV_TYPE${RESET}"
info "Python            : $PYTHON"
info "Django settings   : ${DJANGO_SETTINGS:-not found}"
echo ""

# Confirm before proceeding
if ! confirm "Update Web UI in ${BOLD}$INSTALL_DIR${RESET}?"; then
  echo "Aborted."
  exit 0
fi

# ─── Step 1: Backup current UI files ─────────────────────────────────────────
step "1/5  Backing up current UI files"

BACKUP_DIR="$INSTALL_DIR/.webui-backups/$TIMESTAMP"
mkdir -p "$BACKUP_DIR"

# Backup templates
if [[ -d "$TEMPLATES_DIR" ]]; then
  cp -r "$TEMPLATES_DIR" "$BACKUP_DIR/templates"
  success "Templates backed up → $BACKUP_DIR/templates"
else
  warn "No templates directory found, skipping backup"
fi

# Backup custom static
if [[ -d "$STATIC_CUSTOM_DIR" ]]; then
  cp -r "$STATIC_CUSTOM_DIR" "$BACKUP_DIR/static_custom"
  success "Custom static backed up → $BACKUP_DIR/static_custom"
fi

info "Backup location: $BACKUP_DIR"

# ─── Step 2: Pull latest code from GitHub ─────────────────────────────────────
step "2/5  Pulling latest Web UI from GitHub"

if [[ "$DO_PULL" == false ]]; then
  skipped "Git pull skipped (--no-pull flag)"
else
  cd "$INSTALL_DIR"

  # Ensure git repo exists
  if [[ ! -d ".git" ]]; then
    warn "No .git directory found. Initialising git remote…"
    git init
    git remote add origin "$REPO_URL" 2>/dev/null || git remote set-url origin "$REPO_URL"
  fi

  # Check current remote
  CURRENT_REMOTE="$(git remote get-url origin 2>/dev/null || echo '')"
  info "Remote: $CURRENT_REMOTE"
  info "Branch: $BRANCH"

  # Stash any local changes
  if ! git diff --quiet 2>/dev/null; then
    warn "Uncommitted local changes detected — stashing…"
    git stash push -m "webui-update-$TIMESTAMP" 2>/dev/null || true
  fi

  # Fetch & pull
  info "Fetching from origin…"
  git fetch origin "$BRANCH" 2>&1 | sed 's/^/  /'

  # Sparse pull: only web UI files to avoid overwriting DB/config/etc.
  # Use git checkout to update only UI-related paths
  UI_PATHS=(
    "web/templates"
    "web/static/custom"
    "web/static/assets"
  )

  info "Checking out UI files from origin/$BRANCH …"
  for path in "${UI_PATHS[@]}"; do
    if git ls-tree -d "origin/$BRANCH" "$path" &>/dev/null 2>&1 || \
       git ls-tree "origin/$BRANCH" "$path" &>/dev/null 2>&1; then
      git checkout "origin/$BRANCH" -- "$path" 2>/dev/null && \
        success "Updated: $path" || warn "Could not update: $path (may not exist on remote)"
    else
      skipped "$path not found on origin/$BRANCH"
    fi
  done
fi

# ─── Step 3: Run collectstatic ────────────────────────────────────────────────
step "3/5  Running collectstatic"

if [[ -z "$DJANGO_SETTINGS" ]]; then
  warn "Django settings module not found — skipping collectstatic"
  warn "You may need to run manually:"
  warn "  cd $WEB_DIR && python3 manage.py collectstatic --noinput"
else
  cd "$WEB_DIR"

  info "Running: python3 manage.py collectstatic --noinput"
  COLLECTSTATIC_OUTPUT=$(
    DJANGO_SETTINGS_MODULE="$DJANGO_SETTINGS" \
    "$PYTHON" manage.py collectstatic --noinput 2>&1
  ) && {
    # Extract summary line
    SUMMARY=$(echo "$COLLECTSTATIC_OUTPUT" | grep -E "static file|copied|unmodified" | tail -1 || true)
    success "collectstatic complete${SUMMARY:+ — $SUMMARY}"
  } || {
    warn "collectstatic encountered an error:"
    echo "$COLLECTSTATIC_OUTPUT" | tail -10 | sed 's/^/  /'
    warn "Web server will still be restarted — old static files may be served until fixed"
  }
fi

# ─── Step 4: Clear browser/Django caches ──────────────────────────────────────
step "4/5  Clearing caches"

cd "$WEB_DIR"

# Clear __pycache__ in templates/static area (forces Django template reload)
find "$TEMPLATES_DIR" -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
success "Template __pycache__ cleared"

# Clear Django's cached templates (if file-based cache exists)
CACHE_DIR="$INSTALL_DIR/.django_cache"
if [[ -d "$CACHE_DIR" ]]; then
  rm -rf "${CACHE_DIR:?}/"*
  success "Django file cache cleared: $CACHE_DIR"
fi

# If memcached/redis is available and CLEAR_CACHE env set
if [[ "${CLEAR_CACHE:-}" == "true" ]]; then
  if command_exists redis-cli; then
    redis-cli FLUSHDB &>/dev/null && success "Redis cache flushed" || warn "Redis flush failed"
  fi
fi

success "Cache cleanup done"

# ─── Step 5: Restart web server ───────────────────────────────────────────────
step "5/5  Restarting web server"

if [[ "$DO_RESTART" == false ]]; then
  skipped "Restart skipped (--no-restart flag)"
  warn "Remember to restart the web server manually to apply changes!"
else
  case "$ENV_TYPE" in

    docker)
      # Find the Django/web container
      CONTAINER=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -E "rengine.*(web|django|app)|web.*rengine" | head -1)
      if [[ -n "$CONTAINER" ]]; then
        info "Restarting Docker container: $CONTAINER"
        docker restart "$CONTAINER"
        success "Container '$CONTAINER' restarted"
      else
        warn "Could not find rengine web container — trying docker-compose…"
        if command_exists docker-compose; then
          COMPOSE_FILE="$INSTALL_DIR/docker/docker-compose.yml"
          [[ -f "$COMPOSE_FILE" ]] || COMPOSE_FILE="$INSTALL_DIR/docker-compose.yml"
          [[ -f "$COMPOSE_FILE" ]] || COMPOSE_FILE="docker-compose.yml"
          docker-compose -f "$COMPOSE_FILE" restart web 2>/dev/null && \
            success "docker-compose web restarted" || \
            warn "docker-compose restart failed — please restart manually"
        fi
      fi
      ;;

    pm2)
      # Find the PM2 process name
      PM2_NAME=$(pm2 list --no-color 2>/dev/null | grep -oE "rengine[^ ]*|webapp" | head -1)
      PM2_NAME="${PM2_NAME:-rengine-web}"
      info "Restarting PM2 process: $PM2_NAME"
      pm2 restart "$PM2_NAME" 2>/dev/null && \
        success "PM2 '$PM2_NAME' restarted" || \
        warn "PM2 restart failed — try: pm2 restart $PM2_NAME"
      ;;

    gunicorn)
      PID=$(pgrep -f "gunicorn.*rengine" | head -1)
      if [[ -n "$PID" ]]; then
        info "Sending HUP signal to gunicorn (PID $PID) for graceful reload…"
        kill -HUP "$PID" && success "Gunicorn reloaded (graceful)" || \
          warn "HUP signal failed — try: kill -HUP $PID"
      fi
      ;;

    dev)
      # Django runserver auto-reloads on file change, but if PM2 is running it
      if command_exists pm2 && pm2 list --no-color 2>/dev/null | grep -q "rengine\|webapp"; then
        PM2_NAME=$(pm2 list --no-color 2>/dev/null | grep -oE "rengine[^ ]*|webapp" | head -1)
        pm2 restart "${PM2_NAME:-rengine-web}" 2>/dev/null && \
          success "PM2 dev server restarted" || \
          warn "PM2 restart failed"
      else
        warn "Dev mode — Django runserver should auto-reload"
        warn "If not, restart manually: cd $WEB_DIR && python3 manage.py runserver"
      fi
      ;;
  esac
fi

# ─── Done ─────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${GREEN}║   ✅  Web UI Update Complete!                        ║${RESET}"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════╝${RESET}"
echo ""
echo -e "  ${BOLD}What was updated:${RESET}"
echo -e "  • web/templates/       (HTML templates)"
echo -e "  • web/static/custom/   (CSS & JS)"
echo -e "  • web/static/assets/   (vendor bundles)"
echo -e "  • staticfiles_collected/ (collectstatic)"
echo ""
echo -e "  ${BOLD}Backup saved to:${RESET}"
echo -e "  • $BACKUP_DIR"
echo ""
echo -e "  ${BOLD}Rollback (if needed):${RESET}"
echo -e "  ${CYAN}  bash $0 --rollback-dir $BACKUP_DIR${RESET}"
echo ""

# ─── Optional rollback helper ─────────────────────────────────────────────────
# If called with --rollback-dir <backup_dir>, restore from backup
if [[ "${1:-}" == "--rollback-dir" && -n "${2:-}" ]]; then
  ROLLBACK_DIR="$2"
  step "ROLLBACK  Restoring from backup: $ROLLBACK_DIR"

  [[ -d "$ROLLBACK_DIR/templates" ]] && {
    rm -rf "$TEMPLATES_DIR"
    cp -r "$ROLLBACK_DIR/templates" "$TEMPLATES_DIR"
    success "Templates restored"
  }

  [[ -d "$ROLLBACK_DIR/static_custom" ]] && {
    rm -rf "$STATIC_CUSTOM_DIR"
    cp -r "$ROLLBACK_DIR/static_custom" "$STATIC_CUSTOM_DIR"
    success "Custom static restored"
  }

  success "Rollback complete! Restart your web server to apply."
fi
