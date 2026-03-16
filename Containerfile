ARG FEDORA_MAJOR_VERSION=42

# Build context — scripts are bind-mounted, never copied into the final image
FROM scratch AS ctx
COPY build_files /

# Base Image — Fedora Sway Atomic (formerly Sericea)
FROM quay.io/fedora/fedora-sway-atomic:${FEDORA_MAJOR_VERSION}

# Install packages and configure the system
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build.sh

# Copy system data and config files into the image
COPY usr/ /usr/
COPY etc/ /etc/

# Verify final image is a valid bootc container
RUN bootc container lint
