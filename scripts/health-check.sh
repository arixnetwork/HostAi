#!/usr/bin/env bash
set -Eeuo pipefail
CONF_DIR=/etc/rabby-host
fail=0
ok(){ printf '[ OK ] %s\n' "$*"; }
crit(){ printf '[CRIT] %s\n' "$*"; fail=$((fail+1)); }
service(){ systemctl is-active --quiet "$1" && ok "$1 active" || crit "$1 inactive"; }
[[ -r "$CONF_DIR/rabby-host.env" ]] || crit "missing $CONF_DIR/rabby-host.env"
for s in postgresql redis-server nginx rabby-host-agent rabby-host-worker rabby-host; do service "$s"; done
if command -v nginx >/dev/null && nginx -t >/dev/null 2>&1; then ok 'nginx configuration valid'; else crit 'nginx configuration invalid'; fi
if command -v curl >/dev/null; then
  code=$(curl -fsS -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:8417/health || true)
  [[ "$code" =~ ^2 ]] && ok "agent health ($code)" || crit "agent health unavailable ($code)"
fi
for d in /opt/rabby-host /etc/rabby-host /var/lib/rabby-host /var/log/rabby-host; do [[ -d "$d" ]] && ok "$d exists" || crit "$d missing"; done
if [[ -f "$CONF_DIR/rabby-host.env" ]]; then
  [[ "$(stat -c '%U:%a' "$CONF_DIR/rabby-host.env")" == root:640 ]] && ok 'environment permissions are 0640 root-owned' || crit 'environment permissions are unsafe'
fi
used=$(df -P / | awk 'NR==2 {gsub(/%/,"",$5); print $5}')
(( used < 90 )) && ok "disk usage ${used}%" || crit "disk usage ${used}%"
printf 'Result: %d critical failures\n' "$fail"
(( fail == 0 ))
