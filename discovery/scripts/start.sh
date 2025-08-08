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
# noVNC served on 6080 with English language forced
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export LANGUAGE=en_US:en
websockify --web=/usr/share/novnc 6080 localhost:5900 >/var/log/novnc.log 2>&1 &
log "noVNC available at http://localhost:6080 (English interface)"

# 2) Start mitmproxy (port 8080) and mitmweb (port 8081)
log "Starting mitmproxy and mitmweb..."
# Create certs proactively
mitmdump -q -p 8080 --ssl-insecure --set block_global=false >/var/log/mitmdump.log 2>&1 &
sleep 2
mitmweb -q --web-host 0.0.0.0 -p 8081 --set block_global=false >/var/log/mitmweb.log 2>&1 &
log "mitmweb available at http://localhost:8081"

# 3) Start ADB server
log "Starting ADB server..."
adb start-server >/var/log/adb.log 2>&1 || true

# 4) Start Android emulator with proxy to mitmproxy
# Check if KVM is available; use optimized settings for each mode
EMULATOR_ARGS=""
if [ -c /dev/kvm ]; then
	log "KVM device found - using hardware acceleration"
	EMULATOR_ARGS="-accel on -gpu swiftshader_indirect -qemu -m 2048"
else
	log "KVM device not available - using optimized software emulation settings"
	# Use conservative settings for software emulation to avoid hanging
	EMULATOR_ARGS="-accel off -gpu off -qemu -m 2048"
fi

log "Launching Android emulator..."
if [ -c /dev/kvm ]; then
	log "With KVM: Expected boot time ~30-60 seconds"
else
	log "Without KVM: Expected boot time ~3-8 minutes (be patient!)"
fi

# Important flags:
# -writable-system: allow remount /system to install CA
# -http-proxy: force emulator network through mitmproxy (host from emulator is 10.0.2.2)
# -no-audio: disable audio to avoid PulseAudio dependency issues
emulator -avd tapo-avd \
	-no-boot-anim \
	-camera-back none -camera-front none \
	-netdelay none -netspeed full \
	-writable-system \
	-http-proxy http://10.0.2.2:8080 \
	-no-audio \
	${EMULATOR_ARGS} >/var/log/emulator.log 2>&1 &

# 5) Wait for boot with timeout
log "Waiting for device to boot..."
BOOT_TIMEOUT=600  # 10 minutes max for software emulation
BOOT_START=$(date +%s)

# First wait for device to be detected
log "Waiting for emulator to start..."
if ! timeout 120 adb wait-for-device; then
	log "ERROR: Emulator failed to start within 2 minutes"
	log "Check emulator logs: tail /var/log/emulator.log"
	log "Last 50 lines of emulator.log:"
  tail -n 50 /var/log/emulator.log
	exit 1
fi

log "Device detected, waiting for boot completion..."

# Wait for sys.boot_completed=1 with timeout
while true; do
	CURRENT_TIME=$(date +%s)
	ELAPSED=$((CURRENT_TIME - BOOT_START))
	
	if [ $ELAPSED -gt $BOOT_TIMEOUT ]; then
		log "ERROR: Boot timeout after ${BOOT_TIMEOUT} seconds"
		log "This can happen in software emulation mode. Try:"
		log "1. Ensure you have enough free RAM (at least 4GB)"
		log "2. Close other applications to free up CPU"
		log "3. Check emulator logs: tail /var/log/emulator.log"
		log "Last 50 lines of emulator.log:"
    tail -n 50 /var/log/emulator.log
		exit 1
	fi
	
	# Check boot status
	BOOT_STATUS=$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r\n' || echo "")
	if [ "$BOOT_STATUS" = "1" ]; then
		log "Boot completed after ${ELAPSED} seconds"
		break
	fi
	
	# Progress indicator every 30 seconds
	if [ $((ELAPSED % 30)) -eq 0 ] && [ $ELAPSED -gt 0 ]; then
		log "Still booting... ${ELAPSED}s elapsed (timeout in $((BOOT_TIMEOUT - ELAPSED))s)"
	fi
	
	sleep 5
done

# Give more time for ADB daemon to be fully ready after boot
log "Waiting for ADB daemon to be ready..."
sleep 15

# Verify ADB connection is stable before proceeding with robust retry logic
ADB_READY=false
for i in $(seq 1 30); do
	# Check device state specifically
	DEVICE_STATE=$(adb get-state 2>/dev/null || echo "unknown")
	
	if [ "$DEVICE_STATE" = "device" ]; then
		# Double-check with a simple shell command
		if adb shell echo "test" >/dev/null 2>&1; then
			ADB_READY=true
			log "ADB connection verified (attempt $i/30)"
			break
		fi
	fi
	
	log "ADB not ready yet (state: $DEVICE_STATE), waiting... (attempt $i/30)"
	
	# If device is offline, try restarting ADB server
	if [ "$DEVICE_STATE" = "offline" ] && [ $i -eq 10 ]; then
		log "Device offline, restarting ADB server..."
		adb kill-server >/dev/null 2>&1 || true
		sleep 2
		adb start-server >/dev/null 2>&1 || true
		sleep 3
	fi
	
	sleep 2
done

if [ "$ADB_READY" = "false" ]; then
	log "ERROR: ADB connection failed after boot completion"
	log "Final device state check:"
	adb devices
	FINAL_STATE=$(adb get-state 2>/dev/null || echo "unknown")
	log "Device state: $FINAL_STATE"
	
	# Try one more ADB server restart as last resort
	log "Attempting final ADB server restart..."
	adb kill-server >/dev/null 2>&1 || true
	sleep 3
	adb start-server >/dev/null 2>&1 || true
	sleep 5
	
	# Final check
	if adb shell echo "test" >/dev/null 2>&1; then
		log "ADB connection recovered after server restart"
		ADB_READY=true
	else
		log "ADB connection still failed. Device may need more time to stabilize."
		exit 1
	fi
fi

# 6) Root & remount, install mitm CA into system store
log "Enabling root and installing mitmproxy CA into system trust store..."

# Enable root access (this restarts ADB daemon on device, causing temporary disconnection)
if adb root >/dev/null 2>&1; then
	log "Root access enabled, waiting for ADB daemon to restart..."
	
	# Wait for device to reconnect after root access
	if ! timeout 60 adb wait-for-device; then
		log "ERROR: Device failed to reconnect after enabling root access"
		adb devices
		exit 1
	fi
	
	# Verify ADB connection is stable after root
	ROOT_ADB_READY=false
	for i in $(seq 1 15); do
		DEVICE_STATE=$(adb get-state 2>/dev/null || echo "unknown")
		
		if [ "$DEVICE_STATE" = "device" ]; then
			if adb shell echo "test" >/dev/null 2>&1; then
				ROOT_ADB_READY=true
				log "ADB connection verified after root access (attempt $i/15)"
				break
			fi
		fi
		
		log "ADB not ready after root (state: $DEVICE_STATE), waiting... (attempt $i/15)"
		sleep 2
	done
	
	if [ "$ROOT_ADB_READY" = "false" ]; then
		log "ERROR: ADB connection failed after enabling root access"
		adb devices
		exit 1
	fi
	
	# Now try to remount system partition
	if ! adb remount >/dev/null 2>&1; then
		log "WARNING: Failed to remount system partition. This may be expected on some emulator versions."
	fi
else
	log "WARNING: Failed to enable root access. Device may have restarted - waiting for reconnection..."
	
	# Wait for device to come back online in case adb root caused a restart
	if ! timeout 60 adb wait-for-device; then
		log "ERROR: Device failed to reconnect after failed root attempt"
		adb devices
		exit 1
	fi
	
	# Wait for ADB connection to stabilize
	NOROOT_ADB_READY=false
	for i in $(seq 1 15); do
		DEVICE_STATE=$(adb get-state 2>/dev/null || echo "unknown")
		
		if [ "$DEVICE_STATE" = "device" ]; then
			if adb shell echo "test" >/dev/null 2>&1; then
				NOROOT_ADB_READY=true
				log "ADB connection verified after failed root attempt (attempt $i/15)"
				break
			fi
		fi
		
		log "ADB not ready after failed root (state: $DEVICE_STATE), waiting... (attempt $i/15)"
		sleep 2
	done
	
	if [ "$NOROOT_ADB_READY" = "false" ]; then
		log "ERROR: ADB connection failed after root attempt"
		adb devices
		exit 1
	fi
	
	# Now check device properties
	log "Checking device status..."
	adb devices
	DEBUGGABLE=$(adb shell getprop ro.debuggable 2>/dev/null || echo "unknown")
	log "Device debuggable property: $DEBUGGABLE"
	
	# Check if this is a Google Play image (which doesn't support root)
	BUILD_TYPE=$(adb shell getprop ro.build.type 2>/dev/null || echo "unknown")
	log "Build type: $BUILD_TYPE"
	
	if [ "$BUILD_TYPE" = "user" ]; then
		log "ERROR: This appears to be a production/user build that doesn't support root access"
		log "Make sure the emulator is using Google APIs image, not Google Play image"
		exit 1
	else
		log "Continuing without root access (certificate installation may fail)..."
	fi
fi

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
log "Waiting for reboot to complete..."
if ! timeout 300 adb wait-for-device; then
	log "ERROR: Emulator failed to reboot within 5 minutes"
	exit 1
fi

# Wait for boot completion after reboot
REBOOT_START=$(date +%s)
while true; do
	CURRENT_TIME=$(date +%s)
	ELAPSED=$((CURRENT_TIME - REBOOT_START))
	
	if [ $ELAPSED -gt 300 ]; then  # 5 minute timeout for reboot
		log "ERROR: Reboot timeout after 5 minutes"
		exit 1
	fi
	
	BOOT_STATUS=$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r\n' || echo "")
	if [ "$BOOT_STATUS" = "1" ]; then
		log "Reboot completed after ${ELAPSED} seconds"
		break
	fi
	
	if [ $((ELAPSED % 30)) -eq 0 ] && [ $ELAPSED -gt 0 ]; then
		log "Still rebooting... ${ELAPSED}s elapsed"
	fi
	
	sleep 5
done
sleep 5

# Re-verify ADB connection after reboot
log "Verifying ADB connection after reboot..."
ADB_READY_REBOOT=false
for i in $(seq 1 20); do
	DEVICE_STATE=$(adb get-state 2>/dev/null || echo "unknown")
	
	if [ "$DEVICE_STATE" = "device" ]; then
		if adb shell echo "test" >/dev/null 2>&1; then
			ADB_READY_REBOOT=true
			log "ADB connection verified after reboot (attempt $i/20)"
			break
		fi
	fi
	
	log "ADB not ready after reboot (state: $DEVICE_STATE), waiting... (attempt $i/20)"
	sleep 2
done

if [ "$ADB_READY_REBOOT" = "false" ]; then
	log "WARNING: ADB connection issues after reboot, but continuing..."
	adb devices
fi

# 8) Re-enable root after reboot
log "Re-enabling root access after reboot..."
if adb root >/dev/null 2>&1; then
	log "Root access re-enabled, waiting for ADB daemon to restart..."
	
	# Wait for device to reconnect after root access
	if ! timeout 60 adb wait-for-device; then
		log "WARNING: Device failed to reconnect after re-enabling root access"
		adb devices
	else
		# Quick verification that root is working
		sleep 2
		if adb shell echo "test" >/dev/null 2>&1; then
			log "Root access verified after reboot"
		else
			log "WARNING: Root access may not be working properly after reboot"
		fi
	fi
else
	log "WARNING: Failed to re-enable root access after reboot"
fi
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
log "Inspect traffic:       http://localhost:8081 (mitmweb interface)"
log "Proxy inside emulator: 10.0.2.2:8080 (mitmproxy - for emulator only, not web UI)"
log "Frida is running on the device. Example (in another shell inside container):"
log "  frida -U -f com.tplink.tapo -l /tools/repin.js --no-pause"

# Keep container alive and tail useful logs
touch /var/log/mitmdump.log /var/log/emulator.log
tail -n +1 -F /var/log/mitmdump.log /var/log/mitmweb.log /var/log/emulator.log /var/log/adb.log /var/log/x11vnc.log /var/log/novnc.log
