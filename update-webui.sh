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

# ─── List all rengine app containers (sorted: web first, then workers) ───────
list_rengine_app_containers() {
  # Returns all rengine containers that could host the Django app,
  # sorted so the full-stack containers (web, django, app) come first.
  local all
  all=$(docker ps --format '{{.Names}}' 2>/dev/null \
    | grep -Ei "rengine" 2>/dev/null || true)
  [[ -z "$all" ]] && return

  # Pure infra — never run Django manage.py commands in these
  local INFRA_PAT='nginx|proxy|redis|postgres|db-1|db-2|rabbitmq|mq-|flower'

  # Priority 1: containers explicitly named 'web' or 'django' or 'app'
  echo "$all" | grep -Ei "(rengine[-_]web|rengine[-_]django|rengine[-_]app)" \
    | grep -vEi "$INFRA_PAT" || true
  # Priority 2: containers named 'worker' (not beat — beat has fewer deps)
  echo "$all" | grep -Ei "worker" \
    | grep -vEi "beat|$INFRA_PAT" || true
  # Priority 3: everything else (including celery-beat as last resort)
  echo "$all" | grep -vEi "web|django|app|worker|$INFRA_PAT" || true
}

# ─── Find Python binary inside a container ───────────────────────────────────
find_python_in_container() {
  local cname="$1"

  # Strategy: find the Python that has django-environ installed.
  # reNgine settings.py imports environ at the top — without it collectstatic
  # always fails, regardless of which Python binary we use.
  #
  # Step 1: find the Python binary that can actually "import environ"
  local py found

  # Common explicit paths (handles venv, system, pyenv, conda)
  for py in \
    "/usr/local/bin/python3" \
    "/usr/bin/python3" \
    "/home/rengine/.venv/bin/python3" \
    "/home/rengine/venv/bin/python3" \
    "/venv/bin/python3" \
    "/opt/venv/bin/python3" \
    "/opt/pyenv/shims/python3" \
    "/usr/local/bin/python" \
    "/usr/bin/python"; do
    # Check binary exists AND can import environ
    if docker exec "$cname" sh -c \
      "test -x '$py' && '$py' -c 'import environ' 2>/dev/null" 2>/dev/null; then
      echo "$py"; return
    fi
  done

  # Step 2: locate environ package on the filesystem and infer Python from it
  found=$(docker exec "$cname" sh -c '
    # Find environ package and work back to its Python binary
    for sp in $(find /usr /home /opt /venv -maxdepth 8 -type d -name "environ" 2>/dev/null | head -5); do
      # site-packages/environ → site-packages → python3.x/site-packages → python3.x
      py=$(echo "$sp" | sed "s|/lib/python[0-9.]*.*||")/bin/python3
      [ -x "$py" ] && echo "$py" && exit 0
      # try without version suffix
      py=$(echo "$sp" | sed "s|/lib/python[0-9.]*.*||")/bin/python
      [ -x "$py" ] && echo "$py" && exit 0
    done
  ' 2>/dev/null || true)
  [[ -n "$found" ]] && { echo "$found"; return; }

  # Step 3: any Python binary that can import environ (via PATH)
  found=$(docker exec "$cname" sh -c '
    for py in python3 python; do
      if command -v "$py" >/dev/null 2>&1 && "$py" -c "import environ" 2>/dev/null; then
        command -v "$py"; exit 0
      fi
    done
  ' 2>/dev/null || true)
  [[ -n "$found" ]] && { echo "$found"; return; }

  # Step 4: return any Python we can find (even without environ — stub will handle it)
  found=$(docker exec "$cname" sh -c \
    'command -v python3 2>/dev/null || command -v python 2>/dev/null
     find /usr /home /opt /venv -maxdepth 6 -name "python3" -type f 2>/dev/null | head -1' \
    2>/dev/null | head -1 || true)
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
  # ── Docker: try containers in priority order until one succeeds ──────────────
  info "Scanning rengine containers for a working Django environment…"

  # Build the inline shell script ONCE (container-agnostic, uses $PY placeholder)
  # We pass CONTAINER_PY as an arg so the same script works for any container.
  COLLECT_SCRIPT='#!/bin/sh
CONTAINER_PY="$1"
# ── locate manage.py ──────────────────────────────────────
MANAGE_DIR=""
for D in /home/rengine/rengine /home/rengine/web /usr/src/app /app /rengine/web; do
  [ -f "$D/manage.py" ] && { MANAGE_DIR="$D"; break; }
done
[ -z "$MANAGE_DIR" ] && { echo "[ERR] manage.py not found"; exit 1; }
cd "$MANAGE_DIR"
echo "[INFO] Working dir: $MANAGE_DIR"

# ── settings ──────────────────────────────────────────────
[ -f "reNgine/settings_local.py" ] && export DJANGO_SETTINGS_MODULE="reNgine.settings_local"
[ -f "reNgine/settings.py" ]       && export DJANGO_SETTINGS_MODULE="${DJANGO_SETTINGS_MODULE:-reNgine.settings}"
echo "[INFO] Settings: $DJANGO_SETTINGS_MODULE"

# ── patch __init__.py: stub celery import ─────────────────
INIT="$MANAGE_DIR/reNgine/__init__.py"
INIT_PATCHED=false
if [ -f "$INIT" ] && grep -q "from .celery" "$INIT"; then
  cp "$INIT" "${INIT}.bak_cs"
  sed -i "s|^from .celery import.*|# stubbed by update-webui.sh|" "$INIT"
  INIT_PATCHED=true
  echo "[INFO] Patched __init__.py (celery stub)"
fi

# ── patch settings.py: inject stub environ if module missing ──────────────────
# reNgine/settings.py imports django-environ at the top:
#   import environ; env = environ.Env(...)
# If environ is not installed we create a minimal stub module so that
# collectstatic (which only needs STATIC_ROOT / STATICFILES_DIRS) can run.
SETTINGS_FILE="$MANAGE_DIR/reNgine/settings.py"
ENVIRON_STUB_INJECTED=false
if ! "$CONTAINER_PY" -c "import environ" 2>/dev/null; then
  echo "[INFO] django-environ not found — injecting stub"
  # Write a minimal environ stub into a temp package that shadows the real one
  STUB_DIR="$MANAGE_DIR/_env_stub"
  mkdir -p "$STUB_DIR"
  cat > "$STUB_DIR/environ.py" << '"'"'STUB_EOF'"'"'
"""Minimal django-environ stub for collectstatic only."""
import os, re

class Env:
    def __init__(self, **defaults): self._defaults = defaults
    def __call__(self, key, default=None, cast=None):
        v = os.environ.get(key, self._defaults.get(key, default))
        if cast and v is not None:
            try: return cast(v)
            except: pass
        return v
    def db(self, var="DATABASE_URL", default="sqlite:///stub.db"):
        url = os.environ.get(var, default)
        return {"ENGINE": "django.db.backends.sqlite3", "NAME": "/tmp/stub_cs.db"}
    def cache(self, var="CACHE_URL", default="locmemcache://"):
        return {"BACKEND": "django.core.cache.backends.dummy.DummyCache"}
    def bool(self, key, default=False): return bool(self(key, default))
    def int(self, key, default=0): return int(self(key, default) or default)
    def list(self, key, default=None): return default or []
    def str(self, key, default=""): return str(self(key, default) or "")
    def path(self, key, default="/"): return Path(str(self(key, default) or default))
    def read_env(self, *a, **kw): pass
    @staticmethod
    def read_env(*a, **kw): pass

class Path:
    def __init__(self, p=""): self._path = p
    def __str__(self): return self._path
    def __call__(self, *parts): return os.path.join(self._path, *parts)
    def __add__(self, other): return Path(self._path + other)

def Path(p): return p
STUB_EOF
  # Prepend stub dir to PYTHONPATH so settings.py finds it first
  export PYTHONPATH="$STUB_DIR:${PYTHONPATH:-}"
  ENVIRON_STUB_INJECTED=true
fi

# ── collectstatic ─────────────────────────────────────────
TMPOUT=$("$CONTAINER_PY" manage.py collectstatic --noinput 2>&1)
CS=$?

# ── always restore __init__.py ────────────────────────────
$INIT_PATCHED && mv "${INIT}.bak_cs" "$INIT" && echo "[INFO] Restored __init__.py"

# ── remove environ stub ───────────────────────────────────
$ENVIRON_STUB_INJECTED && rm -rf "$STUB_DIR" && echo "[INFO] Removed environ stub"

if [ $CS -ne 0 ]; then
  echo "$TMPOUT" | grep -iE "error|traceback|ModuleNotFound" | tail -4 || true
  echo "[WARN] manage.py collectstatic failed (exit $CS) — trying direct file copy fallback"

  # ── Direct copy fallback: copy custom/ and assets/ into staticfiles_collected ─
  # Since templates and static source files are already on the shared host volume,
  # we only need to sync the changed files into STATIC_ROOT.
  STATIC_SRC="$MANAGE_DIR/../static"
  # Try known STATIC_ROOT locations
  for DST in \
    "$MANAGE_DIR/staticfiles_collected" \
    "$MANAGE_DIR/../staticfiles_collected" \
    "/home/rengine/staticfiles_collected" \
    "/staticfiles_collected"; do
    if [ -d "$DST" ]; then STATIC_DST="$DST"; break; fi
  done
  [ -z "$STATIC_DST" ] && STATIC_DST="$MANAGE_DIR/staticfiles_collected" && mkdir -p "$STATIC_DST"

  if [ -d "$STATIC_SRC/custom" ]; then
    mkdir -p "$STATIC_DST/custom" "$STATIC_DST/assets"
    cp -rf "$STATIC_SRC/custom/." "$STATIC_DST/custom/" 2>/dev/null \
      && echo "[OK] custom/ synced to $STATIC_DST/custom/" \
      || echo "[WARN] custom/ copy had errors"
    cp -rf "$STATIC_SRC/assets/." "$STATIC_DST/assets/" 2>/dev/null \
      && echo "[OK] assets/ synced" || true
    echo "[DONE] Direct file copy complete"
    exit 0
  else
    echo "[ERR] Static source not found at $STATIC_SRC"
    exit 1
  fi
fi

echo "$TMPOUT" | grep -iE "static file|copied|unmodified" | tail -6 || true
echo "[DONE] collectstatic finished"
'

  COLLECT_DONE=false
  TRIED_CONTAINERS=""

  while IFS= read -r CTR; do
    [[ -z "$CTR" ]] && continue

    # find Python in this container
    CTR_PY="$(find_python_in_container "$CTR")"
    [[ -z "$CTR_PY" ]] && { info "  skip $CTR (no Python found)"; continue; }

    info "  Trying $CTR  (python: $CTR_PY)…"
    TRIED_CONTAINERS="$TRIED_CONTAINERS $CTR"

    if docker exec "$CTR" sh -c "$COLLECT_SCRIPT" -- "$CTR_PY"; then
      success "collectstatic done inside $CTR"
      COLLECT_DONE=true
      break
    else
      warn "  $CTR failed — trying next container…"
    fi
  done < <(list_rengine_app_containers)

  if ! $COLLECT_DONE; then
    warn "collectstatic failed in all containers:${TRIED_CONTAINERS:- (none found)}"
    warn "Templates & custom CSS/JS are already updated on the host volume."
    warn "Static files may be stale until you run:"
    warn "  docker exec <django-container> python manage.py collectstatic --noinput"
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
