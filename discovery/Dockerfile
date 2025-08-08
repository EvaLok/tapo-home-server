# Ubuntu 24.04 base with everything needed to run:
# - Android SDK + emulator (API 30, Google APIs, x86_64)
# - Xvfb + Fluxbox + x11vnc + noVNC
# - mitmproxy + mitmweb (via pipx)
# - Frida tools and frida-server (android-x86_64)
# NOTE: For best performance, pass host KVM device to container:
#   --device /dev/kvm
# Will fallback to software emulation if KVM is not available.

FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV HOME=/root

# Android SDK locations
ENV ANDROID_HOME=/opt/android-sdk
ENV ANDROID_SDK_ROOT=/opt/android-sdk
ENV ANDROID_AVD_HOME=/root/.android/avd
ENV PATH=$PATH:/opt/android-sdk/emulator:/opt/android-sdk/platform-tools:/opt/android-sdk/cmdline-tools/latest/bin

# Ensure pipx puts shims in a global bin dir
ENV PIPX_HOME=/opt/pipx
ENV PIPX_BIN_DIR=/usr/local/bin

# Versions
ARG SDK_TOOLS_ZIP=https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip
ARG ANDROID_API=30
ARG ANDROID_IMG="system-images;android-30;google_apis;x86_64"
# Frida: tools vs server/core have different versioning
ARG FRIDA_TOOLS_VERSION=14.4.5
ARG FRIDA_SERVER_VERSION=16.3.3

# Base dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
	software-properties-common ca-certificates curl wget unzip git openssl gnupg \
	python3 python3-pip python3-venv python3-dev pipx \
	xvfb x11vnc fluxbox novnc websockify \
	openjdk-17-jre-headless \
	locales \
	# emulator runtime deps
	libc6 libstdc++6 libgcc-s1 libdbus-1-3 libnss3 libx11-6 libxext6 libxi6 libxrender1 libxrandr2 libxfixes3 libxcursor1 libxcomposite1 libxdamage1 libxkbcommon0 libgbm1 libglu1-mesa \
	# PulseAudio library for emulator QEMU audio subsystem
	libpulse0 \
	qemu-kvm xz-utils \
	&& locale-gen en_US.UTF-8 \
	&& rm -rf /var/lib/apt/lists/*

# mitmproxy (provides mitmproxy + mitmweb + mitmdump)
RUN pipx install "mitmproxy==10.3.0"

# Frida CLI (tools) and ensure Python 'frida' client matches server version
RUN pipx install "frida-tools==${FRIDA_TOOLS_VERSION}" && \
	pipx runpip frida-tools install "frida==${FRIDA_SERVER_VERSION}"

# Android SDK: commandline-tools (flatten folder so sdkmanager is on PATH)
RUN mkdir -p ${ANDROID_HOME}/cmdline-tools && \
	cd /tmp && \
	curl -fsSL "${SDK_TOOLS_ZIP}" -o commandlinetools.zip && \
	unzip -q commandlinetools.zip && \
	rm -f commandlinetools.zip && \
	mv /tmp/cmdline-tools ${ANDROID_HOME}/cmdline-tools/latest

# Prepare sdkmanager config before accepting licenses
RUN mkdir -p /root/.android && touch /root/.android/repositories.cfg

# Accept licenses & install platform tools, emulator, and system image
RUN yes | sdkmanager --sdk_root=${ANDROID_HOME} --licenses && \
	sdkmanager --sdk_root=${ANDROID_HOME} \
		"platform-tools" \
		"emulator" \
		"platforms;android-${ANDROID_API}" \
		"${ANDROID_IMG}"

# Create AVD (Google APIs x86_64, which allows adb root; avoid Google Play image)
RUN echo "no" | avdmanager create avd \
		-n tapo-avd \
		-k "${ANDROID_IMG}" \
		-d "pixel" && \
	echo "hw.keyboard=yes" >> /root/.android/avd/tapo-avd.avd/config.ini

# Download frida-server for Android x86_64 (must match FRIDA_SERVER_VERSION)
RUN mkdir -p /tools && \
	cd /tools && \
	curl -fsSL -o "frida-server-${FRIDA_SERVER_VERSION}-android-x86_64.xz" "https://github.com/frida/frida/releases/download/${FRIDA_SERVER_VERSION}/frida-server-${FRIDA_SERVER_VERSION}-android-x86_64.xz" && \
	unxz "frida-server-${FRIDA_SERVER_VERSION}-android-x86_64.xz" && \
	mv "frida-server-${FRIDA_SERVER_VERSION}-android-x86_64" frida-server && \
	chmod +x /tools/frida-server

# Copy launcher script and frida pinning bypass
COPY scripts/start.sh /start.sh
COPY tools/repin.js /tools/repin.js
RUN chmod +x /start.sh

# Configure noVNC to use English by default (remove non-English locale files)
RUN rm -f /usr/share/novnc/app/locale/ja.json \
	/usr/share/novnc/app/locale/zh_*.json \
	/usr/share/novnc/app/locale/ko.json \
	/usr/share/novnc/app/locale/fr.json \
	/usr/share/novnc/app/locale/de.json \
	/usr/share/novnc/app/locale/es.json \
	/usr/share/novnc/app/locale/it.json \
	/usr/share/novnc/app/locale/pl.json \
	/usr/share/novnc/app/locale/ru.json \
	/usr/share/novnc/app/locale/tr.json \
	/usr/share/novnc/app/locale/cs.json \
	/usr/share/novnc/app/locale/nl.json \
	/usr/share/novnc/app/locale/pt.json

# Place a workspace for APKs (mount host folder here)
RUN mkdir -p /apks

EXPOSE 6080 8080 8081

# The emulator prefers /dev/kvm from host for performance: run with --device /dev/kvm
# Will fallback to software emulation if KVM is not available
ENTRYPOINT ["/start.sh"]
