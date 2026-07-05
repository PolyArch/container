# Rocky Linux 10 Container for EDA Tools
# This containerfile sets up a Rocky Linux 10 environment optimized for running EDA tools
# It includes all necessary dependencies for GUI applications and system libraries

FROM quay.io/rockylinux/rockylinux:10

# Update system and install required packages for EDA Tools (like Virtuoso)
# The installation is split into logical groups for better maintainability
RUN dnf -y update && \
    # Install dnf plugin manager for repository management
    dnf install -y dnf-plugins-core && \
    # Enable CRB repository for additional packages
    dnf config-manager --set-enabled crb && \
    # Install EPEL repository for extra packages
    dnf install -y epel-release passwd && \
    # Install LSB (Linux Standard Base) tools for system information
    dnf install -y lsb-release && \
    dnf -y install \
        # Basic development and shell tools
        ksh csh xterm tcsh tcl-devel file which gcc gcc-c++ make iptables iptables-services environment-modules \
        # X11 and GUI libraries required for EDA GUI applications
        libXtst libXext libXft libXmu libXrandr libXrender \
        libXi libXcursor libXinerama libXdmcp libXau libxcb \
        gtk2 gtk2-devel \
        # Core system libraries
        glibc glibc-devel \
        libgcc libstdc++ \
        # Graphics and display libraries
        fontconfig freetype libpng libjpeg-turbo \
        mesa-libGL mesa-libGLU mesa-dri-drivers \
        libSM libICE \
        # Additional dependencies specific to EDA tools
        nss procps-ng elfutils-libelf-devel libssh \
        dbus dbus-devel dbus-tools \
        libtiff openssl-devel apr-util libxcrypt-compat libnsl \
        "xcb-util-*" xkeyboard-config libxkbcommon-x11 \
        alsa-lib ncurses-compat-libs \
        numactl-libs pulseaudio-libs-glib2 \
        openldap-compat \
        # Cadence SPB
        libtirpc pciutils-libs \
        # Cadence Stratus
        perl \
        # Cadence Innovus
        gd \
        # Arteris FlexNoC
        "libpng*" libicu libicu-devel \
        # Font packages and X11 utilities
        "xorg-x11-fonts-*" \
        # Development and debugging tools
        strace ltrace gdb \
        # Locale support for English UTF-8
        glibc-langpack-en \
        # Development Tools
        vim zsh git telnet radare2

# Generate and set up D-Bus machine ID
# This is required for D-Bus to function properly in the container
RUN rm -f /etc/machine-id /var/lib/dbus/machine-id \
    && dbus-uuidgen --ensure=/etc/machine-id \
    && mkdir -p /var/lib/dbus \
    && ln -s /etc/machine-id /var/lib/dbus/machine-id \
    && dnf clean all

# Create a non-root user for running EDA tools
# The UID and GID are configurable through build arguments
ARG user=eda
ARG uid=1000
ARG gid=1000
# Add timezone as a configurable build argument with default value
ARG timezone=America/Los_Angeles
RUN groupadd -g ${gid} ${user} && \
    useradd -m -u ${uid} -g ${gid} -s /bin/bash ${user} && \
    # Remove root password to allow passwordless su root
    passwd -d root

# Switch to the non-root user for security
USER ${user}
WORKDIR /home/${user}

# Set up environment variables
# Configure locale for proper character encoding
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

# Set timezone using the configurable argument
ENV TZ=${timezone}

# Configure X11 for GUI support
ENV DISPLAY=:0
ENV QT_X11_NO_MITSHM=1

# Create necessary directories for mounting
# These directories will be used for work files
RUN mkdir -p /home/${user}/work

# Create directories for license and acceptance file mounts
RUN mkdir -p /home/${user}/.Xilinx /home/${user}/.achronix

# Install Oh My Zsh and configure .zshrc
RUN sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" && \
    echo 'export ZSH_DISABLE_COMPFIX=true' > /home/${user}/.zshrc && \
    echo 'export ZSH="$HOME/.oh-my-zsh"' >> /home/${user}/.zshrc && \
    echo 'DISABLE_AUTO_UPDATE="true"' >> /home/${user}/.zshrc && \
    echo 'ZSH_THEME="ai-candy"' >> /home/${user}/.zshrc && \
    echo 'plugins=(git)' >> /home/${user}/.zshrc && \
    echo 'source $ZSH/oh-my-zsh.sh' >> /home/${user}/.zshrc && \
    echo '[ -f /etc/profile.d/modules.sh ] && source /etc/profile.d/modules.sh' >> /home/${user}/.zshrc

# Change Theme to AI-Candy
RUN curl -o /home/${user}/.oh-my-zsh/custom/themes/ai-candy.zsh-theme \
    https://raw.githubusercontent.com/SihaoLiu/ai-candy/refs/heads/main/ai-candy.zsh-theme

# Set the default command to start zsh shell
CMD ["/usr/bin/zsh"] 
