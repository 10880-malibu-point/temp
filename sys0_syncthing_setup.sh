#!/usr/bin/env bash
# sys0: install + start syncthing, join the mesh
set -e

# 1 - install if missing
if ! command -v syncthing >/dev/null 2>&1; then
  sudo apt-get update -y
  sudo apt-get install -y syncthing
fi

# 2 - keep it alive after logout / reboot
sudo loginctl enable-linger "$USER"

# 3 - start the user service
systemctl --user enable --now syncthing.service

# 4 - wait for the API to come up
for i in $(seq 1 30); do
  curl -s -o /dev/null http://127.0.0.1:8384 && break
  sleep 2
done

# 5 - show status
K=$(grep -oP '(?<=<apikey>)[^<]+' ~/.config/syncthing/config.xml 2>/dev/null || true)
H="X-API-Key: ${K}"

echo "== device id =="
syncthing -device-id 2>/dev/null || echo "(could not read device id)"

if [ -n "$K" ]; then
  echo "== folders =="
  curl -s -H "$H" http://127.0.0.1:8384/rest/config/folders \
    | python3 -c "import json,sys; [print(f['id'],'->',f['path'], 'paused' if f['paused'] else 'ok') for f in json.load(sys.stdin)]" || true
  echo "== devices =="
  curl -s -H "$H" http://127.0.0.1:8384/rest/config/devices \
    | python3 -c "import json,sys; [print(d['deviceID'][:7], d.get('name','')) for d in json.load(sys.stdin)]" || true
  echo "== connections =="
  curl -s -H "$H" http://127.0.0.1:8384/rest/system/connections \
    | python3 -c "import json,sys; d=json.load(sys.stdin)['connections']; [print(k[:7],'connected' if v['connected'] else 'not connected') for k,v in d.items()]" || true
else
  echo "(fresh config created - open http://127.0.0.1:8384 and accept pending devices)"
fi