ARG BASE_TAG="1.18.0"
ARG BASE_IMAGE="core-debian-trixie"
FROM kasmweb/${BASE_IMAGE}:${BASE_TAG}

USER root

ENV HOME=/home/kasm-default-profile
ENV STARTUPDIR=/dockerstartup
ENV INST_SCRIPTS=${STARTUPDIR}/install
WORKDIR ${HOME}

# Apply security patches and updates
RUN apt-get update \
    && apt-get upgrade -y --no-install-recommends \
    && rm -rf /var/lib/apt/lists/*

# Version pinning
ARG DELTACHAT_VERSION="2.35.0"

# Optimize: Combined RUN command for all browser installs with unified cleanup
# 1. Download all keys and add repos
# 2. Install all packages in single apt-get update call
# 3. Update desktop entries
# 4. Cleanup everything in same layer
RUN mkdir -p /usr/share/keyrings \
    # Signal Desktop key
    && wget -qO- https://updates.signal.org/desktop/apt/keys.asc | gpg --dearmor > /usr/share/keyrings/signal-desktop-keyring.gpg \
    # Delta Chat key (use same keyring file, different name to avoid confusion)
    && wget -qO- "https://download.delta.chat/desktop/v${DELTACHAT_VERSION}/deltachat-desktop_${DELTACHAT_VERSION}_amd64.deb" -O /tmp/deltachat.deb \
    # Vivaldi key
    && wget -qO- https://repo.vivaldi.com/archive/linux_signing_key.pub | gpg --dearmor > /usr/share/keyrings/vivaldi-browser.gpg \
    # Add repos (using xenial for Signal as original, stable for Vivaldi)
    && echo 'deb [arch=amd64 signed-by=/usr/share/keyrings/signal-desktop-keyring.gpg] https://updates.signal.org/desktop/apt xenial main' > /etc/apt/sources.list.d/signal-xenial.list \
    && echo "deb [signed-by=/usr/share/keyrings/vivaldi-browser.gpg arch=amd64] https://repo.vivaldi.com/archive/deb/ stable main" > /etc/apt/sources.list.d/vivaldi.list \
    # Update and install all in one go
    && apt-get update \
    && apt-get install -y --no-install-recommends signal-desktop vivaldi-stable \
    && apt-get install -y --no-install-recommends /tmp/deltachat.deb \
    # Update desktop entries with --no-sandbox for container use
    && sed -i 's|Exec=/opt/Signal/signal-desktop %U|Exec=/opt/Signal/signal-desktop --no-sandbox %U|' /usr/share/applications/signal-desktop.desktop \
    && sed -i 's|Exec=/opt/DeltaChat/deltachat-desktop|Exec=/opt/DeltaChat/deltachat-desktop --no-sandbox|' /usr/share/applications/deltachat-desktop.desktop \
    && sed -i 's|Exec=/usr/bin/vivaldi-stable %U|Exec=bash -c "rm -f ~/.config/vivaldi/SingletonLock; /usr/bin/vivaldi-stable --no-sandbox %U"|' /usr/share/applications/vivaldi-stable.desktop \
    # Cleanup apt sources (optional - saves ~2KB per file)
    && rm -f /etc/apt/sources.list.d/signal-xenial.list /etc/apt/sources.list.d/vivaldi.list \
    # Clean up temp files
    && rm -f /tmp/deltachat.deb \
    && rm -rf /var/lib/apt/lists/*

# Copy .desktop shortcuts to user's Desktop folder (now using optimized cleanup)
RUN mkdir -p ${HOME}/Desktop \
    && cp /usr/share/applications/signal-desktop.desktop ${HOME}/Desktop/ \
    && cp /usr/share/applications/deltachat-desktop.desktop ${HOME}/Desktop/ 2>/dev/null || true \
    && cp /usr/share/applications/vivaldi-stable.desktop ${HOME}/Desktop/ \
    && chmod +x ${HOME}/Desktop/*.desktop 2>/dev/null || true

# Kasm startup script
COPY custom_startup.sh ${STARTUPDIR}/custom_startup.sh
RUN chmod 755 ${STARTUPDIR}/custom_startup.sh

# Set ownership to kasm-user (UID 1000) and clean up temp files
RUN chown -R 1000:0 ${HOME} \
    && ${STARTUPDIR}/set_user_permission.sh ${HOME} \
    && find /usr/share/ -name "icon-theme.cache" -exec rm -f {} \; \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Switch to unprivileged user
ENV HOME=/home/kasm-user
WORKDIR ${HOME}
RUN mkdir -p ${HOME} && chown -R 1000:0 ${HOME}

USER 1000
