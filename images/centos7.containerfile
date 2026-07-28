# CentOS 7 Container for EDA Tools
# This containerfile sets up a CentOS 7 environment optimized for running EDA tools
# It includes all necessary dependencies for GUI applications and system libraries

FROM quay.io/centos/centos:7

# Update system and install required packages for EDA Tools (like Virtuoso)
# The installation is split into logical groups for better maintainability
RUN sed -i -e 's|^mirrorlist=|#mirrorlist=|' -e 's|^#baseurl=http://mirror.centos.org/centos/$releasever|baseurl=http://vault.centos.org/7.9.2009|' /etc/yum.repos.d/CentOS-*.repo && \
    yum -y update && \
    # Install yum plugin manager for repository management
    yum install -y yum-utils && \
    # Install EPEL repository for extra packages
    yum install -y epel-release && \
    # Install LSB (Linux Standard Base) tools for system information
    yum install -y redhat-lsb-core passwd && \
    yum -y install \
        # Basic development and shell tools
        ksh csh xterm tcsh tcl-devel file which gcc gcc-c++ make python3 curl tar gzip iptables iptables-services \
        # X11 and GUI libraries required for EDA GUI applications
        libXp libXtst libXext libXft libXmu libXrandr libXrender \
        libXi libXcursor libXinerama libXdmcp libXau libxcb \
        motif motif-devel gtk2 gtk2-devel \
        # Core system libraries
        glibc glibc-devel \
        libgcc libstdc++ libatomic snappy \
        # Graphics and display libraries
        fontconfig freetype libpng libpng12 libjpeg-turbo \
        mesa-libGL mesa-libGLU mesa-dri-drivers \
        libSM libICE \
        # PDF reader
        evince \
        # Additional dependencies specific to EDA tools
        nss procps-ng elfutils-libelf-devel pciutils-libs libzstd orc \
        numactl-libs pcre2 pcre2-utf16 libssh libidn2 glibc.i686 ncurses-libs.i686 \
        libXScrnSaver dbus dbus-devel \
        libtiff openssl-devel apr-util \
        pulseaudio-libs-glib2 \
        # Cadence Innovus
        gd \
        # Arteris FlexNoC
        libicu libicu-devel \
        # Explicitly add missing xcb utilities
        xcb-util xcb-util-renderutil \
        xcb-util-image xcb-util-cursor \
        xcb-util-keysyms xcb-util-wm  compat-db47 \
        xkeyboard-config libxkbcommon-x11 alsa-lib \
        # Font packages and X11 utilities
        "xorg-x11-fonts-*" xorg-x11-server-utils xorg-x11-utils \
        # Development and debugging tools
        strace ltrace gdb vim zsh git telnet radare2

# Generate and set up D-Bus machine ID
# This is required for D-Bus to function properly in the container
RUN rm -f /etc/machine-id /var/lib/dbus/machine-id \
    && dbus-uuidgen --ensure=/etc/machine-id \
    && mkdir -p /var/lib/dbus \
    && ln -s /etc/machine-id /var/lib/dbus/machine-id \
    && yum clean all

# EL7 distribution packages are either old Environment Modules 3.x or EPEL Lmod.
# Build Environment Modules 5.x so modulefile behavior matches EL8+ containers.
ARG modules_version=5.3.0
RUN cd /tmp \
    && curl -fsSL -o modules.tar.gz "https://github.com/cea-hpc/modules/releases/download/v${modules_version}/modules-${modules_version}.tar.gz" \
    && tar -xzf modules.tar.gz \
    && cd "modules-${modules_version}" \
    && ./configure --prefix=/usr/share/Modules --modulefilesdir=/usr/share/modulefiles \
    && make -j2 \
    && make install \
    && ln -sf /usr/share/Modules/init/profile.sh /etc/profile.d/modules.sh \
    && ln -sf /usr/share/Modules/init/profile.csh /etc/profile.d/modules.csh \
    && rm -rf "/tmp/modules-${modules_version}" /tmp/modules.tar.gz

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
    echo '[ -f /etc/profile.d/lmod.sh ] && source /etc/profile.d/lmod.sh; [ -f /etc/profile.d/modules.sh ] && source /etc/profile.d/modules.sh' >> /home/${user}/.zshrc

# Change Theme to AI-Candy
RUN curl -o /home/${user}/.oh-my-zsh/custom/themes/ai-candy.zsh-theme \
    https://raw.githubusercontent.com/SihaoLiu/ai-candy/refs/heads/main/ai-candy.zsh-theme

# Set the default command to start zsh shell
CMD ["/usr/bin/zsh"]
