# GUI Container for EDA Tools
# This image provides an Xvnc-backed AlmaLinux 9 desktop endpoint for GUI smoke tests.

FROM almalinux:9

USER root
RUN dnf -y update && \
    dnf -y install epel-release && \
    dnf -y install \
        Thunar \
        dbus-x11 \
        openbox \
        procps-ng \
        tigervnc-server \
        xfce4-panel \
        xfce4-session \
        xfce4-settings \
        xfce4-terminal \
        xfdesktop \
        xfwm4 \
        xorg-x11-utils \
        xorg-x11-xauth \
        xterm && \
    rm -f \
        /etc/xdg/autostart/xfce-polkit.desktop \
        /etc/xdg/autostart/geoclue-demo-agent.desktop && \
    dnf clean all

RUN useradd --create-home --shell /bin/bash x11user
USER x11user
WORKDIR /home/x11user
ENV HOME=/home/x11user USER=x11user LOGNAME=x11user
