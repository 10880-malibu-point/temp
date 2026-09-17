#!/usr/bin/env bash
# Installer for the Cipher tray chat panel on sys0 (Cinnamon/MATE).
# Run from your desktop session (NOT over SSH without DISPLAY):
#   bash install-cipher-tray.sh
set -euo pipefail

APP_SRC="$1"   # path to cipher-tray.py (already copied to sys0)
APP_DIR="$HOME/.local/share/cipher-tray"
DESKTOP_DIR="$HOME/.config/autostart"
DESKTOP="$DESKTOP_DIR/cipher-tray.desktop"

echo ">> Installing deps..."
sudo apt-get update -qq
sudo apt-get install -y -qq \
  python3-gi \
  gir1.2-gtk-3.0 \
  gir1.2-webkit2-4.1 \
  gir1.2-appindicator3-0.1 \
  >/dev/null

echo ">> Copying app..."
mkdir -p "$APP_DIR"
install -m 0755 "$APP_SRC" "$APP_DIR/cipher-tray.py"

echo ">> Setting up autostart..."
mkdir -p "$DESKTOP_DIR"
cat > "$DESKTOP" <<EOF
[Desktop Entry]
Type=Application
Name=Cipher
Comment=Cipher tray chat panel
Exec=$APP_DIR/cipher-tray.py
Icon=chat
X-GNOME-Autostart-enabled=true
Terminal=false
EOF

echo ">> Done."
echo "Run it now with:  $APP_DIR/cipher-tray.py"
echo "First run: open the Cipher DM once in the panel, then it stays in recents."
echo "To change the direct-DM URL: edit ~/.config/cipher-tray.json  (url field)"
