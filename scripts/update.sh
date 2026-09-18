#!/usr/bin/env bash
set -Eeuo pipefail
[[ $EUID -eq 0 ]] || { echo 'run as root' >&2; exit 1; }
CONF_DIR=/etc/rabby-host
INSTALL_DIR=/opt/rabby-host
LOG_DIR=/var/log/rabby-host
[[ -f "$CONF_DIR/rabby-host.env" ]] || { echo 'installation not found' >&2; exit 1; }
stamp=$(date -u +%Y%m%d-%H%M%S)
backup="$CONF_DIR/backup-$stamp"
install -d -m 0700 "$backup"
cp -a "$CONF_DIR/rabby-host.env" "$backup/"
rsync -a --delete --exclude .git --exclude node_modules --exclude .next --exclude .env "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/" "$INSTALL_DIR/"
cd "$INSTALL_DIR"
npm ci --omit=dev
set -a; . "$CONF_DIR/rabby-host.env"; set +a
npm run db:migrate 2>"$LOG_DIR/update-migrate-$stamp.log"
npm run build 2>"$LOG_DIR/update-build-$stamp.log"
systemctl restart rabby-host-agent rabby-host-worker rabby-host
systemctl restart rabby-host
bash "$INSTALL_DIR/scripts/health-check.sh"
echo "update completed; configuration backup: $backup"
