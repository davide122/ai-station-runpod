FROM runpod/pytorch:1.4.1-cu1281-torch280-ubuntu2404
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends  xfce4 xfce4-terminal thunar dbus-x11 tigervnc-standalone-server  novnc websockify ffmpeg mpv vlc xdg-utils x11-xserver-utils  ca-certificates curl git wget python3-venv iproute2 procps  libvulkan1 libgomp1 libgtk-3-0 libnss3 libatk-bridge2.0-0  libasound2t64 libgbm1 libxss1 libsecret-1-0  sudo rsync xz-utils && rm -rf /var/lib/apt/lists/*
RUN useradd -m -s /bin/bash ai && mkdir -p /opt/ai-station /var/lib/ai-station && chown -R ai:ai /var/lib/ai-station
RUN git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git /opt/ComfyUI &&  python -m venv --system-site-packages /opt/comfy-venv &&  /opt/comfy-venv/bin/python -m pip install --no-cache-dir -r /opt/ComfyUI/requirements.txt &&  git clone --depth 1 https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git /opt/ComfyUI/custom_nodes/ComfyUI-VideoHelperSuite &&  /opt/comfy-venv/bin/python -m pip install --no-cache-dir -r /opt/ComfyUI/custom_nodes/ComfyUI-VideoHelperSuite/requirements.txt
ARG LU_VERSION=3.0.7
RUN curl -fL "https://github.com/PurpleDoubleD/locally-uncensored/releases/download/v${LU_VERSION}/Locally.Uncensored_${LU_VERSION}_amd64.deb" -o /tmp/lu.deb &&  echo "54c412c043fe5aabfc570b0d7569d8e71540f7e07a5890dd9b9c083aa3b2b335  /tmp/lu.deb" | sha256sum -c - &&  apt-get update && apt-get install -y /tmp/lu.deb && rm -f /tmp/lu.deb && rm -rf /var/lib/apt/lists/*
COPY station.sh /usr/local/bin/ai-station
COPY run-station.sh /usr/local/bin/run-station
RUN chmod +x /usr/local/bin/ai-station /usr/local/bin/run-station
EXPOSE 22 8888
CMD ["/usr/local/bin/run-station"]
