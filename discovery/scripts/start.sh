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
# -selinux permissive: disable SELinux enforcement to enable root access
# -qemu -append: pass kernel parameters for permissive SELinux
emulator -avd tapo-avd \
	-no-boot-anim \
	-camera-back none -camera-front none \
	-netdelay none -netspeed full \
	-writable-system \
	-http-proxy http://10.0.2.2:8080 \
	-no-audio \
	-selinux permissive \
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

# 6) Root & remount, install mitm CA into system store (REQUIRED)
log "Enabling root and installing mitmproxy CA into system trust store..."

# Track whether we have system write access
SYSTEM_WRITABLE=false
CERT_INSTALLED=false

# Enable root access (this restarts ADB daemon on device, causing temporary disconnection)
log "Attempting to enable root access..."
if adb root >/dev/null 2>&1; then
	log "Root access enabled, waiting for ADB daemon to restart..."
	
	# Wait for device to reconnect after root access
	if ! timeout 60 adb wait-for-device; then
		log "ERROR: Device failed to reconnect after enabling root access"
		log "This indicates a critical emulator configuration issue"
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
	if adb remount >/dev/null 2>&1; then
		log "System partition remounted as writable"
		SYSTEM_WRITABLE=true
	else
		log "ERROR: Failed to remount system partition even with root access"
		log "This is a critical failure - root access is required for this container"
		exit 1
	fi
else
	log "ERROR: Failed to enable root access on emulator"
	log "Root access is REQUIRED for certificate installation and traffic interception"
	
	# Check device properties for troubleshooting
	log "Device diagnostics:"
	adb devices
	DEBUGGABLE=$(adb shell getprop ro.debuggable 2>/dev/null || echo "unknown")
	BUILD_TYPE=$(adb shell getprop ro.build.type 2>/dev/null || echo "unknown") 
	SECURE=$(adb shell getprop ro.secure 2>/dev/null || echo "unknown")
	log "- ro.debuggable: $DEBUGGABLE"
	log "- ro.build.type: $BUILD_TYPE"
	log "- ro.secure: $SECURE"
	
	if [ "$BUILD_TYPE" = "user" ]; then
		log "ERROR: Production/user build detected - root access not supported"
		log "Ensure the emulator uses Google APIs image, not Google Play image"
	elif [ "$SECURE" = "1" ]; then
		log "ERROR: Device security settings prevent root access"
		log "This may indicate SELinux enforcement or other security policies"
	else
		log "ERROR: Root access failed for unknown reasons"
		log "Check emulator logs for more details: tail /var/log/emulator.log"
		log "Last 50 lines of emulator.log:"
    tail -n 50 /var/log/emulator.log
	fi
	
	log "SOLUTION: This container requires root access to function properly."
	log "If the issue persists, try rebuilding the image or checking emulator configuration."
	exit 1
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
	
	# Install system certificate (we have guaranteed root access)
	log "Installing mitmproxy CA certificate to system trust store..."
	
	# First check if the cacerts directory exists and create if needed
	CACERTS_DIR="/system/etc/security/cacerts"
	if ! adb shell "test -d ${CACERTS_DIR}" >/dev/null 2>&1; then
		log "Creating cacerts directory: ${CACERTS_DIR}"
		if ! adb shell "mkdir -p ${CACERTS_DIR}" >/dev/null 2>&1; then
			log "ERROR: Failed to create cacerts directory"
			log "Debug: Checking system partition mount status..."
			adb shell "mount | grep system"
			adb shell "ls -la /system/etc/security/"
			exit 1
		fi
	fi
	
	# Set proper permissions on cacerts directory
	adb shell "chmod 755 ${CACERTS_DIR}" >/dev/null 2>&1 || true
	
	# Install the certificate
	CERT_PATH="${CACERTS_DIR}/${HASH}.0"
	log "Installing certificate as ${CERT_PATH}"
	
	# Enhanced diagnostics before attempting certificate installation
	log "Pre-installation diagnostics:"
	log "- Local certificate file: ${MITM_DER}"
	if [ -f "${MITM_DER}" ]; then
		log "- Local cert file size: $(stat -c%s ${MITM_DER}) bytes"
		log "- Local cert file permissions: $(stat -c%a ${MITM_DER})"
	else
		log "ERROR: Local certificate file ${MITM_DER} does not exist"
		exit 1
	fi
	log "- Target certificate path: ${CERT_PATH}"
	log "- Certificate hash: ${HASH}"
	
	# Verify ADB connection is still stable before certificate operation
	log "Verifying ADB connection stability before certificate installation..."
	DEVICE_STATE=$(adb get-state 2>/dev/null || echo "unknown")
	if [ "$DEVICE_STATE" != "device" ]; then
		log "ERROR: Device not ready for certificate installation (state: $DEVICE_STATE)"
		adb devices
		exit 1
	fi
	
	# Test basic shell command to ensure device is responsive
	if ! adb shell "echo 'connection_test'" >/dev/null 2>&1; then
		log "ERROR: Device not responding to shell commands"
		adb devices
		exit 1
	fi
	log "ADB connection verified - device is responsive"
	
	# Check if target certificate already exists
	if adb shell "test -f ${CERT_PATH}" >/dev/null 2>&1; then
		log "WARNING: Certificate ${CERT_PATH} already exists, removing it first"
		adb shell "rm -f ${CERT_PATH}" >/dev/null 2>&1 || true
	fi
	
	# Try the certificate installation with detailed error reporting and timeout
	log "Attempting certificate push (timeout: 60 seconds)..."
	
	# Start the push command in background with timeout and show progress
	(
		sleep 10 && echo "[startup] Certificate push in progress (10s)..." >&2
		sleep 20 && echo "[startup] Certificate push in progress (30s)..." >&2
		sleep 20 && echo "[startup] Certificate push in progress (50s)..." >&2
	) &
	PROGRESS_PID=$!
	
	PUSH_OUTPUT=$(timeout 60 adb push "${MITM_DER}" "${CERT_PATH}" 2>&1)
	PUSH_RESULT=$?
	
	# Kill progress indicator
	kill $PROGRESS_PID 2>/dev/null || true
	wait $PROGRESS_PID 2>/dev/null || true
	
	# Check if command timed out
	if [ $PUSH_RESULT -eq 124 ]; then
		log "ERROR: Certificate push timed out after 60 seconds"
		log "This suggests ADB connection issues or device unresponsiveness"
		log "Checking device status..."
		adb devices
		DEVICE_STATE=$(adb get-state 2>/dev/null || echo "unknown")
		log "Device state: $DEVICE_STATE"
		exit 1
	fi
	
	if [ $PUSH_RESULT -eq 0 ]; then
		log "Certificate push successful: $PUSH_OUTPUT"
		if adb shell "chmod 644 ${CERT_PATH}" >/dev/null 2>&1; then
			log "Successfully installed mitmproxy CA as ${CERT_PATH}"
			# Verify the certificate was actually installed
			if adb shell "test -f ${CERT_PATH}" >/dev/null 2>&1; then
				INSTALLED_SIZE=$(adb shell "stat -c%s ${CERT_PATH}" 2>/dev/null | tr -d '\r\n')
				LOCAL_SIZE=$(stat -c%s ${MITM_DER})
				log "Certificate verification: local=${LOCAL_SIZE}B, installed=${INSTALLED_SIZE}B"
				if [ "$LOCAL_SIZE" = "$INSTALLED_SIZE" ]; then
					CERT_INSTALLED=true
				else
					log "ERROR: Certificate size mismatch after installation"
					exit 1
				fi
			else
				log "ERROR: Certificate file missing after installation"
				exit 1
			fi
		else
			log "ERROR: Failed to set permissions on system certificate"
			log "Debug: Checking certificate file status..."
			adb shell "ls -la ${CERT_PATH}"
			exit 1
		fi
	else
		log "ERROR: Failed to push certificate to system store"
		log "Push command output: $PUSH_OUTPUT"
		log "Push exit code: $PUSH_RESULT"
		log "Debug: Certificate installation diagnostics..."
		adb shell "ls -la ${CACERTS_DIR}/" 2>/dev/null || log "Failed to list cacerts directory"
		adb shell "df /system" 2>/dev/null || log "Failed to check system disk space"
		adb shell "mount | grep system" 2>/dev/null || log "Failed to check system mount status"
		log "Available space in /system:"
		adb shell "df -h /system | tail -1" 2>/dev/null || log "Failed to get system space info"
		log "SELinux status:"
		adb shell "getenforce" 2>/dev/null || log "Failed to get SELinux status"
		exit 1
	fi
else
	log "ERROR: mitmproxy CA PEM not found - this is a critical failure"
	exit 1
fi

# 7) Reboot to apply system CA changes (required since certificate is always installed)
log "Rebooting emulator to apply system CA changes..."
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
	log "ERROR: ADB connection failed after reboot"
	adb devices
	exit 1
fi

# 8) Re-enable root after reboot (required)
log "Re-enabling root access after reboot..."
if adb root >/dev/null 2>&1; then
	log "Root access re-enabled, waiting for ADB daemon to restart..."
	
	# Wait for device to reconnect after root access
	if ! timeout 60 adb wait-for-device; then
		log "ERROR: Device failed to reconnect after re-enabling root access"
		adb devices
		exit 1
	else
		# Quick verification that root is working
		sleep 2
		if adb shell echo "test" >/dev/null 2>&1; then
			log "Root access verified after reboot"
		else
			log "ERROR: Root access not working properly after reboot"
			exit 1
		fi
	fi
else
	log "ERROR: Failed to re-enable root access after reboot"
	log "This is a critical failure - root access is required"
	exit 1
fi
sleep 1

# 8) Confirm/force HTTP proxy via settings too (belt and suspenders)
adb shell settings put global http_proxy "10.0.2.2:8080" || true

# 9) Start Frida server inside emulator
log "Starting frida-server inside emulator..."
adb push /tools/frida-server /data/local/tmp/frida-server >/dev/null
adb shell "chmod 755 /data/local/tmp/frida-server"
# Start frida-server in background on device
adb shell "/data/local/tmp/frida-server >/dev/null 2>&1 &"

# 10) Auto-install APKs from /apks (optional)
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
log "Root access enabled with system certificates installed for full HTTPS interception"
log "Frida is running on the device. Example (in another shell inside container):"
log "  frida -U -f com.tplink.tapo -l /tools/repin.js --no-pause"

# Keep container alive and tail useful logs
touch /var/log/mitmdump.log /var/log/emulator.log
tail -n +1 -F /var/log/mitmdump.log /var/log/mitmweb.log /var/log/emulator.log /var/log/adb.log /var/log/x11vnc.log /var/log/novnc.log
