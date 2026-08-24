#!/bin/sh
set -e
# Atomic deploy script for adguardhome dashboard files (BusyBox sh compatible)
# Usage: sh deploy_atomic.sh /tmp/changes/changes_package
UPLOAD_DIR=${1:-/tmp/changes/changes_package}
if [ ! -d "$UPLOAD_DIR" ]; then
  echo "Usage: $0 <uploaded_package_dir>"
  exit 1
fi
TMPDIR=/tmp/agh_deploy_$$
mkdir -p "$TMPDIR"
# Copy files to tmp then move into place
if [ -f "$UPLOAD_DIR/adguardhome.lua" ]; then
  echo "Deploying controller..."
  mkdir -p "$TMPDIR/usr_lib_lua_luci_controller"
  cp -a "$UPLOAD_DIR/adguardhome.lua" "$TMPDIR/usr_lib_lua_luci_controller/adguardhome.lua"
  mkdir -p /usr/lib/lua/luci/controller
  mv "$TMPDIR/usr_lib_lua_luci_controller/adguardhome.lua" /usr/lib/lua/luci/controller/adguardhome.lua
  chmod 644 /usr/lib/lua/luci/controller/adguardhome.lua
fi
if [ -f "$UPLOAD_DIR/dashboard.js" ]; then
  echo "Deploying dashboard JS..."
  mkdir -p "$TMPDIR/www_luci_static_view_adguardhome"
  cp -a "$UPLOAD_DIR/dashboard.js" "$TMPDIR/www_luci_static_view_adguardhome/dashboard.js"
  mkdir -p /www/luci-static/resources/view/adguardhome
  mv "$TMPDIR/www_luci_static_view_adguardhome/dashboard.js" /www/luci-static/resources/view/adguardhome/dashboard.js
  chmod 644 /www/luci-static/resources/view/adguardhome/dashboard.js
fi
# ensure other aux files (po, changelog) are copied if present
if [ -f "$UPLOAD_DIR/adguardhome.po" ]; then
  mkdir -p /usr/lib/lua/luci/i18n || true
  cp -a "$UPLOAD_DIR/adguardhome.po" /usr/lib/lua/luci/i18n/adguardhome.po || true
fi
# restart services
echo "Restarting rpcd and uhttpd..."
/etc/init.d/rpcd restart || true
/etc/init.d/uhttpd restart || true
# cleanup
rm -rf "$TMPDIR"
sync
echo "Deployment complete"
exit 0
