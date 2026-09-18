#!/usr/bin/env bash
# =============================================================================
# Rabby Host — Health Check
# Verifies application, agent, worker, PostgreSQL, Redis, Nginx, filesystem,
# permissions, disk and memory. Exits non-zero on any CRITICAL failure.
# CRITICAL failures = non-zero exit. WARN failures are reported but exit 0.
# =============================================================================

set -Eeuo pipefail

CONF_DIR="/etc/rabby-host"
FAILURES=0
WARNINGS=0

ok()   { printf '  [ OK ] %s\n' "$*"; }
warn() { printf '  [WARN] %s\n' "$*"; WARNINGS=$((WARNINGS+1)); }
crit() { printf '  [CRIT] %s\n' "$*"; FAILURES=$((FAILURES+1)); }

section() { printf '\n== %s ==\n' "$*"; }

service_check() {
  local svc="$1" critical="${2:-true}"
  if systemctl is-active --quiet "${svc}"; then
    ok "${svc} is active"
  else
    if [[ "$critical" == "true" ]]; then
      crit "${svc} is NOT active"
    else
      warn "${svc} is not active"
    fi
  fi
}

url_check() {
  local name="$1" url="$2" critical="${3:-true}"
  local code
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$url" || true)"
  if [[ "$code" =~ ^(2|3)[0-9][0-9]$ ]]; then
    ok "${name} responded (${code})"
  else
    if [[ "$critical" == "true" ]]; then
      crit "${name} unreachable (HTTP ${code:-no response})"
    else
      warn "${name} unreachable (HTTP ${code:-no response})"
    fi
  fi
}

echo "Rabby Host health check — $(date -u '+%Y-%m-%d %H:%M:%S UTC')"

# --- systemd / services ------------------------------------------------------
section "Systemd services"
[[ "$(systemctl is-system-running 2>/dev/null || true)" =~ ^(running|degraded)$ ]] \
  && ok "systemd is running" || crit "systemd is not running"
service_check rabby-host
service_check rabby-host-agent
service_check rabby-host-worker
service_check postgresql
service_check redis-server
service_check nginx
# PHP-FPM and MariaDB are optional runtimes: warn only.
if systemctl list-unit-files 'php*-fpm.service' --no-legend | grep -q .; then
  if systemctl is-active --quiet php8.2-fpm 2>/dev/null; then ok "php8.2-fpm active"; else warn "PHP-FPM installed but expected unit not active"; fi
else
  warn "PHP-FPM not installed (PHP hosting unavailable)"
fi
systemctl is-active --quiet mariadb 2>/dev/null && ok "mariadb active" || warn "MariaDB not running (MySQL features unavailable)"

# --- HTTP endpoints ----------------------------------------------------------
section "HTTP endpoints"
AGENT_PORT="$(grep '^AGENT_URL=' "${CONF_DIR}/rabby-host.env" 2>/dev/null | sed -E 's#.*:([0-9]+)/?$#\1#')"
AGENT_PORT="${AGENT_PORT:-8417}"
url_check "Control panel" "http://127.0.0.1:3000/api/v1/system/health"
url_check "Agent health"  "http://127.0.0.1:${AGENT_PORT}/health" true

# --- Nginx configuration -----------------------------------------------------
section "Nginx"
if nginx -t >/dev/null 2>&1; then
  ok "nginx configuration valid"
else
  crit "nginx configuration INVALID (nginx -t failed) — reload blocked by design"
fi

# --- Database connectivity ---------------------------------------------------
section "PostgreSQL"
if [[ -r "${CONF_DIR}/rabby-host.env" ]]; then
  DB_URL="$(grep '^DATABASE_URL=' "${CONF_DIR}/rabby-host.env" | cut -d= -f2-)"
  if PGPASSWORD="${DB_URL#postgresql://rabbyhost:}" psql -h 127.0.0.1 -U rabbyhost -d rabbyhost \
       -c 'SELECT 1' >/dev/null 2>&1; then
    ok "database connection OK"
  else
    crit "cannot connect to PostgreSQL as application user"
  fi
else
  crit "configuration file ${CONF_DIR}/rabby-host.env missing or unreadable"
fi

# --- Filesystem / permissions ------------------------------------------------
section "Filesystem"
for d in /opt/rabby-host /etc/rabby-host /var/lib/rabby-host /var/log/rabby-host; do
  [[ -d "$d" ]] && ok "directory ${d} exists" || crit "directory ${d} missing"
done
ENV_FILE="${CONF_DIR}/rabby-host.env"
if [[ -f "${ENV_FILE}" ]]; then
  PERMS="$(stat -c '%a' "${ENV_FILE}")"
  [[ "${PERMS}" =~ ^6[04]0$ ]] && ok "env file permissions restrictive (${PERMS})" \
    || crit "env file permissions too open (${PERMS}); run: chmod 640 ${ENV_FILE}"
  OWNER="$(stat -c '%U' "${ENV_FILE}")"
  [[ "${OWNER}" == "root" ]] || crit "env file owned by ${OWNER}; must be root-owned"
else
  crit "env file missing"
fi

# --- Disk / memory -----------------------------------------------------------
section "Resources"
DISK_PCT="$(df -P / | awk 'NR==2 {gsub("%","",$5); print $5}')"
if   (( DISK_PCT >= 90 )); then crit "root filesystem ${DISK_PCT}% full"
elif (( DISK_PCT >= 80 )); then warn "root filesystem ${DISK_PCT}% full"
else ok "root filesystem ${DISK_PCT}% used"; fi

MEM_TOTAL="$(awk '/MemTotal/ {print $2}' /proc/meminfo)"
(( MEM_TOTAL >= 1000000 )) && ok "RAM $((MEM_TOTAL/1024)) MB" || warn "RAM $((MEM_TOTAL/1024)) MB (below 1 GB)"

LOAD="$(cut -d' ' -f1 /proc/loadavg)"
NPROC="$(nproc)"
ok "load average ${LOAD} on ${NPROC} CPU(s)"

# --- Result ------------------------------------------------------------------
echo
echo "Result: ${FAILURES} critical, ${WARNINGS} warnings"
if (( FAILURES > 0 )); then
  echo "HEALTH CHECK FAILED"
  exit 1
fi
echo "HEALTH CHECK PASSED"
exit 0
