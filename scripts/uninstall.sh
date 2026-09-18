#!/usr/bin/env bash
set -Eeuo pipefail
[[ $EUID -eq 0 ]] || { echo 'run as root' >&2; exit 1; }
read -r -p 'Scopes (services application config database data users): ' scopes
[[ -n "$scopes" ]] || exit 1
has(){ [[ " $scopes " == *" $1 "* ]]; }
confirm(){ local phrase=$1 answer; read -r -p "Type '$phrase' to continue: " answer; [[ "$answer" == "$phrase" ]] || exit 1; }
systemctl stop rabby-host rabby-host-worker rabby-host-agent 2>/dev/null || true
if has services; then
  systemctl disable rabby-host rabby-host-worker rabby-host-agent 2>/dev/null || true
  rm -f /etc/systemd/system/rabby-host.service /etc/systemd/system/rabby-host-worker.service /etc/systemd/system/rabby-host-agent.service
  systemctl daemon-reload
fi
if has application; then confirm 'REMOVE APPLICATION'; rm -rf -- /opt/rabby-host /opt/rabby-host-agent-venv; fi
if has config; then confirm 'REMOVE CONFIG'; rm -rf -- /etc/rabby-host; fi
if has database; then confirm 'DROP DATABASE'; sudo -u postgres dropdb --if-exists rabbyhost; sudo -u postgres dropuser --if-exists rabbyhost; fi
if has data; then confirm 'REMOVE DATA'; rm -rf -- /var/lib/rabby-host /var/log/rabby-host; fi
if has users; then userdel rabby 2>/dev/null || true; userdel rabby-agent 2>/dev/null || true; groupdel rabby 2>/dev/null || true; groupdel rabby-agent 2>/dev/null || true; fi
echo 'uninstall completed; /var/www and nginx site configurations were not touched'
