#!/usr/bin/env bash
set -euo pipefail

# Tabs for indentation per user preference

log() {
	echo "[startup] $*"
}

# Ensure environment
export ANDROID_HOME="${ANDROID_HOME:-/opt/android-sdk}"
export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-/opt/android-sdk}"
export ANDROID_AVD_HOME="${ANDROID_AVD_HOME:-/root/.android/avd}"
export PATH="$PATH:${ANDROID_HOME}/emulator:${ANDROID_HOME}/platform-tools:${ANDROID_HOME}/cmdline-tools/latest/bin"
export DISPLAY=:0

# 1) Start X stack and noVNC
log "Starting Xvfb, Fluxbox, x11vnc, and noVNC..."
Xvfb :0 -screen 0 1280x800x24 -ac +extension RANDR >/var/log/xvfb.log 2>&1 &
sleep 1
fluxbox >/var/log/fluxbox.log 2>&1 &
sleep 1
# x11vnc listens on localhost:5900; novnc will proxy to it
x11vnc -display :0 -nopw -forever -shared -rfbport 5900 >/var/log/x11vnc.log 2>&1 &
sleep 1
# noVNC served on 6080
websockify --web=/usr/share/novnc 6080 localhost:5900 >/var/log/novnc.log 2>&1 &
log "noVNC available at http://localhost:6080"

# 2) Start mitmproxy (port 8080) and mitmweb (port 8081)
log "Starting mitmproxy and mitmweb..."
# Create certs proactively
mitmdump -q -p 8080 --ssl-insecure --set block_global=false >/var/log/mitmdump.log 2>&1 &
sleep 2
mitmweb -q -p 8081 --set block_global=false >/var/log/mitmweb.log 2>&1 &
log "mitmweb available at http://localhost:8081"

# 3) Start ADB server
log "Starting ADB server..."
adb start-server >/var/log/adb.log 2>&1 || true

# 4) Start Android emulator with proxy to mitmproxy
# Use KVM from host: ensure container started with --device /dev/kvm
log "Launching Android emulator (this can take ~30-60s)..."
# Important flags:
# -writable-system: allow remount /system to install CA
# -http-proxy: force emulator network through mitmproxy (host from emulator is 10.0.2.2)
emulator -avd tapo-avd \
	-no-boot-anim \
	-gpu swiftshader_indirect \
	-camera-back none -camera-front none \
	-netdelay none -netspeed full \
	-writable-system \
	-http-proxy http://10.0.2.2:8080 \
	-qemu -m 2048 >/var/log/emulator.log 2>&1 &

# 5) Wait for boot
log "Waiting for device to boot..."
adb wait-for-device
# Wait for sys.boot_completed=1
until adb shell getprop sys.boot_completed 2>/dev/null | grep -q "1"; do
	sleep 1
done
# Give a bit more time for settings provider to be ready
sleep 3

# 6) Root & remount, install mitm CA into system store
log "Enabling root and installing mitmproxy CA into system trust store..."
adb root >/dev/null 2>&1 || true
sleep 1
adb remount >/dev/null 2>&1 || true
sleep 1

# Ensure mitm CA exists
MITM_DIR="/root/.mitmproxy"
MITM_PEM="${MITM_DIR}/mitmproxy-ca-cert.pem"
MITM_DER="/tmp/mitmproxy-ca-cert.der"
if [ ! -f "${MITM_PEM}" ]; then
	log "Waiting for mitmproxy to generate certificates..."
	# mitmproxy generates certs on first run; mitmdump was already started
	for i in $(seq 1 30); do
		[ -f "${MITM_PEM}" ] && break
		sleep 1
	done
fi

if [ -f "${MITM_PEM}" ]; then
	# Compute subject hash for Android cacerts filename
	HASH="$(openssl x509 -subject_hash_old -in "${MITM_PEM}" -noout)"
	openssl x509 -in "${MITM_PEM}" -outform DER -out "${MITM_DER}"
	adb push "${MITM_DER}" "/system/etc/security/cacerts/${HASH}.0" >/dev/null
	adb shell "chmod 644 /system/etc/security/cacerts/${HASH}.0" >/dev/null
	log "Installed mitmproxy CA as /system/etc/security/cacerts/${HASH}.0"
else
	log "WARNING: mitmproxy CA PEM not found; HTTPS intercept may fail."
fi

# 7) Reboot to apply system CA changes
log "Rebooting emulator to apply system CA..."
adb reboot
adb wait-for-device
until adb shell getprop sys.boot_completed 2>/dev/null | grep -q "1"; do
	sleep 1
done
sleep 3

# 8) Re-enable root after reboot
adb root >/dev/null 2>&1 || true
sleep 1

# 9) Confirm/force HTTP proxy via settings too (belt and suspenders)
adb shell settings put global http_proxy "10.0.2.2:8080" || true

# 10) Start Frida server inside emulator
log "Starting frida-server inside emulator..."
adb push /tools/frida-server /data/local/tmp/frida-server >/dev/null
adb shell "chmod 755 /data/local/tmp/frida-server"
# Start frida-server in background on device
adb shell "/data/local/tmp/frida-server >/dev/null 2>&1 &"

# 11) Auto-install APKs from /apks (optional)
if ls /apks/*.apk >/dev/null 2>&1; then
	log "Installing APKs from /apks..."
	for apk in /apks/*.apk; do
		log "Installing: ${apk}"
		adb install -r "${apk}" || true
	done
fi

log "Setup complete."
log "Access emulator UI:    http://localhost:6080"
log "Inspect traffic:       http://localhost:8081"
log "Proxy inside emulator: 10.0.2.2:8080 (mitmproxy)"
log "Frida is running on the device. Example (in another shell inside container):"
log "  frida -U -f com.tplink.tapo -l /tools/repin.js --no-pause"

# Keep container alive and tail useful logs
touch /var/log/mitmdump.log /var/log/emulator.log
tail -n +1 -F /var/log/mitmdump.log /var/log/mitmweb.log /var/log/emulator.log /var/log/adb.log /var/log/x11vnc.log /var/log/novnc.log
