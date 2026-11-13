#!/bin/sh
set -e

# DumbLG Uninstaller for LG webOS 4.5
# Restores LG Home, unregisters services, removes DumbLG files, leaves backups intact.

HOST_TV="${1:-labfam}"
APP_ID="au.com.kellogs12.dumblg.launcher"
SERVICE_ID="au.com.kellogs12.dumblg.service"
SERVICE_DIR="/media/developer/apps/usr/palm/services/$SERVICE_ID"
APPS_DIR="/media/developer/apps/usr/palm/applications"
APP_DIR="$APPS_DIR/$APP_ID"
INIT_DIR="/var/lib/webosbrew/init.d"
BACKUP_DIR="/home/root/dumbtv-webos-backup"

if [ "$(uname -s)" != "Linux" ]; then
    echo "=== Running DumbLG uninstaller from host machine ==="
    ssh "$HOST_TV" 'sh /home/root/dumblg-uninstall 2>/dev/null || sh /home/root/dumblg-install/uninstall.sh --on-tv'
    echo "=== Uninstallation complete! ==="
    exit 0
fi

echo "=============================================="
echo "    DumbLG webOS 4.5 Uninstaller (On-TV)      "
echo "=============================================="

# 1. Stop background service & relay
echo "[*] Stopping DumbLG service and releasing input grab..."
if [ -f "$SERVICE_DIR/service.pid" ]; then
    pid=$(cat "$SERVICE_DIR/service.pid" 2>/dev/null)
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && \
       grep -q "dumblg.service" "/proc/$pid/cmdline" 2>/dev/null; then
        kill -9 "$pid" 2>/dev/null || true
    fi
    rm -f "$SERVICE_DIR/service.pid"
fi
pkill -9 relay 2>/dev/null || true

# 2. Restore /etc/hosts and clean bind mounts
echo "[*] Restoring /etc/hosts..."
umount /etc/hosts 2>/dev/null || true
rm -f /tmp/hosts 2>/dev/null || true
if [ -f "$BACKUP_DIR/hosts.orig" ]; then
    cp "$BACKUP_DIR/hosts.orig" /etc/hosts 2>/dev/null || true
fi

# 3. Remove init.d hooks (both current and legacy names)
echo "[*] Removing init.d hooks..."
rm -f "$INIT_DIR/50-dumblg-hosts" "$INIT_DIR/80-dumblg-hosts"
rm -f "$INIT_DIR/60-dumblg-removed-apps"
rm -f "$INIT_DIR/70-dumblg-service"
# dumblg-uninstall should live under /home/root/ now; kill any legacy copy too
rm -f "$INIT_DIR/dumblg-uninstall"
rm -f "/home/root/dumblg-uninstall"

# 4. Remove Luna bus registrations
echo "[*] Unregistering Luna Service2 files..."
for ROOT_DIR in /var/luna-service2-dev /var/luna-service2; do
    rm -f "$ROOT_DIR/services.d/$SERVICE_ID.service"
    rm -f "$ROOT_DIR/roles.d/$SERVICE_ID.service.json"
    rm -f "$ROOT_DIR/client-permissions.d/$SERVICE_ID.root.json"
    rm -f "$ROOT_DIR/api-permissions.d/$SERVICE_ID.api.json"
    rm -f "$ROOT_DIR/api-permissions.d/$SERVICE_ID.api.public.json"
    rm -f "$ROOT_DIR/manifests.d/au.com.kellogs12.dumblg.json"
done
ls-control scan-services >/dev/null 2>&1 || true

# 5. Remove App and Service directories
echo "[*] Removing DumbLG launcher and service files..."
rm -rf "$APP_DIR"
rm -f "$APPS_DIR/au.com.kellogs12.dumblg.launcher_*.ipk"
rm -rf "$SERVICE_DIR"
rm -rf /media/developer/apps/usr/palm/applications/com.local.nativehome/state

# 6. Restore LG Home
echo "[*] Restoring LG default Home screen..."
luna-send -n 1 -a com.webos.service.secondscreen.gateway luna://com.webos.applicationManager/launch '{"id":"com.webos.app.home"}' >/dev/null 2>&1 || \
luna-send -n 1 -a com.webos.service.secondscreen.gateway luna://com.webos.applicationManager/launch '{"id":"com.webos.app.fullhome"}' >/dev/null 2>&1 || true

echo ""
echo "=============================================="
echo "       DumbLG Successfully Uninstalled        "
echo " Backups preserved at $BACKUP_DIR"
echo "=============================================="
