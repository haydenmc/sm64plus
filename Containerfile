# Build stage
FROM registry.fedoraproject.org/fedora-minimal:40 AS builder

RUN microdnf install -y --nodocs --setopt=install_weak_deps=0 \
    binutils-mips64-linux-gnu \
    gcc \
    gcc-c++ \
    make \
    audiofile-devel \
    SDL2-devel \
    libusb1-devel \
    libX11-devel \
    libXrandr-devel \
    capstone-devel \
    mesa-libGL-devel \
    pkgconf \
    python3 \
    util-linux \
    && microdnf clean all

WORKDIR /build

# Copy source code
COPY . .

# Build arguments for ROM version and parallel jobs
ARG VERSION=us
ARG JOBS=4

# The baserom must be provided at build time
# Either: COPY baserom.us.z64 into the repo before building
# Or: podman build --volume /path/to/baserom.us.z64:/build/baserom.us.z64:ro
RUN make VERSION=${VERSION} -j${JOBS}

# Output stage - just the build artifacts
FROM scratch

ARG VERSION=us

COPY --from=builder /build/build/${VERSION}_pc/sm64.${VERSION} /sm64
COPY --from=builder /build/build/${VERSION}_pc/gfx /gfx