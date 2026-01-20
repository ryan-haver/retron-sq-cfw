# Retron SQ CFW Build Environment
# Based on Ubuntu 20.04 LTS for Buildroot compatibility
#
# Build:  docker build -t retron-sq-build ./docker
# Run:    docker run -it --rm -v ${PWD}:/workspace retron-sq-build
#
FROM ubuntu:20.04

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# Set locale
RUN apt-get update && apt-get install -y locales && \
    locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

# Install build dependencies for Rockchip Buildroot
RUN apt-get update && apt-get install -y \
    # Core build tools
    build-essential \
    gcc \
    g++ \
    make \
    cmake \
    automake \
    autoconf \
    libtool \
    pkg-config \
    # Cross-compilation
    gcc-arm-linux-gnueabihf \
    g++-arm-linux-gnueabihf \
    # Kernel/bootloader tools
    bc \
    bison \
    flex \
    libssl-dev \
    libncurses5-dev \
    libncursesw5-dev \
    device-tree-compiler \
    u-boot-tools \
    lzop \
    # Filesystem tools
    squashfs-tools \
    dosfstools \
    mtools \
    parted \
    gdisk \
    kpartx \
    e2fsprogs \
    # Python (for Buildroot/scripts)
    python3 \
    python3-pip \
    python-is-python3 \
    # Version control
    git \
    subversion \
    # Compression
    zip \
    unzip \
    gzip \
    bzip2 \
    xz-utils \
    lzma \
    cpio \
    # Network tools (for downloads)
    wget \
    curl \
    rsync \
    # Misc utilities
    file \
    patch \
    texinfo \
    gettext \
    libglib2.0-dev \
    libpixman-1-dev \
    dos2unix \
    # Additional libraries for Buildroot packages
    libfdt-dev \
    libelf-dev \
    libmpc-dev \
    libgmp-dev \
    libmpfr-dev \
    # For host tools
    graphviz \
    python3-matplotlib \
    # Cleanup
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Create workspace directory
WORKDIR /workspace

# Set environment variables for cross-compilation
ENV CROSS_COMPILE=arm-linux-gnueabihf-
ENV ARCH=arm

# Create non-root user for builds (some Buildroot packages require this)
RUN useradd -m -s /bin/bash builder && \
    chown -R builder:builder /workspace

# Default command
CMD ["/bin/bash"]
