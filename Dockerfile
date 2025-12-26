#::::::::::::::#
#:::::Base:::::#
#::::::::::::::#

# syntax=docker/dockerfile:1.4
FROM kalilinux/kali-rolling:latest AS base

# Configure default user and set env
# The users UID and GID will be set on container startup
ENV \
    PUID=1000 \
    PGID=1000 \
    UMASK=000 \
    UNAME="retro" \
    HOME="/home/retro" \
    TZ="Europe/Berlin" \
    DEBIAN_FRONTEND=noninteractive \
    NEEDRESTART_SUSPEND=1

ARG TARGETARCH TARGETVARIANT

# Install default required packages
ARG GOSU_VERSION=1.14

RUN <<_INSTALL_PACKAGES
set -e
echo "**** Update apt database ****"
apt-get update

echo "**** Install certificates ****"
apt-get install -y --reinstall --no-install-recommends \
    ca-certificates

echo "**** Install base packages ****"
apt-get install -y --no-install-recommends \
    fuse \
    libnss3 \
    wget \
    curl \
    jq

echo "**** Install gosu ****"
wget --progress=dot:giga \
    -O /usr/bin/gosu \
    "https://github.com/tianon/gosu/releases/download/${GOSU_VERSION}/gosu-${TARGETARCH}${TARGETVARIANT}"
chmod +x /usr/bin/gosu

echo "**** Verify gosu works ****"
gosu nobody true && echo "Working!"

echo "**** Section cleanup ****"
rm -rf \
    /var/lib/apt/lists/*

echo
_INSTALL_PACKAGES

# Import overlay
COPY assets/base/overlay /

# Set entrypoint script
ENTRYPOINT ["/entrypoint.sh"]

#::::::::::::::::::::::::::::::#
#:::::SDL::JSTEST::BUILDER:::::#
#::::::::::::::::::::::::::::::#

FROM base AS sdl-jstest-builder

ENV DEBIAN_FRONTEND=noninteractive

WORKDIR /

ARG SDL_JS_TEST_VERSION=8a84a47209f96eb3994cf9f906ae072e828886bb
ENV SDL_JS_TEST_VERSION=${SDL_JS_TEST_VERSION}
RUN <<_BUILD_SDL_JSTEST
    set -e

    apt-get update -y
    apt install -y --no-install-recommends \
      build-essential \
      cmake \
      libsdl2-dev \
      libncurses5-dev \
      git

    git clone https://github.com/games-on-whales/sdl-jstest
    cd sdl-jstest
    git checkout ${SDL_JS_TEST_VERSION}
    git submodule init
    git submodule update
    mkdir build
    cd build
    cmake .. -DBUILD_SDL_JSTEST=OFF -DBUILD_SDL2_JSTEST=ON
    make

_BUILD_SDL_JSTEST

#:::::::::::::::::::#
#:::::Base::App:::::#
#:::::::::::::::::::#

FROM base AS base-app

ENV DEBIAN_FRONTEND=noninteractive
ENV BUILD_ARCHITECTURE=amd64
ENV DEB_BUILD_OPTIONS=noddebs

ARG PKGS_ROOT=/opt/gow

# x11-utils: contains xdpyinfo, which we use to know whether Xorg has started yet
# pulseaudio-utils: some apps can't play sound unless this package is installed
ARG REQUIRED_PACKAGES="\
    x11-utils \
    pulseaudio-utils \
    mesa-vulkan-drivers libgbm1 libgles2 libegl1 libgl1-mesa-dri \
    libnvidia-egl-wayland1 libnvidia-egl-gbm1 \
    fonts-noto-cjk \
    locales \
    xwayland kitty nano \
    waybar fonts-font-awesome xdg-desktop-portal xdg-desktop-portal-gtk psmisc \
    "

RUN apt-get update -y && \
    apt-get install -y --no-install-recommends \
    $REQUIRED_PACKAGES && \
    rm -rf /var/lib/apt/lists/*

# Some games with native Linux ports require en_US.UTF-8
# to be generated regardless of user locale settings
# see: https://github.com/games-on-whales/gow/pull/185
RUN locale-gen en_US.UTF-8

COPY assets/base-app/configs /cfg

COPY --chmod=777 assets/base-app/scripts/launch-comp.sh /opt/gow/launch-comp.sh
COPY --chmod=777 assets/base-app/scripts/startup.sh /opt/gow/startup.sh
COPY --chmod=777 assets/base-app/scripts/wait-x11 /opt/gow/wait-x11

RUN apt-get update -y && \
    apt-get install -y --no-install-recommends libsdl2-2.0-0 libncurses6 && \
    rm -rf /var/lib/apt/lists/*
COPY --from=sdl-jstest-builder /sdl-jstest/build/sdl2-jstest /usr/local/bin/sdl2-jstest

#################################
# Install Sway
#################################
# We had lots of issues with Sway 1.10.1
# So we are manually reverting back to 1.9 from Ubuntu 24.04
RUN <<_INSTALL_SWAY
#!/bin/bash
set -e
apt update
apt install -y sway swaybg polkitd libwlroots-0.19-dev libwlroots-0.19 libwayland-dev libxcb-icccm4
_INSTALL_SWAY

# Configure the default directory to be the 'retro' users home directory
WORKDIR ${HOME}

#::::::::::::::#
#:::::XFCE:::::#
#::::::::::::::#

# syntax=docker/dockerfile:1.4
FROM base-app

ARG CORE_PACKAGES=" \
    lsb-release \
    wget \
    gnupg2 \
    dbus-x11 \
    flatpak \
    sudo \
    "

ARG DE_PACKAGES=" \
    xfce4 \
    xfce4-settings \
    at-spi2-core \
    "

ARG ADDITIONAL_PACKAGES=" \
    xfce4-terminal \
    xfce4-taskmanager \
    xfce4-whiskermenu-plugin \
    xfce4-docklike-plugin \
    xarchiver \
    mousepad \
    zip unzip p7zip-full \
    gnome-software gnome-software-plugin-flatpak \
    "
#
# Prevent firefox snap
COPY assets/xfce/scripts/ff-unsnap /etc/apt/preferences.d/ff-unsnap

RUN \
    # \
    # Setup Firefox PPA \
    apt-get update && \
    apt-get install -y --no-install-recommends software-properties-common gpg-agent && \
    apt-get update && \
    # \
    # Install core packages \
    apt-get install -y $CORE_PACKAGES && \
    # \
    # Install de \
    apt-get install -y $DE_PACKAGES && \
    # \
    # Install additional apps \
    apt-get install -y --no-install-recommends $ADDITIONAL_PACKAGES && \
    # \
    # Fixes \
    rm -f \
    /etc/xdg/autostart/xscreensaver.desktop && \
    # \
    # Clean \
    apt update && \
    apt-get remove -y foot && \
    apt autoremove -y &&\
    apt clean && \
    rm -rf \
    /config/.cache \
    /var/lib/apt/lists/* \
    /var/tmp/* \
    /tmp/*

#
# Replace launch scripts
COPY --chmod=777 assets/xfce/scripts/launch-comp.sh assets/xfce/scripts/startup.sh /opt/gow/
COPY --chmod=777 assets/xfce/scripts/startdbus.sh /opt/gow/startdbus

#
# Include default xfce config
COPY --chmod=777 --chown=retro:retro assets/xfce/scripts/xfce4 /opt/gow/xfce4

#
# Fix locals
COPY assets/xfce/scripts/locale /etc/default/locale

#
# Allow anyone to start dbus without password
RUN echo "\nALL ALL=NOPASSWD: /opt/gow/startdbus" >> /etc/sudoers

#
# Fix bwarp perms for flatpaks
RUN chmod u+s /usr/bin/bwrap

ENV XDG_RUNTIME_DIR=/tmp/.X11-unix

ARG IMAGE_SOURCE
LABEL org.opencontainers.image.source=$IMAGE_SOURCE
