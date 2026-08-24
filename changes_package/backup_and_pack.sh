#!/bin/sh
set -e

# Backup current installed files and move uploaded new files into place.
# Usage on router: run this script from the uploaded directory or place files in /tmp/changes and run as root.

# Determine directory containing this script; use it as upload dir if present
SCRIPT_DIR="$(cd "$(dirname "$0")" >/dev/null 2>&1 && pwd)"
if [ -d "$SCRIPT_DIR" ] && [ "$(ls -A "$SCRIPT_DIR")" ]; then
  UPLOAD_DIR="$SCRIPT_DIR"
else
  UPLOAD_DIR="/tmp/changes"
fi

BACKUP_DIR="/root/agh_backup_$(date +%s)"

echo "Backup dir: $BACKUP_DIR"
mkdir -p "$BACKUP_DIR"

# Files to replace (space-separated, POSIX-compatible)
FILES="/usr/lib/lua/luci/controller/adguardhome.lua /www/luci-static/resources/view/adguardhome/dashboard.js"

# Backup existing files if present
for f in $FILES; do
  if [ -f "$f" ]; then
    echo "Backing up $f"
    cp -a "$f" "$BACKUP_DIR/"
  fi
done

# Move uploaded files into place
if [ -d "$UPLOAD_DIR" ]; then
  echo "Installing uploaded files from $UPLOAD_DIR"

  if [ -f "$UPLOAD_DIR/adguardhome.lua" ]; then
    mkdir -p /usr/lib/lua/luci/controller || true
    cp -a "$UPLOAD_DIR/adguardhome.lua" /usr/lib/lua/luci/controller/adguardhome.lua
    chmod 644 /usr/lib/lua/luci/controller/adguardhome.lua || true
  fi

  if [ -f "$UPLOAD_DIR/dashboard.js" ]; then
    mkdir -p /www/luci-static/resources/view/adguardhome || true
    cp -a "$UPLOAD_DIR/dashboard.js" /www/luci-static/resources/view/adguardhome/dashboard.js
    chmod 644 /www/luci-static/resources/view/adguardhome/dashboard.js || true
  fi

  # Restart services (best-effort)
  /etc/init.d/rpcd restart || true
  /etc/init.d/uhttpd restart || true

  echo "Deployment complete"
else
  echo "No upload dir $UPLOAD_DIR found"
  exit 1
fi
