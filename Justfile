export image_name := env("IMAGE_NAME", "sway-blue") # output image name, usually same as repo name
export default_tag := env("DEFAULT_TAG", "latest")
export bib_image := env("BIB_IMAGE", "quay.io/centos-bootc/bootc-image-builder:latest")
export vm_user := env("VM_USER", "test")
export vm_password := env("VM_PASSWORD", "test")

alias build-vm := build-qcow2
alias rebuild-vm := rebuild-qcow2
alias run-vm := run-vm-qcow2

[private]
default:
    @just --list

# Check Just Syntax
[group('Just')]
check:
    #!/usr/bin/bash
    find . -type f -name "*.just" | while read -r file; do
    	echo "Checking syntax: $file"
    	just --unstable --fmt --check -f $file
    done
    echo "Checking syntax: Justfile"
    just --unstable --fmt --check -f Justfile

# Fix Just Syntax
[group('Just')]
fix:
    #!/usr/bin/bash
    find . -type f -name "*.just" | while read -r file; do
    	echo "Checking syntax: $file"
    	just --unstable --fmt -f $file
    done
    echo "Checking syntax: Justfile"
    just --unstable --fmt -f Justfile || { exit 1; }

# Clean Repo
[group('Utility')]
clean:
    #!/usr/bin/bash
    set -eoux pipefail
    touch _build
    find *_build* -exec rm -rf {} \;
    rm -f previous.manifest.json
    rm -f changelog.md
    rm -f output.env
    rm -f output/

# Sudo Clean Repo
[group('Utility')]
[private]
sudo-clean:
    just sudoif just clean

# sudoif bash function
[group('Utility')]
[private]
sudoif command *args:
    #!/usr/bin/bash
    function sudoif(){
        if [[ "${UID}" -eq 0 ]]; then
            "$@"
        elif [[ "$(command -v sudo)" ]] && [[ -t 0 ]]; then
            # Interactive terminal — use plain sudo (prompts for password)
            /usr/bin/sudo "$@" || exit 1
        elif [[ "$(command -v sudo)" && -n "${SSH_ASKPASS:-}" ]] && [[ -n "${DISPLAY:-}" || -n "${WAYLAND_DISPLAY:-}" ]]; then
            /usr/bin/sudo --askpass "$@" || exit 1
        elif [[ "$(command -v sudo)" ]]; then
            /usr/bin/sudo "$@" || exit 1
        else
            exit 1
        fi
    }
    sudoif {{ command }} {{ args }}

# This Justfile recipe builds a container image using Podman.
#
# Arguments:
#   $target_image - The tag you want to apply to the image (default: $image_name).
#   $tag - The tag for the image (default: $default_tag).
#
# The script constructs the version string using the tag and the current date.
# If the git working directory is clean, it also includes the short SHA of the current HEAD.
#
# just build $target_image $tag
#
# Example usage:
#   just build aurora lts
#
# This will build an image 'aurora:lts' with DX and GDX enabled.
#

# Build the image using the specified parameters
build $target_image=image_name $tag=default_tag:
    #!/usr/bin/env bash

    LOGFILE="output_$(date +%Y%m%d_%H%M%S).txt"
    echo "Build log: ${LOGFILE}"

    BUILD_ARGS=()
    if [[ -z "$(git status -s)" ]]; then
        BUILD_ARGS+=("--build-arg" "SHA_HEAD_SHORT=$(git rev-parse --short HEAD)")
    fi

    podman build \
        "${BUILD_ARGS[@]}" \
        --pull=newer \
        --jobs=$(nproc) \
        --tag "${target_image}:${tag}" \
        . 2>&1 | tee "${LOGFILE}"

    exit ${PIPESTATUS[0]}

# Command: _rootful_load_image
# Description: This script checks if the current user is root or running under sudo. If not, it attempts to resolve the image tag using podman inspect.
#              If the image is found, it loads it into rootful podman. If the image is not found, it pulls it from the repository.
#
# Parameters:
#   $target_image - The name of the target image to be loaded or pulled.
#   $tag - The tag of the target image to be loaded or pulled. Default is 'default_tag'.
#
# Example usage:
#   _rootful_load_image my_image latest
#
# Steps:
# 1. Check if the script is already running as root or under sudo.
# 2. Check if target image is in the non-root podman container storage)
# 3. If the image is found, load it into rootful podman using podman scp.
# 4. If the image is not found, pull it from the remote repository into reootful podman.

_rootful_load_image $target_image=image_name $tag=default_tag:
    #!/usr/bin/bash
    set -eoux pipefail

    # When run via `sudo just`, copy the image from the invoking user's storage
    if [[ -n "${SUDO_USER:-}" ]]; then
        SUDO_UID=$(id -u "${SUDO_USER}")
        ROOT_IMG_ID=$(podman images --filter reference="${target_image}:${tag}" --format "{{ '{{.ID}}' }}" 2>/dev/null || true)
        USER_IMG_ID=$(podman --storage-driver overlay --root "/home/${SUDO_USER}/.local/share/containers/storage" images --filter reference="${target_image}:${tag}" --format "{{ '{{.ID}}' }}" 2>/dev/null || true)

        if [[ -z "$USER_IMG_ID" ]]; then
            # Try XDG_DATA_HOME/podman paths (Fedora Atomic uses /var/home)
            for base in "/var/home/${SUDO_USER}/.local/share/containers/storage" "/home/${SUDO_USER}/.local/share/containers/storage"; do
                if [[ -d "$base" ]]; then
                    USER_IMG_ID=$(podman --root "$base" images --filter reference="${target_image}:${tag}" --format "{{ '{{.ID}}' }}" 2>/dev/null || true)
                    [[ -n "$USER_IMG_ID" ]] && break
                fi
            done
        fi

        if [[ -n "$USER_IMG_ID" && "$USER_IMG_ID" != "$ROOT_IMG_ID" ]]; then
            echo "Copying image from ${SUDO_USER}'s podman to root podman..."
            COPYTMP=$(mktemp -p "${PWD}" -d -t _build_podman_scp.XXXXXXXXXX)
            TMPDIR=${COPYTMP} podman image scp ${SUDO_UID}@localhost::"${target_image}:${tag}" root@localhost::"${target_image}:${tag}"
            rm -rf "${COPYTMP}"
        elif [[ -n "$ROOT_IMG_ID" ]]; then
            echo "Image already in root podman storage."
        else
            echo "Error: image ${target_image}:${tag} not found in ${SUDO_USER}'s podman storage."
            echo "Run 'just build' first (without sudo)."
            exit 1
        fi
        exit 0
    fi

    # Already root (not via sudo) — nothing to copy
    if [[ "${UID}" -eq "0" ]]; then
        exit 0
    fi

    # Running as regular user — copy to root via sudo
    set +e
    resolved_tag=$(podman inspect -t image "${target_image}:${tag}" | jq -r '.[].RepoTags.[0]')
    return_code=$?
    set -e

    USER_IMG_ID=$(podman images --filter reference="${target_image}:${tag}" --format "{{ '{{.ID}}' }}")

    if [[ $return_code -eq 0 ]]; then
        ID=$(just sudoif podman images --filter reference="${target_image}:${tag}" --format "{{ '{{.ID}}' }}")
        if [[ "$ID" != "$USER_IMG_ID" ]]; then
            COPYTMP=$(mktemp -p "${PWD}" -d -t _build_podman_scp.XXXXXXXXXX)
            just sudoif TMPDIR=${COPYTMP} podman image scp ${UID}@localhost::"${target_image}:${tag}" root@localhost::"${target_image}:${tag}"
            rm -rf "${COPYTMP}"
        fi
    else
        just sudoif podman pull "${target_image}:${tag}"
    fi

# Build a bootc bootable image using Bootc Image Builder (BIB)
# Converts a container image to a bootable image
# Parameters:
#   target_image: The name of the image to build (ex. localhost/fedora)
#   tag: The tag of the image to build (ex. latest)
#   type: The type of image to build (ex. qcow2, raw, iso)
#   config: The configuration file to use for the build (default: disk_config/disk.toml)

# Example: just _rebuild-bib localhost/fedora latest qcow2 disk_config/disk.toml
_build-bib $target_image $tag $type $config: (_rootful_load_image target_image tag)
    #!/usr/bin/env bash
    set -euo pipefail

    LOGFILE="output_bib_$(date +%Y%m%d_%H%M%S).txt"
    echo "BIB build log: ${LOGFILE}"

    args="--type ${type} "
    args+="--use-librepo=True "
    args+="--rootfs=btrfs"

    BUILDTMP=$(mktemp -p "${PWD}" -d -t _build-bib.XXXXXXXXXX)

    sudo podman run \
      --rm \
      -it \
      --privileged \
      --pull=newer \
      --net=host \
      --security-opt label=type:unconfined_t \
      -v $(pwd)/${config}:/config.toml:ro \
      -v $BUILDTMP:/output \
      -v /var/lib/containers/storage:/var/lib/containers/storage \
      "${bib_image}" \
      ${args} \
      "${target_image}:${tag}" 2>&1 | tee "${LOGFILE}"

    BIB_EXIT=${PIPESTATUS[0]}
    if [[ $BIB_EXIT -ne 0 ]]; then
        sudo rm -rf "$BUILDTMP"
        exit $BIB_EXIT
    fi

    mkdir -p output
    # Remove previous build output for this type to allow mv
    sudo rm -rf "output/${type}"
    sudo mv -f $BUILDTMP/* output/
    sudo rmdir $BUILDTMP
    sudo chown -R $USER:$USER output/

# Podman builds the image from the Containerfile and creates a bootable image
# Parameters:
#   target_image: The name of the image to build (ex. localhost/fedora)
#   tag: The tag of the image to build (ex. latest)
#   type: The type of image to build (ex. qcow2, raw, iso)
#   config: The configuration file to use for the build (deafult: disk_config/disk.toml)

# Example: just _rebuild-bib localhost/fedora latest qcow2 disk_config/disk.toml
_rebuild-bib $target_image $tag $type $config: (build target_image tag) && (_build-bib target_image tag type config)

# Generate VM disk config with test credentials from environment
[private]
_gen-vm-config:
    #!/usr/bin/bash
    set -euo pipefail
    sed -e "s/VM_USER/${vm_user}/" -e "s/VM_PASSWORD/${vm_password}/" \
        disk_config/disk-vm.toml.template > disk_config/disk-vm.toml
    echo "VM user: ${vm_user} / password: ${vm_password}"

# Build a QCOW2 virtual machine image
[group('Build Virtal Machine Image')]
build-qcow2 $target_image=("localhost/" + image_name) $tag=default_tag: _gen-vm-config && (_build-bib target_image tag "qcow2" "disk_config/disk-vm.toml")

# Build a RAW virtual machine image
[group('Build Virtal Machine Image')]
build-raw $target_image=("localhost/" + image_name) $tag=default_tag: _gen-vm-config && (_build-bib target_image tag "raw" "disk_config/disk-vm.toml")

# Build an ISO virtual machine image
[group('Build Virtal Machine Image')]
build-iso $target_image=("localhost/" + image_name) $tag=default_tag: _gen-vm-config && (_build-bib target_image tag "iso" "disk_config/iso.toml")

# Rebuild a QCOW2 virtual machine image
[group('Build Virtal Machine Image')]
rebuild-qcow2 $target_image=("localhost/" + image_name) $tag=default_tag: _gen-vm-config && (_rebuild-bib target_image tag "qcow2" "disk_config/disk-vm.toml")

# Rebuild a RAW virtual machine image
[group('Build Virtal Machine Image')]
rebuild-raw $target_image=("localhost/" + image_name) $tag=default_tag: _gen-vm-config && (_rebuild-bib target_image tag "raw" "disk_config/disk-vm.toml")

# Rebuild an ISO virtual machine image
[group('Build Virtal Machine Image')]
rebuild-iso $target_image=("localhost/" + image_name) $tag=default_tag: _gen-vm-config && (_rebuild-bib target_image tag "iso" "disk_config/iso.toml")

# Run a virtual machine with the specified image type and configuration
_run-vm $target_image $tag $type $config:
    #!/usr/bin/bash
    set -eoux pipefail

    # Determine the image file based on the type
    image_file="output/${type}/disk.${type}"
    if [[ $type == iso ]]; then
        image_file="output/bootiso/install.iso"
    fi

    # Build the image if it does not exist
    if [[ ! -f "${image_file}" ]]; then
        just "build-${type}" "$target_image" "$tag"
    fi

    # Determine an available port to use
    port=8006
    while grep -q :${port} <<< $(ss -tunalp); do
        port=$(( port + 1 ))
    done
    echo "Using Port: ${port}"
    echo "Connect to http://localhost:${port}"

    # Set up the arguments for running the VM
    run_args=()
    run_args+=(--rm --privileged)
    run_args+=(--pull=newer)
    run_args+=(--publish "127.0.0.1:${port}:8006")
    run_args+=(--env "CPU_CORES=4")
    run_args+=(--env "RAM_SIZE=8G")
    run_args+=(--env "DISK_SIZE=64G")
    run_args+=(--env "TPM=Y")
    run_args+=(--env "GPU=Y")
    run_args+=(--device=/dev/kvm)
    run_args+=(--volume "${PWD}/${image_file}":"/boot.${type}")
    run_args+=(docker.io/qemux/qemu)

    # Run the VM and open the browser to connect
    (sleep 30 && xdg-open http://localhost:"$port") &
    podman run "${run_args[@]}"

# Run a virtual machine from a QCOW2 image
[group('Run Virtal Machine')]
run-vm-qcow2 $target_image=("localhost/" + image_name) $tag=default_tag: && (_run-vm target_image tag "qcow2" "disk_config/disk.toml")

# Run a virtual machine from a RAW image
[group('Run Virtal Machine')]
run-vm-raw $target_image=("localhost/" + image_name) $tag=default_tag: && (_run-vm target_image tag "raw" "disk_config/disk.toml")

# Run a virtual machine from an ISO
[group('Run Virtal Machine')]
run-vm-iso $target_image=("localhost/" + image_name) $tag=default_tag: && (_run-vm target_image tag "iso" "disk_config/iso.toml")

# Run a virtual machine using systemd-vmspawn
[group('Run Virtal Machine')]
spawn-vm rebuild="0" type="qcow2" ram="6G":
    #!/usr/bin/env bash

    set -euo pipefail

    [ "{{ rebuild }}" -eq 1 ] && echo "Rebuilding the ISO" && just build-vm {{ rebuild }} {{ type }}

    systemd-vmspawn \
      -M "bootc-image" \
      --console=gui \
      --cpus=2 \
      --ram=$(echo {{ ram }}| /usr/bin/numfmt --from=iec) \
      --network-user-mode \
      --vsock=false --pass-ssh-key=false \
      -i ./output/**/*.{{ type }}


# Install Flatpak apps from the curated list
[group('Setup')]
install-flatpaks:
    #!/usr/bin/bash
    set -euo pipefail
    if ! flatpak remote-list | grep -q flathub; then
        flatpak remote-add --if-not-exists --user flathub https://flathub.org/repo/flathub.flatpakrepo
    fi
    installed=$(flatpak list --app --columns=application)
    while IFS= read -r app; do
        app=$(echo "$app" | xargs)
        [[ -z "$app" || "$app" == \#* ]] && continue
        if echo "$installed" | grep -q "^${app}$"; then
            echo "Already installed: $app"
        else
            echo "Installing: $app"
            flatpak install --user -y flathub "$app"
        fi
    done < build_files/flatpaks.txt
    echo "Done. All Flatpaks installed."

# Runs shell check on all Bash scripts
lint:
    #!/usr/bin/env bash
    set -eoux pipefail
    # Check if shellcheck is installed
    if ! command -v shellcheck &> /dev/null; then
        echo "shellcheck could not be found. Please install it."
        exit 1
    fi
    # Run shellcheck on all Bash scripts
    /usr/bin/find . -iname "*.sh" -type f -exec shellcheck "{}" ';'

# Runs shfmt on all Bash scripts
format:
    #!/usr/bin/env bash
    set -eoux pipefail
    # Check if shfmt is installed
    if ! command -v shfmt &> /dev/null; then
        echo "shellcheck could not be found. Please install it."
        exit 1
    fi
    # Run shfmt on all Bash scripts
    /usr/bin/find . -iname "*.sh" -type f -exec shfmt --write "{}" ';'
