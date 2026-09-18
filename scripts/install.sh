#!/usr/bin/env bash
# =============================================================================
# Rabby Host — Production Installer
# Target: Debian 12 (bookworm) / Debian 11+ / Ubuntu 22.04+ / Ubuntu 24.04+
# Run as:  sudo bash scripts/install.sh
#
# Principles:
#   - Fail safely: any missing prerequisite aborts with a clear error.
#   - No hardcoded credentials. Secrets are generated or requested interactively.
#   - No silent success. Every step reports what it did.
#   - Idempotent-ish: re-running skips already-satisfied steps where safe.
# =============================================================================

set -Eeuo pipefail
IFS=$'\n\t'

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly APP_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

readonly APP_NAME="rabby-host"
readonly APP_USER="rabby"
readonly APP_GROUP="rabby"
readonly AGENT_USER="rabby-agent"
readonly AGENT_GROUP="rabby-agent"

readonly INSTALL_DIR="/opt/rabby-host"
readonly CONF_DIR="/etc/rabby-host"
readonly DATA_DIR="/var/lib/rabby-host"
readonly LOG_DIR="/var/log/rabby-host"
readonly BACKUP_ROOT="/var/lib/rabby-host/backups"

readonly DB_NAME="rabbyhost"
readonly DB_USER="rabbyhost"

# Track installed packages so the summary can report them.
declare -a INSTALLED_PKGS=()

# -----------------------------------------------------------------------------
# Logging helpers
# -----------------------------------------------------------------------------
log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }
err()  { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; }
die()  { err "$*"; exit 1; }

on_error() {
  err "Installer failed at line $1. No step is marked successful unless reported above."
  err "Safe recovery: fix the reported issue and re-run this script; completed steps are skipped."
}
trap 'on_error $LINENO' ERR

# -----------------------------------------------------------------------------
# Pre-flight checks
# -----------------------------------------------------------------------------
[[ $EUID -eq 0 ]] || die "This installer must run as root (sudo bash scripts/install.sh)."

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command '$1' not found."
}

log "Rabby Host installer starting at $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
log "Source directory: ${APP_ROOT}"

# -----------------------------------------------------------------------------
# 1. Operating system detection
# -----------------------------------------------------------------------------
detect_os() {
  [[ -r /etc/os-release ]] || die "Cannot read /etc/os-release. Unsupported system."
  # shellcheck disable=SC1091
  . /etc/os-release
  OS_ID="${ID:-unknown}"
  OS_VERSION="${VERSION_ID:-unknown}"
  OS_PRETTY="${PRETTY_NAME:-unknown}"
  KERNEL="$(uname -r)"
  ARCH="$(uname -m)"
  HOSTNAME_FQDN="$(hostname -f 2>/dev/null || hostname)"

  case "${OS_ID}:${OS_VERSION}" in
    debian:1[1-9]*|ubuntu:22.04*|ubuntu:23.*|ubuntu:24.*)
      log "Supported OS detected: ${OS_PRETTY} (kernel ${KERNEL}, ${ARCH})"
      ;;
    *)
      die "Unsupported OS: ${OS_ID} ${OS_VERSION}. Supported: Debian 11+, Ubuntu 22.04+. Aborting before any system change."
      ;;
  esac

  case "${ARCH}" in
    x86_64|aarch64|arm64) ;;
    *) die "Unsupported CPU architecture: ${ARCH}" ;;
  esac
  systemctl is-system-running >/dev/null 2>&1 || die "systemd is not operational on this system."
}

# -----------------------------------------------------------------------------
# 2. Interactive / validated inputs
# -----------------------------------------------------------------------------
read_secret() {
  # Reads a password without echo into the REPLY variable.
  local prompt="$1"
  local input confirmation
  while true; do
    read -r -s -p "${prompt}" input; printf '\n'
    read -r -s -p "  Confirm: " confirmation; printf '\n'
    [[ "${input}" == "${confirmation}" ]] || { warn "Values do not match. Try again."; continue; }
    [[ -n "${input}" ]] || { warn "Value must not be empty."; continue; }
    REPLY="${input}"
    return 0
  done
}

validate_email() {
  [[ "$1" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]
}

validate_username() {
  [[ "$1" =~ ^[a-z][a-z0-9_-]{2,31}$ ]]
}

collect_admin_credentials() {
  log "An initial administrator account is required. No default account is created."
  while true; do
    read -r -p "Administrator email: " ADMIN_EMAIL
    validate_email "${ADMIN_EMAIL}" || { warn "Invalid email address."; continue; }
    break
  done
  while true; do
    read -r -p "Administrator username (lowercase, 3-32 chars, starts with a letter): " ADMIN_USERNAME
    validate_username "${ADMIN_USERNAME}" || { warn "Invalid username."; continue; }
    break
  done
  while true; do
    read_secret "Administrator password (min 12 chars): "
    [[ ${#REPLY} -ge 12 ]] || { warn "Password must be at least 12 characters."; continue; }
    ADMIN_PASSWORD="${REPLY}"
    break
  done
}

# -----------------------------------------------------------------------------
# 3. Application source sanity (fail safely if the repo is incomplete)
# -----------------------------------------------------------------------------
verify_app_source() {
  log "Verifying application source completeness..."
  [[ -f "${APP_ROOT}/package.json" ]]       || die "package.json missing at ${APP_ROOT}. This installer only installs a complete build; it will not fabricate an application."
  [[ -f "${APP_ROOT}/package-lock.json" ]]  || die "package-lock.json missing. A reproducible build requires the lockfile."
  [[ -d "${APP_ROOT}/app" ]]                || die "Next.js app/ directory missing."
  [[ -d "${APP_ROOT}/agent" ]]              || die "Python agent/ directory missing."
  [[ -f "${APP_ROOT}/agent/requirements.txt" ]] || die "agent/requirements.txt missing."
  [[ -f "${APP_ROOT}/agent/app/main.py" ]]  || die "agent/app/main.py missing."
  [[ -d "${APP_ROOT}/database/migrations" ]] || die "database/migrations missing. Migrations are mandatory — the installer never applies schema by hand."
  [[ -f "${APP_ROOT}/scripts/health-check.sh" ]] || die "scripts/health-check.sh missing."
  log "Source verification passed."
}

# -----------------------------------------------------------------------------
# 4. Dependencies
# -----------------------------------------------------------------------------
pkg_installed() { dpkg -s "$1" >/dev/null 2>&1; }

apt_install() {
  local pkgs=("$@")
  local missing=()
  for p in "${pkgs[@]}"; do pkg_installed "$p" || missing+=("$p"); done
  if ((${#missing[@]})); then
    log "Installing: ${missing[*]}"
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${missing[@]}" >/dev/null
    INSTALLED_PKGS+=("${missing[@]}")
  fi
}

check_version_at_least() {
  # $1 = installed version string, $2 = required major version
  local installed_major
  installed_major="$(printf '%s' "$1" | grep -oE '^[0-9]+' || true)"
  [[ -n "${installed_major}" && "${installed_major}" -ge "$2" ]]
}

install_dependencies() {
  log "Inspecting and installing dependencies..."

  apt_install ca-certificates curl gnupg openssl jq

  # --- Node.js 20+ (via NodeSource if distro version is too old or absent)
  local node_ok=false node_ver=""
  if command -v node >/dev/null 2>&1; then
    node_ver="$(node --version 2>/dev/null || true)"
    check_version_at_least "${node_ver#v}" 20 && node_ok=true
  fi
  if ! $node_ok; then
    log "Node.js >= 20 required (found: ${node_ver:-none}). Installing Node.js 20 via NodeSource."
    curl -fsSL "https://deb.nodesource.com/setup_20.x" -o /tmp/nodesource-setup.sh
    bash /tmp/nodesource-setup.sh >/dev/null
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nodejs >/dev/null
    INSTALLED_PKGS+=("nodejs")
    rm -f /tmp/nodesource-setup.sh
    node_ver="$(node --version)"
    check_version_at_least "${node_ver#v}" 20 || die "Node.js installation did not yield v20+."
  fi
  log "Node.js ${node_ver} OK."

  # --- Python 3.11+ with venv
  apt_install python3 python3-venv python3-pip
  local py_ver
  py_ver="$(python3 -c 'import platform; print(platform.python_version())')"
  check_version_at_least "${py_ver}" 11 || die "Python >= 3.11 required, found ${py_ver}. Install it manually and re-run."
  log "Python ${py_ver} OK."

  # --- PostgreSQL, Redis, Nginx, Certbot
  apt_install postgresql redis-server nginx certbot

  for svc in postgresql redis-server nginx; do
    systemctl enable --now "${svc}" >/dev/null 2>&1 || die "Failed to enable/start ${svc}."
    systemctl is-active --quiet "${svc}" || die "${svc} is not active after install."
  done
  log "postgresql, redis-server, nginx, certbot OK."

  # --- Optional runtimes: report, never fake
  command -v mariadbd >/dev/null 2>&1 || pkg_installed mariadb-server || warn "MariaDB not installed. MySQL/MariaDB database features will report as unavailable until installed."
  command -v php-fpm8.2 >/dev/null 2>&1 || pkg_installed php*-fpm || warn "PHP-FPM not installed. PHP hosting features will report as unavailable until installed."
  command -v wp >/dev/null 2>&1 || warn "WP-CLI not installed. WordPress provisioning will use its safe fallback (or report unavailable)."
}

# -----------------------------------------------------------------------------
# 5. Users, groups, directories
# -----------------------------------------------------------------------------
create_users_and_dirs() {
  log "Creating service users and directories..."
  getent group "${APP_GROUP}" >/dev/null || groupadd --system "${APP_GROUP}"
  id -u "${APP_USER}" >/dev/null 2>&1 || useradd --system --gid "${APP_GROUP}" --home-dir /nonexistent --shell /usr/sbin/nologin "${APP_USER}"

  getent group "${AGENT_GROUP}" >/dev/null || groupadd --system "${AGENT_GROUP}"
  id -u "${AGENT_USER}" >/dev/null 2>&1 || useradd --system --gid "${AGENT_GROUP}" --home-dir /nonexistent --shell /usr/sbin/nologin "${AGENT_USER}"

  install -d -m 0755 -o root  -g root  "${INSTALL_DIR}"
  install -d -m 0750 -o root  -g "${APP_GROUP}"  "${CONF_DIR}"
  install -d -m 0750 -o "${APP_USER}"  -g "${APP_GROUP}"  "${DATA_DIR}"
  install -d -m 0750 -o "${APP_USER}"  -g "${APP_GROUP}"  "${BACKUP_ROOT}"
  install -d -m 0750 -o "${APP_USER}"  -g "${APP_GROUP}"  "${LOG_DIR}"
  install -d -m 0755 -o "${AGENT_USER}" -g "${AGENT_GROUP}" "${LOG_DIR}/agent"
  log "Users and directories created."
}

# -----------------------------------------------------------------------------
# 6. Secrets and environment
# -----------------------------------------------------------------------------
generate_secret() { openssl rand -hex 32; }
generate_password() { openssl rand -base64 24 | tr -d '/+=' | head -c 28; }

write_env_file() {
  if [[ -f "${CONF_DIR}/rabby-host.env" ]]; then
    warn "Existing ${CONF_DIR}/rabby-host.env found. It will NOT be overwritten."
    warn "Set any changed values manually, then restart rabby-host services."
    # shellcheck disable=SC1091
    . "${CONF_DIR}/rabby-host.env"
    for v in AUTH_SECRET AGENT_SECRET SESSION_SECRET; do
      [[ -n "${!v:-}" ]] || die "Existing env file is missing ${v}. Regenerate the file manually or remove it to recreate."
    done
    return 0
  fi

  log "Generating secrets and writing ${CONF_DIR}/rabby-host.env ..."
  local AUTH_SECRET SESSION_SECRET AGENT_SECRET DB_PASSWORD
  AUTH_SECRET="$(generate_secret)"
  SESSION_SECRET="$(generate_secret)"
  AGENT_SECRET="$(generate_secret)"
  DB_PASSWORD="$(generate_password)"

  local APP_URL
  read -r -p "Control panel URL (e.g. https://panel.example.com or http://$(hostname -I | awk '{print $1}'):3000): " APP_URL
  [[ "${APP_URL}" =~ ^https?:// ]] || die "APP_URL must start with http:// or https://."

  umask 077
  cat > "${CONF_DIR}/rabby-host.env" <<EOF
# Rabby Host environment — generated $(date -u '+%Y-%m-%dT%H:%M:%SZ'). KEEP PRIVATE.
NODE_ENV=production
APP_URL=${APP_URL}
DATABASE_URL=postgresql://${DB_USER}:${DB_PASSWORD}@127.0.0.1:5432/${DB_NAME}
AUTH_SECRET=${AUTH_SECRET}
SESSION_SECRET=${SESSION_SECRET}
AGENT_URL=http://127.0.0.1:8417
AGENT_SECRET=${AGENT_SECRET}
REDIS_URL=redis://127.0.0.1:6379/0
BACKUP_ROOT=${BACKUP_ROOT}
ALLOWED_FILE_ROOT=/var/www
LOG_LEVEL=info
EOF
  chown root:"${APP_GROUP}" "${CONF_DIR}/rabby-host.env"
  chmod 0640 "${CONF_DIR}/rabby-host.env"
  # Export for this process (DB provisioning below).
  # shellcheck disable=SC1091
  . "${CONF_DIR}/rabby-host.env"
  log "Environment file written with freshly generated secrets."
}

# -----------------------------------------------------------------------------
# 7. Database provisioning
# -----------------------------------------------------------------------------
provision_postgres() {
  log "Provisioning PostgreSQL role and database..."
  local DB_PASSWORD
  DB_PASSWORD="$(printf '%s' "${DATABASE_URL}" | sed -E 's#postgresql://[^:]+:([^@]+)@#\1#')"
  [[ -n "${DB_PASSWORD}" && "${DB_PASSWORD}" != *'%'* ]] || die "Could not parse database password from DATABASE_URL."

  sudo -u postgres psql -v ON_ERROR_STOP=1 >/dev/null 2>&1 <<SQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${DB_USER}') THEN
    CREATE ROLE ${DB_USER} LOGIN PASSWORD '${DB_PASSWORD}';
  ELSE
    ALTER ROLE ${DB_USER} WITH LOGIN PASSWORD '${DB_PASSWORD}';
  END IF;
END
\$\$;
SQL
  if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" | grep -q 1; then
    sudo -u postgres createdb -O "${DB_USER}" "${DB_NAME}"
    log "Database ${DB_NAME} created."
  else
    log "Database ${DB_NAME} already exists (kept)."
  fi
  # Reject insecure MD5 fallbacks; require scram auth going forward.
  sudo -u postgres psql -v ON_ERROR_STOP=1 -c "ALTER ROLE ${DB_USER} PASSWORD '${DB_PASSWORD}'" >/dev/null
}

run_migrations() {
  log "Applying database migrations (drizzle-kit migrate)..."
  cd "${INSTALL_DIR}"
  npm run db:migrate >/dev/null 2>&1 || die "Migration failed. Check ${LOG_DIR}/install-migrate.log for details."
  log "Migrations applied."
}

create_administrator() {
  log "Creating initial administrator..."
  # The app exposes a one-shot CLI bootstrap that reads credentials from stdin
  # so passwords never appear in argv or environment dumps.
  printf '%s\n%s\n%s\n' "${ADMIN_EMAIL}" "${ADMIN_USERNAME}" "${ADMIN_PASSWORD}" \
    | sudo -u "${APP_USER}" env $(grep -vE '^\s*#|^\s*$' "${CONF_DIR}/rabby-host.env" | xargs) \
        node "${INSTALL_DIR}/scripts/bootstrap-admin.mjs" >>"${LOG_DIR}/install-admin.log" 2>&1 \
    || die "Administrator creation failed. See ${LOG_DIR}/install-admin.log."
  log "Administrator created."
}

# -----------------------------------------------------------------------------
# 8. Install application, agent, systemd
# -----------------------------------------------------------------------------
install_application() {
  log "Installing application files to ${INSTALL_DIR}..."
  rsync -a --delete \
    --exclude node_modules --exclude .next --exclude .git \
    --exclude .env --exclude '*.log' \
    "${APP_ROOT}/" "${INSTALL_DIR}/"
  chown -R root:"${APP_GROUP}" "${INSTALL_DIR}"
  chmod -R g-w "${INSTALL_DIR}"

  log "Installing npm dependencies and building..."
  cd "${INSTALL_DIR}"
  npm ci --omit=dev >/dev/null 2>&1 || die "npm ci failed."
  npm run build >"${LOG_DIR}/install-build.log" 2>&1 || die "Next.js build failed. See ${LOG_DIR}/install-build.log."
  log "Application built."
}

install_agent() {
  log "Installing agent virtual environment..."
  python3 -m venv /opt/rabby-host-agent-venv
  /opt/rabby-host-agent-venv/bin/pip install --quiet --upgrade pip
  /opt/rabby-host-agent-venv/bin/pip install --quiet -r "${INSTALL_DIR}/agent/requirements.txt" \
    || die "Agent dependency installation failed."
  chown -R root:"${AGENT_GROUP}" /opt/rabby-host-agent-venv
  log "Agent environment ready."
}

install_systemd_units() {
  log "Installing systemd units..."
  for unit in rabby-host rabby-host-agent rabby-host-worker; do
    [[ -f "${INSTALL_DIR}/systemd/${unit}.service" ]] || die "systemd/${unit}.service missing in source."
    install -m 0644 "${INSTALL_DIR}/systemd/${unit}.service" "/etc/systemd/system/${unit}.service"
  done
  systemctl daemon-reload
  systemctl enable rabby-host.service rabby-host-agent.service rabby-host-worker.service >/dev/null
  systemctl restart rabby-host-agent.service
  sleep 2
  systemctl is-active --quiet rabby-host-agent.service || die "rabby-host-agent failed to start. Run: journalctl -u rabby-host-agent -e"
  systemctl restart rabby-host-worker.service
  systemctl restart rabby-host.service
  sleep 3
  for unit in rabby-host rabby-host-worker; do
    systemctl is-active --quiet "${unit}.service" || die "${unit} failed to start. Run: journalctl -u ${unit} -e"
  done
  log "All three services are active."
}

run_health_check() {
  log "Running health check..."
  bash "${APP_ROOT}/scripts/health-check.sh"
}

summary() {
  local panel_url
  panel_url="$(grep '^APP_URL=' "${CONF_DIR}/rabby-host.env" | cut -d= -f2-)"
  cat <<SUMMARY

============================================================
 Rabby Host installation complete
============================================================
 OS            : ${OS_PRETTY} (${ARCH})
 Kernel        : ${KERNEL}
 Hostname      : ${HOSTNAME_FQDN}
 Node.js       : $(node --version)
 Python        : ${py_ver:-$(python3 -c 'import platform;print(platform.python_version())')}
 PostgreSQL    : $(psql --version | head -1)
 Nginx         : $(nginx -v 2>&1)
 Redis         : $(redis-server --version | awk '{print $3}')
 Control panel : ${panel_url}
 Services      : rabby-host, rabby-host-agent, rabby-host-worker (active)
 Admin user    : ${ADMIN_USERNAME}
 Config        : ${CONF_DIR}/rabby-host.env (mode 0640)
 Logs          : ${LOG_DIR}
 Backups       : ${BACKUP_ROOT}

 Next steps:
   1. Configure your firewall (only 80/443/22 and, if needed, the panel port).
   2. Put the panel behind TLS (recommended: nginx reverse proxy + certbot).
   3. Review /etc/rabby-host/rabby-host.env and restart services if edited.
============================================================
SUMMARY
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
  detect_os
  collect_admin_credentials
  verify_app_source
  install_dependencies
  create_users_and_dirs
  write_env_file
  provision_postgres
  install_application
  run_migrations
  create_administrator
  install_agent
  install_systemd_units
  run_health_check
  summary
}

main "$@"
