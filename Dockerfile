ARG BASE_TAG="1.18.0"
ARG BASE_IMAGE="core-debian-trixie"
FROM kasmweb/${BASE_IMAGE}:${BASE_TAG}

USER root

ENV HOME=/home/kasm-default-profile
ENV STARTUPDIR=/dockerstartup
ENV INST_SCRIPTS=${STARTUPDIR}/install
WORKDIR ${HOME}

######### Update Base Packages ###########

# Upgrade system packages to fix known vulnerabilities
RUN apt-get update \
    && apt-get upgrade -y --no-install-recommends \
    && rm -rf /var/lib/apt/lists/*

######### Install Applications ###########

# Application versions
ARG DELTACHAT_VERSION="2.35.0"

# Install Signal Desktop (Debian Trixie uses keyrings instead of apt-key)
RUN mkdir -p /usr/share/keyrings \
    && wget -qO- https://updates.signal.org/desktop/apt/keys.asc | gpg --dearmor > /usr/share/keyrings/signal-desktop-keyring.gpg \
    && echo 'deb [arch=amd64 signed-by=/usr/share/keyrings/signal-desktop-keyring.gpg] https://updates.signal.org/desktop/apt xenial main' > /etc/apt/sources.list.d/signal-xenial.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends signal-desktop \
    && sed -i 's|Exec=/opt/Signal/signal-desktop %U|Exec=/opt/Signal/signal-desktop --no-sandbox %U|' /usr/share/applications/signal-desktop.desktop \
    && rm -rf /var/lib/apt/lists/*

# Install Delta Chat Desktop
RUN wget -q "https://download.delta.chat/desktop/v${DELTACHAT_VERSION}/deltachat-desktop_${DELTACHAT_VERSION}_amd64.deb" -O /tmp/deltachat.deb \
    && apt-get update \
    && apt-get install -y --no-install-recommends /tmp/deltachat.deb \
    && rm -f /tmp/deltachat.deb \
    && rm -rf /var/lib/apt/lists/* \
    && sed -i 's|Exec=/opt/DeltaChat/deltachat-desktop|Exec=/opt/DeltaChat/deltachat-desktop --no-sandbox|' /usr/share/applications/deltachat-desktop.desktop

# Install Vivaldi Browser
RUN wget -qO- https://repo.vivaldi.com/archive/linux_signing_key.pub | gpg --dearmor > /usr/share/keyrings/vivaldi-browser.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/vivaldi-browser.gpg arch=amd64] https://repo.vivaldi.com/archive/deb/ stable main" > /etc/apt/sources.list.d/vivaldi.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends vivaldi-stable \
    && rm -rf /var/lib/apt/lists/* \
    && sed -i 's|Exec=/usr/bin/vivaldi-stable|Exec=/usr/bin/vivaldi-stable --no-sandbox|g' /usr/share/applications/vivaldi-stable.desktop

# Create desktop shortcuts for all applications
RUN mkdir -p ${HOME}/Desktop \
    && cp /usr/share/applications/signal-desktop.desktop ${HOME}/Desktop/ \
    && cp /usr/share/applications/deltachat-desktop.desktop ${HOME}/Desktop/ 2>/dev/null \
    || cp /usr/share/applications/deltachat.desktop ${HOME}/Desktop/ 2>/dev/null || true \
    && cp /usr/share/applications/vivaldi-stable.desktop ${HOME}/Desktop/ \
    && chmod +x ${HOME}/Desktop/*.desktop 2>/dev/null || true

######### End Application Installation ###########

# Copy custom startup script
COPY custom_startup.sh ${STARTUPDIR}/custom_startup.sh
RUN chmod 755 ${STARTUPDIR}/custom_startup.sh

# Final cleanup and permissions
RUN chown -R 1000:0 ${HOME} \
    && ${STARTUPDIR}/set_user_permission.sh ${HOME} \
    && find /usr/share/ -name "icon-theme.cache" -exec rm -f {} \; \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Userspace runtime
ENV HOME=/home/kasm-user
WORKDIR ${HOME}
RUN mkdir -p ${HOME} && chown -R 1000:0 ${HOME}

USER 1000
