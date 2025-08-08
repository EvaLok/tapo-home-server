# Android MITM Emulator in Docker

This image runs:
- Android Emulator (API 30, Google APIs, x86_64) with root
- mitmproxy (port 8080) + mitmweb (port 8081)
- Xvfb + Fluxbox + x11vnc + noVNC (port 6080)
- Frida server (inside emulator) + frida-tools (inside container)

All from inside a single container.

## Requirements

- Host OS: Ubuntu 24
- CPU virtualization enabled (KVM)
- Docker with access to `/dev/kvm`

Verify KVM:
```bash
ls /dev/kvm
```

## Build

```bash
docker build -t tapo-emulator:latest .
```

## Run

```bash
docker run --rm -it \
	--device /dev/kvm \
	-p 6080:6080 \
	-p 8080:8080 \
	-p 8081:8081 \
	-v "$PWD/apks":/apks \
	tapo-emulator:latest
```

- Mount APKs into `./apks` to auto-install (optional).
- Access the emulator UI: http://localhost:6080
- Inspect traffic in mitmweb: http://localhost:8081

## What the container does

1. Starts Xvfb + Fluxbox and serves the desktop via noVNC on port 6080.
2. Starts mitmproxy on port 8080 and mitmweb on 8081.
3. Launches the Android emulator with HTTP proxy set to `10.0.2.2:8080` (the container's mitmproxy).
4. Roots and remounts `/system`, installs the mitmproxy CA into the system trust store, then reboots the emulator.
5. Starts frida-server inside the emulator.

This ensures HTTPS is interceptable and pinning can be bypassed.

## Using Frida to bypass TLS pinning

Inside another shell in the same container:
```bash
docker exec -it $(docker ps -q --filter ancestor=tapo-emulator:latest) bash
frida -U -f com.tplink.tapo -l /tools/repin.js --no-pause
```

Then use the app in the emulator (noVNC). Requests should appear in mitmweb.

## Sideloading the Tapo APK

Place the APK in `./apks` before starting the container. The startup script installs any `*.apk` found in `/apks`.

Manual install:
```bash
adb install -r /apks/com.tplink.tapo.apk
```

## Captured data

In mitmweb (http://localhost:8081):
- Filter by hostname (e.g., `~u tplink|tapo`).
- Export flows as HAR.

## Notes/Troubleshooting

- If the emulator fails to start, ensure `/dev/kvm` is passed and not in use.
- If HTTPS isn’t decrypted:
    - Confirm mitm CA installed: `adb shell ls /system/etc/security/cacerts | grep -i mitm`
    - Check that proxy is set: `adb shell settings get global http_proxy` should print `10.0.2.2:8080`
    - Use Frida hook as above to bypass pinning.
- Avoid using a Google Play system image (root is disabled there). This setup uses Google APIs image, which allows `adb root`.

## Cleanup

Stop the container with Ctrl+C. The emulator AVD is inside the image, so a fresh container starts clean.
