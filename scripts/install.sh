#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

APP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_DIR=/opt/rabby-host
CONF_DIR=/etc/rabby-host
DATA_DIR=/var/lib/rabby-host
LOG_DIR=/var/log/rabby-host
DB_NAME=rabbyhost
DB_USER=rabbyhost
APP_USER=rabby
AGENT_USER=rabby-agent

log(){ printf '[install] %s\n' "$*"; }
die(){ printf '[ERROR] %s\n' "$*" >&2; exit 1; }
trap 'die "failed at line $LINENO"' ERR

[[ $EUID -eq 0 ]] || die 'run as root: sudo bash scripts/install.sh'
command -v apt-get >/dev/null || die 'apt-get is required'
command -v systemctl >/dev/null || die 'systemd is required'

. /etc/os-release
case "${ID}:${VERSION_ID}" in
  debian:1[1-9]*|ubuntu:22.04*|ubuntu:23.*|ubuntu:24.*) ;;
  *) die "unsupported OS: ${PRETTY_NAME:-unknown}; supported Debian 11+ and Ubuntu 22.04+" ;;
esac
case "$(uname -m)" in x86_64|aarch64|arm64) ;; *) die 'unsupported architecture' ;; esac

for path in package.json package-lock.json; do
  [[ -f "$APP_ROOT/$path" ]] || die "$path is missing; refusing to install an incomplete application"
done

apt_install(){
  local missing=() p
  for p in "$@"; do dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q 'install ok installed' || missing+=("$p"); done
  ((${#missing[@]})) || return 0
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}"
}

version_major(){ printf '%s' "$1" | sed -E 's/^v?([0-9]+).*/\1/'; }
apt_install ca-certificates curl git jq openssl rsync sudo python3 python3-venv python3-pip postgresql redis-server nginx certbot nodejs npm

node_major=$(version_major "$(node --version 2>/dev/null || echo 0)")
if (( node_major < 20 )); then
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  apt-get install -y nodejs
fi
python_major=$(version_major "$(python3 --version | awk '{print $2}')")
(( python_major >= 3 )) || die 'Python 3 is required'

systemctl enable --now postgresql redis-server nginx
getent group "$APP_USER" >/dev/null || groupadd --system "$APP_USER"
id -u "$APP_USER" >/dev/null 2>&1 || useradd --system --gid "$APP_USER" --home-dir /nonexistent --shell /usr/sbin/nologin "$APP_USER"
getent group "$AGENT_USER" >/dev/null || groupadd --system "$AGENT_USER"
id -u "$AGENT_USER" >/dev/null 2>&1 || useradd --system --gid "$AGENT_USER" --home-dir /nonexistent --shell /usr/sbin/nologin "$AGENT_USER"
install -d -m 0755 "$INSTALL_DIR"
install -d -m 0750 -o root -g "$APP_USER" "$CONF_DIR"
install -d -m 0750 -o "$APP_USER" -g "$APP_USER" "$DATA_DIR" "$LOG_DIR"

if [[ ! -f "$CONF_DIR/rabby-host.env" ]]; then
  read -r -p 'Control panel URL: ' APP_URL
  [[ "$APP_URL" =~ ^https?:// ]] || die 'APP_URL must begin with http:// or https://'
  read -r -p 'Administrator email: ' ADMIN_EMAIL
  [[ "$ADMIN_EMAIL" =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]] || die 'invalid administrator email'
  read -r -s -p 'Administrator password (minimum 12 characters): ' ADMIN_PASSWORD; printf '\n'
  ((${#ADMIN_PASSWORD} >= 12)) || die 'password must be at least 12 characters'
  DB_PASSWORD=$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 32)
  umask 077
  cat > "$CONF_DIR/rabby-host.env" <<EOF
NODE_ENV=production
APP_URL=$APP_URL
DATABASE_URL=postgresql://$DB_USER:$DB_PASSWORD@127.0.0.1:5432/$DB_NAME
AUTH_SECRET=$(openssl rand -hex 32)
SESSION_SECRET=$(openssl rand -hex 32)
AGENT_SECRET=$(openssl rand -hex 32)
AGENT_URL=http://127.0.0.1:8417
REDIS_URL=redis://127.0.0.1:6379/0
BACKUP_ROOT=$DATA_DIR/backups
ALLOWED_FILE_ROOT=/var/www
ADMIN_EMAIL=$ADMIN_EMAIL
EOF
  chown root:"$APP_USER" "$CONF_DIR/rabby-host.env"
  chmod 0640 "$CONF_DIR/rabby-host.env"
else
  log 'preserving existing environment file'
fi

set -a; . "$CONF_DIR/rabby-host.env"; set +a
[[ -n "${DATABASE_URL:-}" ]] || die 'DATABASE_URL is missing from environment file'
DB_PASSWORD="$(printf '%s' "$DATABASE_URL" | sed -n 's#^postgresql://[^:]*:\([^@]*\)@.*#\1#p')"
[[ -n "$DB_PASSWORD" ]] || die 'could not read database password'
sudo -u postgres psql -v ON_ERROR_STOP=1 -v db_user="$DB_USER" -v db_password="$DB_PASSWORD" <<'SQL'
DO $do$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = :'db_user') THEN
    EXECUTE format('CREATE ROLE %I LOGIN PASSWORD %L', :'db_user', :'db_password');
  ELSE
    EXECUTE format('ALTER ROLE %I PASSWORD %L', :'db_user', :'db_password');
  END IF;
END
$do$;
SQL
sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'" | grep -q 1 || sudo -u postgres createdb -O "$DB_USER" "$DB_NAME"

rsync -a --delete --exclude .git --exclude node_modules --exclude .next --exclude .env "$APP_ROOT/" "$INSTALL_DIR/"
chown -R root:"$APP_USER" "$INSTALL_DIR"
chmod -R g-w "$INSTALL_DIR"
cd "$INSTALL_DIR"
npm ci --omit=dev
npm run build

if [[ -f agent/requirements.txt ]]; then
  python3 -m venv /opt/rabby-host-agent-venv
  /opt/rabby-host-agent-venv/bin/pip install --quiet -r agent/requirements.txt
  chown -R root:"$AGENT_USER" /opt/rabby-host-agent-venv
fi
[[ -x scripts/health-check.sh ]] || chmod 0755 scripts/health-check.sh
for unit in rabby-host rabby-host-agent rabby-host-worker; do
  [[ -f "$INSTALL_DIR/systemd/$unit.service" ]] || die "missing systemd/$unit.service"
  install -m 0644 "$INSTALL_DIR/systemd/$unit.service" "/etc/systemd/system/$unit.service"
done
systemctl daemon-reload
systemctl enable --now rabby-host-agent rabby-host-worker rabby-host
bash "$INSTALL_DIR/scripts/health-check.sh"
log 'installation completed successfully'
