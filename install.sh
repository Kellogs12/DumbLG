#!/bin/sh
set -e

# DumbLG Installer for LG webOS 4.5
# Supports running directly on TV or from a dev machine over SSH.

HOST_TV="${1:-labfam}"
APP_ID="au.com.kellogs12.dumblg.launcher"
VERSION="0.1.0"
IPK_FILE="${APP_ID}_${VERSION}_all.ipk"
SERVICE_ID="au.com.kellogs12.dumblg.service"
SERVICE_DIR="/media/developer/apps/usr/palm/services/$SERVICE_ID"
APPS_DIR="/media/developer/apps/usr/palm/applications"
APP_DIR="$APPS_DIR/$APP_ID"
INIT_DIR="/var/lib/webosbrew/init.d"
BACKUP_DIR="/home/root/dumbtv-webos-backup"

# Detect if running on dev Mac / host or on the TV itself
if [ "$(uname -s)" != "Linux" ]; then
    echo "=== Running DumbLG installer from host machine ==="
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    cd "$SCRIPT_DIR"

    echo "[1/4] Building launcher IPK..."
    if [ ! -f "dist/$IPK_FILE" ]; then
        python3 package-launcher.py
    fi

    echo "[2/4] Testing SSH connection to $HOST_TV..."
    ssh -o ConnectTimeout=5 "$HOST_TV" 'uname -a' >/dev/null

    echo "[3/4] Uploading installer and payload to TV..."
    ssh "$HOST_TV" 'mkdir -p /home/root/dumblg-install'
    scp -r dist "$SCRIPT_DIR/service" "$SCRIPT_DIR/install.sh" "$SCRIPT_DIR/uninstall.sh" "$HOST_TV:/home/root/dumblg-install/"

    echo "[4/4] Executing on-device installation..."
    ssh "$HOST_TV" 'cd /home/root/dumblg-install && sh install.sh --on-tv'
    echo "=== Installation completed successfully! ==="
    exit 0
fi

# --- On-Device Installation Steps ---
echo "=============================================="
echo "      DumbLG webOS 4.5 Installer (On-TV)     "
echo "=============================================="

# 1. Backups
mkdir -p "$BACKUP_DIR"
if [ ! -f "$BACKUP_DIR/hosts.orig" ]; then
    echo "[*] Creating backup of original /etc/hosts..."
    cp /etc/hosts "$BACKUP_DIR/hosts.orig" 2>/dev/null || true
fi

# 2. Extract / Install Launcher App
echo "[*] Installing DumbLG launcher application..."
mkdir -p "$APPS_DIR"
IPK_PATH="dist/$IPK_FILE"
if [ ! -f "$IPK_PATH" ] && [ -f "$IPK_FILE" ]; then
    IPK_PATH="$IPK_FILE"
fi

if [ -f "$IPK_PATH" ]; then
    cp "$IPK_PATH" "$APPS_DIR/$IPK_FILE"
    echo "    Dropped $IPK_FILE into $APPS_DIR"
    # Install via luna appInstallService
    luna-send -n 1 -a com.webos.service.secondscreen.gateway luna://com.webos.appInstallService/dev/install "{\"id\":\"$APP_ID\",\"ipkUrl\":\"$APPS_DIR/$IPK_FILE\"}" >/dev/null 2>&1 || true
fi

# Ensure unpacked directory is populated
if [ ! -f "$APP_DIR/appinfo.json" ] && [ -f "$APPS_DIR/$IPK_FILE" ]; then
    echo "    Extracting IPK contents to $APP_DIR..."
    TMP_DIR="/tmp/dumblg-unpack-$$"
    mkdir -p "$TMP_DIR"
    (
        cd "$TMP_DIR"
        ar x "$APPS_DIR/$IPK_FILE" data.tar.gz
        tar -zxf data.tar.gz -C /media/developer/apps/
    )
    rm -rf "$TMP_DIR"
fi

# 3. Install Background Service
echo "[*] Installing DumbLG background supervisor service..."
# Stop existing running service / relay so binary is not busy
if [ -f "$SERVICE_DIR/service.pid" ]; then
    kill -9 "$(cat "$SERVICE_DIR/service.pid")" 2>/dev/null || true
fi
pkill -9 relay 2>/dev/null || true
rm -f "$SERVICE_DIR/bin/relay" 2>/dev/null || true

mkdir -p "$SERVICE_DIR"
if [ -d "service" ]; then
    cp -r service/* "$SERVICE_DIR/"
fi
chmod +x "$SERVICE_DIR/run-js-service" 2>/dev/null || true
chmod +x "$SERVICE_DIR/bin/relay" 2>/dev/null || true

# Prepare state dir
STATE_DIR="$SERVICE_DIR/state"
LEGACY_STATE_DIR="/media/developer/apps/usr/palm/applications/com.local.nativehome/state"
mkdir -p "$STATE_DIR"
mkdir -p "$(dirname "$LEGACY_STATE_DIR")"
rm -f "$LEGACY_STATE_DIR" 2>/dev/null || true
ln -s "$STATE_DIR" "$LEGACY_STATE_DIR" 2>/dev/null || true
rm -f "$STATE_DIR/relay.lock" "$STATE_DIR/watchdog" "$STATE_DIR/blocked" 2>/dev/null || true

# 4. Register with Luna Service Bus
echo "[*] Registering Luna Service2 permissions and roles..."
for ROOT_DIR in /var/luna-service2-dev /var/luna-service2; do
    mkdir -p "$ROOT_DIR/services.d" "$ROOT_DIR/roles.d" "$ROOT_DIR/client-permissions.d" "$ROOT_DIR/api-permissions.d" "$ROOT_DIR/manifests.d"

    cat << EOF > "$ROOT_DIR/services.d/$SERVICE_ID.service"
[D-BUS Service]
Name=$SERVICE_ID
Exec=$SERVICE_DIR/run-js-service -k -n $SERVICE_DIR
Type=dynamic
EOF

    cat << EOF > "$ROOT_DIR/roles.d/$SERVICE_ID.service.json"
{
    "appId": "$SERVICE_ID",
    "type": "regular",
    "allowedNames": ["$SERVICE_ID", "*"],
    "permissions": [
        {"service": "$SERVICE_ID", "outbound": ["*"]},
        {"service": "*", "inbound": ["*"], "outbound": ["*"]}
    ]
}
EOF

    cat << EOF > "$ROOT_DIR/client-permissions.d/$SERVICE_ID.root.json"
{
    "$SERVICE_ID*": ["all"]
}
EOF

    cat << EOF > "$ROOT_DIR/api-permissions.d/$SERVICE_ID.api.public.json"
{
    "public": ["$SERVICE_ID/*"]
}
EOF

    cat << EOF > "$ROOT_DIR/api-permissions.d/$SERVICE_ID.api.json"
{
    "$SERVICE_ID.group": ["$SERVICE_ID/*"],
    "ares.webos.cli": ["$SERVICE_ID/*"]
}
EOF

    cat << EOF > "$ROOT_DIR/manifests.d/au.com.kellogs12.dumblg.json"
{
    "id": "au.com.kellogs12.dumblg",
    "version": "$VERSION",
    "serviceFiles": ["$ROOT_DIR/services.d/$SERVICE_ID.service"],
    "roleFiles": ["$ROOT_DIR/roles.d/$SERVICE_ID.service.json"],
    "clientPermissionFiles": ["$ROOT_DIR/client-permissions.d/$SERVICE_ID.root.json"],
    "apiPermissionFiles": [
        "$ROOT_DIR/api-permissions.d/$SERVICE_ID.api.json",
        "$ROOT_DIR/api-permissions.d/$SERVICE_ID.api.public.json"
    ]
}
EOF
done

ls-control scan-services >/dev/null 2>&1 || true

# 5. Install init.d hooks
echo "[*] Installing init.d boot hooks..."
mkdir -p "$INIT_DIR"

# 50-dumblg-hosts
cat << 'EOF' > "$INIT_DIR/50-dumblg-hosts"
#!/bin/sh
# Appends DUMBTV ad/ACR/Amazon blocks to /etc/hosts
if ! mount | grep -q " on /etc/hosts "; then
    cp /etc/hosts /tmp/hosts
    mount --bind /tmp/hosts /etc/hosts
fi

if grep -q "DUMBTV-WEBOS-BLOCKLIST" /etc/hosts; then
    exit 0
fi

cat >> /etc/hosts << 'HOSTS'

# --- DUMBTV-WEBOS-BLOCKLIST ---
127.0.0.1 ad.lgappstv.com lgsmartad.com ngfts.lgsmartad.com
127.0.0.1 ibis.lgappstv.com us.ibs.lgappstv.com kr.ibs.lgappstv.com
127.0.0.1 eic.lgtvsdp.com ad.lgsmartserver.com smartshare.lgtvsdp.com
127.0.0.1 livepluszz.lgtvsdp.com lgacr.com
127.0.0.1 info.lgsmartad.com kr.info.lgsmartad.com ca.info.lgsmartad.com
127.0.0.1 rdx2.lgtvsdp.com lgnoti.lgtvsdp.com kr.lgtvsdp.com
127.0.0.1 kr.coredata.lgsmartserver.com us.coredata.lgsmartserver.com
127.0.0.1 softwareupdates.amazon.com arcus-uswest.amazon.com
127.0.0.1 unagi-na.amazon.com api.amazonalexa.com
HOSTS
EOF
chmod +x "$INIT_DIR/50-dumblg-hosts"

# 60-dumblg-removed-apps
cat << 'EOF' > "$INIT_DIR/60-dumblg-removed-apps"
#!/bin/sh
# Re-removes bloat apps on boot and after 60s
APPS="com.pplus.webapp.prod-intl com.disney.disneyplus-prod com.streamotion.binge com.foxtel.app stan.webos2 com.apple.appletv com.streamotion.kayosports au.com.optus.sport.lgtv tv.twitch.tv.starshot.lg googleplaymovieswebos"
remove() {
    for a in $APPS; do
        rm -rf /media/cryptofs/apps/usr/palm/applications/$a 2>/dev/null
        rm -rf /media/cryptofs/apps/usr/palm/services/${a}.* 2>/dev/null
    done
}
remove
( sleep 60; remove ) &
EOF
chmod +x "$INIT_DIR/60-dumblg-removed-apps"

# 70-dumblg-service
cat << EOF > "$INIT_DIR/70-dumblg-service"
#!/bin/sh
SERVICE_DIR="$SERVICE_DIR"
PIDFILE="\$SERVICE_DIR/service.pid"

if [ -f "\$PIDFILE" ]; then
    kill -9 "\$(cat "\$PIDFILE")" 2>/dev/null || true
    rm -f "\$PIDFILE"
fi

if [ -x "\$SERVICE_DIR/run-js-service" ]; then
    nohup "\$SERVICE_DIR/run-js-service" -k -n "\$SERVICE_DIR" > /var/log/dumblg-service.log 2>&1 &
fi
EOF
chmod +x "$INIT_DIR/70-dumblg-service"

# Copy uninstaller to init.d
if [ -f "uninstall.sh" ]; then
    cp "uninstall.sh" "$INIT_DIR/dumblg-uninstall"
    chmod +x "$INIT_DIR/dumblg-uninstall"
fi

# Clean up older init.d scripts with older names if present
rm -f "$INIT_DIR/50-dumbtv-hosts" "$INIT_DIR/60-dumbtv-removed-apps" 2>/dev/null || true

# 6. Apply settings and debloat right now
echo "[*] Applying hosts blocklist..."
sh "$INIT_DIR/50-dumblg-hosts"

echo "[*] Removing streaming bloatware apps..."
sh "$INIT_DIR/60-dumblg-removed-apps"

echo "[*] Starting DumbLG supervisor service..."
sh "$INIT_DIR/70-dumblg-service"
sleep 2

# 7. Launch DumbLG Home
echo "[*] Launching DumbLG Home..."
luna-send -n 1 -a com.webos.service.secondscreen.gateway luna://com.webos.applicationManager/launch "{\"id\":\"$APP_ID\"}" >/dev/null 2>&1 || true

echo ""
echo "=============================================="
echo "        DumbLG Installed Successfully!        "
echo "=============================================="
echo "Active init.d scripts:"
ls -la "$INIT_DIR"
echo ""
echo "Service status:"
luna-send -n 1 -a com.webos.service.secondscreen.gateway "luna://$SERVICE_ID/status" "{}" 2>/dev/null || echo "Service started in background"
echo ""
echo "To uninstall anytime, run:"
echo "  sh $INIT_DIR/dumblg-uninstall"
echo "=============================================="
