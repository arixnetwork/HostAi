#!/usr/bin/env bash
# =============================================================================
# Rabby Host — Update / Upgrade
# 1. back up configuration       5. rebuild
# 2. update source               6. restart services
# 3. install dependencies        7. health checks
# 4. run migrations              8. rollback on failure where practical
# Never overwrites user configuration.
# =============================================================================

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly APP_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly CONF_DIR="/etc/rabby-host"
readonly INSTALL_DIR="/opt/rabby-host"
readonly LOG_DIR="/var/log/rabby-host"
readonly STAMP="$(date -u '+%Y%m%d-%H%M%S')"
readonly CONF_BACKUP="${CONF_DIR}/backup-${STAMP}"
readonly PREVIOUS_MANIFEST="${DATA_DIR:-/var/lib/rabby-host}/.installed-manifest"

log() { printf '\033[1;32m[update]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Run as root: sudo bash scripts/update.sh"
[[ -f "${CONF_DIR}/rabby-host.env" ]] || die "No existing installation found (${CONF_DIR}/rabby-host.env missing). Use scripts/install.sh instead."

# --- 1. Back up configuration (never overwrite) -------------------------------
log "Backing up configuration to ${CONF_BACKUP}..."
install -d -m 0700 "${CONF_BACKUP}"
cp -a "${CONF_DIR}/rabby-host.env" "${CONF_BACKUP}/"
[[ -f "${PREVIOUS_MANIFEST}" ]] && cp -a "${PREVIOUS_MANIFEST}" "${CONF_BACKUP}/" || true
log "Configuration backed up."

# --- 2. Update source ---------------------------------------------------------
log "Updating source in ${INSTALL_DIR}..."
if [[ -d "${INSTALL_DIR}/.git" ]]; then
  CURRENT_COMMIT="$(git -C "${INSTALL_DIR}" rev-parse HEAD)"
  git -C "${INSTALL_DIR}" fetch --all --tags >/dev/null 2>&1 || die "git fetch failed."
  TARGET="${1:-origin/main}"
  git -C "${INSTALL_DIR}" reset --hard "${TARGET}" >/dev/null 2>&1 || die "git checkout of ${TARGET} failed."
  NEW_COMMIT="$(git -C "${INSTALL_DIR}" rev-parse HEAD)"
  if [[ "${CURRENT_COMMIT}" == "${NEW_COMMIT}" ]]; then
    log "Already at ${CURRENT_COMMIT:0:12}. Nothing to update."
    exit 0
  fi
  log "Updating ${CURRENT_COMMIT:0:12} -> ${NEW_COMMIT:0:12} (${TARGET})."
else
  log "No git checkout; syncing from ${APP_ROOT}..."
  rsync -a --delete --exclude node_modules --exclude .next --exclude .git \
        --exclude .env --exclude '*.log' "${APP_ROOT}/" "${INSTALL_DIR}/"
fi

# --- 3. Dependencies ----------------------------------------------------------
cd "${INSTALL_DIR}"
log "Installing dependencies..."
npm ci --omit=dev >/dev/null 2>&1 || die "npm ci failed."

# --- 4. Migrations ------------------------------------------------------------
log "Applying migrations..."
# shellcheck disable=SC1091
set -a; . "${CONF_DIR}/rabby-host.env"; set +a
npm run db:migrate >"${LOG_DIR}/update-migrate-${STAMP}.log" 2>&1 \
  || die "Migration failed. Services were NOT restarted; current version keeps running. See ${LOG_DIR}/update-migrate-${STAMP}.log."

# --- 5. Build -----------------------------------------------------------------
log "Building application..."
npm run build >"${LOG_DIR}/update-build-${STAMP}.log" 2>&1 \
  || die "Build failed. Services were NOT restarted; current version keeps running."

# --- 6. Restart services ------------------------------------------------------
log "Restarting services..."
systemctl restart rabby-host-agent.service
systemctl restart rabby-host-worker.service
systemctl restart rabby-host.service
sleep 3
for unit in rabby-host rabby-host-agent rabby-host-worker; do
  systemctl is-active --quiet "${unit}" || die "${unit} failed to start after update."
done

# --- 7. Health check ----------------------------------------------------------
if ! bash "${APP_ROOT}/scripts/health-check.sh"; then
  # --- 8. Rollback where practical -------------------------------------------
  err_msg="Health check failed after update."
  if [[ -n "${CURRENT_COMMIT:-}" ]]; then
    printf '\033[1;33m[rollback]\033[0m %s\n' "${err_msg} Rolling back to ${CURRENT_COMMIT:0:12}..."
    git -C "${INSTALL_DIR}" reset --hard "${CURRENT_COMMIT}" >/dev/null 2>&1 || true
    npm ci --omit=dev >/dev/null 2>&1 || true
    npm run build >/dev/null 2>&1 || true
    systemctl restart rabby-host-agent rabby-host-worker rabby-host || true
    die "Rolled back. Verify services manually: systemctl status rabby-host"
  fi
  die "${err_msg} Manual intervention required (no git history available for automatic rollback)."
fi

git -C "${INSTALL_DIR}" ls-files > "${PREVIOUS_MANIFEST}" 2>/dev/null || true
log "Update complete and healthy. Configuration backup: ${CONF_BACKUP}"
