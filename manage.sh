#!/usr/bin/env bash
# =============================================================================
#  reNgine-ng — Quick Management Script
#  Usage: bash manage.sh [start|stop|restart|logs|update|status|uninstall]
# =============================================================================
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/opt/rengine}"
COMPOSE_DIR="${INSTALL_DIR}/docker"
ENV_FILE="${INSTALL_DIR}/.env"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; exit 1; }

require_dir() {
  [ -d "$COMPOSE_DIR" ] || error "reNgine-ng not found at $INSTALL_DIR. Run install.sh first."
}

cmd_start() {
  require_dir
  info "Starting reNgine-ng…"
  cd "$COMPOSE_DIR" && docker compose --env-file "$ENV_FILE" up -d
  success "reNgine-ng started."
}

cmd_stop() {
  require_dir
  info "Stopping reNgine-ng…"
  cd "$COMPOSE_DIR" && docker compose --env-file "$ENV_FILE" down
  success "reNgine-ng stopped."
}

cmd_restart() {
  require_dir
  info "Restarting reNgine-ng…"
  cd "$COMPOSE_DIR" && docker compose --env-file "$ENV_FILE" restart
  success "reNgine-ng restarted."
}

cmd_logs() {
  require_dir
  cd "$COMPOSE_DIR" && docker compose --env-file "$ENV_FILE" logs -f --tail=100 "${2:-}"
}

cmd_status() {
  require_dir
  cd "$COMPOSE_DIR" && docker compose --env-file "$ENV_FILE" ps
}

cmd_update() {
  require_dir
  info "Pulling latest code…"
  git -C "$INSTALL_DIR" pull --ff-only
  info "Pulling latest Docker images…"
  cd "$COMPOSE_DIR" && docker compose --env-file "$ENV_FILE" pull
  info "Restarting services with new images…"
  docker compose --env-file "$ENV_FILE" up -d
  success "Update complete."
}

cmd_uninstall() {
  require_dir
  warn "This will STOP all containers and DELETE all data (volumes, DB, scan results)!"
  read -rp "Type 'yes' to confirm: " confirm
  [[ "$confirm" == "yes" ]] || { info "Aborted."; exit 0; }

  cd "$COMPOSE_DIR"
  docker compose --env-file "$ENV_FILE" down -v --remove-orphans
  cd /
  rm -rf "$INSTALL_DIR"
  success "reNgine-ng uninstalled and all data removed."
}

cmd_shell() {
  require_dir
  local svc="${2:-web}"
  info "Opening shell in ${svc} container…"
  cd "$COMPOSE_DIR" && docker compose --env-file "$ENV_FILE" exec "$svc" bash
}

usage() {
  echo ""
  echo -e "${BOLD}reNgine-ng Management Script${RESET}"
  echo ""
  echo "  Usage: bash manage.sh <command>"
  echo ""
  echo "  Commands:"
  echo "    start       Start all services"
  echo "    stop        Stop all services"
  echo "    restart     Restart all services"
  echo "    logs        Follow logs (optionally: logs web)"
  echo "    status      Show container status"
  echo "    update      Pull latest code + images and restart"
  echo "    shell       Open bash in a container (default: web)"
  echo "    uninstall   Remove all containers, volumes and files"
  echo ""
  echo "  Environment variables:"
  echo "    INSTALL_DIR   Installation directory (default: /opt/rengine)"
  echo ""
}

ACTION="${1:-help}"
case "$ACTION" in
  start)     cmd_start ;;
  stop)      cmd_stop ;;
  restart)   cmd_restart ;;
  logs)      cmd_logs "$@" ;;
  status)    cmd_status ;;
  update)    cmd_update ;;
  uninstall) cmd_uninstall ;;
  shell)     cmd_shell "$@" ;;
  *)         usage ;;
esac
