#!/usr/bin/env bash
# =============================================================================
# Rabby Host — Safe Uninstall
# Distinguishes clearly between removal scopes. Anything destructive requires
# explicit typed confirmation. Hosted websites and databases are NEVER silently
# deleted.
# =============================================================================

set -Eeuo pipefail

CONF_DIR="/etc/rabby-host"
INSTALL_DIR="/opt/rabby-host"
AGENT_VENV="/opt/rabby-host-agent-venv"
DATA_DIR="/var/lib/rabby-host"
LOG_DIR="/var/log/rabby-host"
DB_NAME="rabbyhost"
DB_USER="rabbyhost"

log() { printf '\033[1;32m[uninstall]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Run as root: sudo bash scripts/uninstall.sh"

typed_confirm() {
  local what="$1" phrase="$2"
  echo
  echo "!!! DESTRUCTIVE OPERATION !!!"
  echo "You are about to: ${what}"
  echo "This CANNOT be undone."
  local answer
  read -r -p "Type '${phrase}' to confirm (anything else aborts): " answer
  [[ "${answer}" == "${phrase}" ]] || die "Aborted. Nothing was removed."
}

echo "Rabby Host uninstaller"
echo "Removal scopes:"
echo "  1) services    — stop and remove rabby-host systemd units"
echo "  2) application — remove /opt/rabby-host and agent venv"
echo "  3) config      — remove /etc/rabby-host (contains secrets)"
echo "  4) database    — drop the rabbyhost PostgreSQL database and role"
echo "  5) data        — remove /var/lib/rabby-host (incl. BACKUPS)"
echo "  6) users       — remove rabby and rabby-agent system users"
echo
echo "Hosted websites under /var/www and their Nginx configs are NEVER touched."
echo

read -r -p "Enter scopes to remove, space-separated (e.g. 'services application config'): " SCOPES
[[ -n "${SCOPES}" ]] || die "No scopes selected. Aborting."

has_scope() { [[ " ${SCOPES} " == *" $1 "* ]]; }

# --- Stop services first, always ----------------------------------------------
log "Stopping services..."
systemctl stop rabby-host.service rabby-host-worker.service rabby-host-agent.service 2>/dev/null || true

if has_scope services; then
  log "Removing systemd units..."
  systemctl disable rabby-host.service rabby-host-worker.service rabby-host-agent.service 2>/dev/null || true
  rm -f /etc/systemd/system/rabby-host.service /etc/systemd/system/rabby-host-worker.service /etc/systemd/system/rabby-host-agent.service
  systemctl daemon-reload
fi

if has_scope application; then
  typed_confirm "remove the application code from ${INSTALL_DIR} and ${AGENT_VENV}" "REMOVE APPLICATION"
  rm -rf "${INSTALL_DIR}" "${AGENT_VENV}"
  log "Application removed."
fi

if has_scope config; then
  typed_confirm "remove configuration and secrets in ${CONF_DIR}" "REMOVE CONFIG"
  rm -rf "${CONF_DIR}"
  log "Configuration removed."
fi

if has_scope database; then
  typed_confirm "drop PostgreSQL database '${DB_NAME}' and role '${DB_USER}' — ALL PANEL DATA WILL BE LOST" "DROP DATABASE"
  sudo -u postgres psql -v ON_ERROR_STOP=1 -c "DROP DATABASE IF EXISTS ${DB_NAME};"
  sudo -u postgres psql -v ON_ERROR_STOP=1 -c "DROP ROLE IF EXISTS ${DB_USER};"
  log "Database removed."
fi

if has_scope data; then
  typed_confirm "remove ${DATA_DIR} including ALL BACKUPS" "REMOVE DATA"
  rm -rf "${DATA_DIR}"
  log "Data removed."
fi

if has_scope users; then
  log "Removing system users (group membership must be empty)..."
  userdel rabby 2>/dev/null || warn "could not remove user 'rabby' (still owns files?)"
  userdel rabby-agent 2>/dev/null || warn "could not remove user 'rabby-agent'"
  groupdel rabby 2>/dev/null || true
  groupdel rabby-agent 2>/dev/null || true
fi

log "Uninstall finished for scopes: ${SCOPES}"
[[ " ${SCOPES} " == *" services "* ]] || log "Note: services scope not selected; units may still be registered."
log "Reminder: hosted websites under /var/www and Nginx site configs were NOT touched."
