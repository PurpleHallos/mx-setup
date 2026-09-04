#!/bin/bash
# Devops tooling not tied to the desktop or general apps: Docker CE + Compose
# v2, Vagrant, and Terraform. All three ship from vendor apt repos rather
# than Debian's own (stale/absent there), via the shared `add_apt_repo`
# helper in lib/common.sh (originally apps.sh's `_apps_add_repo`, promoted
# once a second module needed it).
#
# Verified on this machine (2026-09, trixie):
#  * Docker: Debian's own `docker.io` package lags upstream, so this installs
#    Docker CE from Docker's own apt repo instead, same shape as apps.sh's
#    gh/Spotify/VirtualBox repos. Pulls in the Compose v2 plugin (`docker
#    compose`, not the old standalone `docker-compose` binary) and Buildx
#    alongside the engine/CLI/containerd, enables+starts the `docker`
#    systemd service, and adds $USER to the `docker` group so `docker`/
#    `docker compose` work without `sudo` (needs a re-login, or `newgrp
#    docker`, to take effect - same as apps.sh's VirtualBox/vboxusers case).
#  * Vagrant and Terraform both ship from the same HashiCorp apt repo
#    (apt.releases.hashicorp.com), so one repo add covers both packages.
#    Vagrant's default provider is VirtualBox, which apps.sh installs
#    separately (`./main.sh apps`) - install that too if Vagrant boxes need
#    to actually run here.
#  * None of the three touch Secure Boot, DKMS, or the kernel directly -
#    Vagrant's VirtualBox provider inherits whatever apps.sh's VirtualBox
#    install already resolved (see that module's header for the
#    vboxconfig/Secure Boot caveat); this module doesn't re-check it.
#  * jq is Debian's actual jq package - no naming collision there. yq is a
#    different story: Debian's `yq` apt package is a Python tool with its own
#    syntax, but the one most devops workflows mean by "yq" is Mike Farah's
#    Go tool (`mikefarah/yq`), which isn't in Debian's repos at all. This
#    installs that one instead, as a single static binary from its GitHub
#    release straight to /usr/local/bin/yq (tag resolved from the GitHub
#    API) - /usr/local/bin already wins over /usr/bin on PATH here, so it
#    shadows Debian's yq if that's ever installed too, and the
#    version-string check below only recognizes this one as "already
#    installed".
#  * kubectl: installed as the single static binary from dl.k8s.io (the
#    official non-apt route), not from Kubernetes' apt repo - that repo is
#    pinned to one minor version per source line (e.g. v1.34) and needs
#    manual bumping across minors, whereas dl.k8s.io/release/stable.txt
#    always resolves to the current latest stable release. sha256-verified
#    against the checksum dl.k8s.io publishes alongside it before install.
#  * helm: the official get-helm-3 install script (helm/helm on GitHub),
#    same "official curl/sh installer" shape as apps.sh's Zed/spicetify -
#    it resolves the latest release and handles the /usr/local/bin/helm
#    install (with its own internal sudo) itself.
#  * Neither talks to a cluster on its own - kubectl/helm are just client
#    binaries, no local cluster is installed or implied by this module.

run_devops_setup() {
    log "=== Installing devops tooling ==="

    install_if_missing jq

    if dry; then
        log "[dry] add the Docker CE apt repo, install docker-ce/docker-ce-cli/"
        log "[dry] containerd.io/docker-buildx-plugin/docker-compose-plugin,"
        log "[dry] enable+start the docker service, and add $USER to the docker group"
        log "[dry] add the HashiCorp apt repo, install vagrant and terraform"
        log "[dry] install mikefarah/yq to /usr/local/bin/yq"
        log "[dry] install kubectl (dl.k8s.io, sha256-verified) to /usr/local/bin/kubectl"
        log "[dry] install helm via its official get-helm-3 script"
        return 0
    fi

    # Independent installs - one failing (we're under set -e) must not abort
    # the rest, same reasoning as apps.sh's list.
    _devops_install_docker    || warn "Docker install failed, continuing"
    _devops_install_terraform || warn "Terraform install failed, continuing"
    _devops_install_vagrant   || warn "Vagrant install failed, continuing"
    _devops_install_yq        || warn "yq install failed, continuing"
    _devops_install_kubectl   || warn "kubectl install failed, continuing"
    _devops_install_helm      || warn "helm install failed, continuing"

    log "Devops tooling installed."
}

# ---------------------------------------------------------------------------
# Docker CE + Compose v2, from Docker's own apt repo.
# ---------------------------------------------------------------------------
_devops_install_docker() {
    if command -v docker >/dev/null; then
        warn "Docker already installed ($(docker --version 2>/dev/null)), skipping"
    else
        log "Adding the Docker CE repo (Debian's docker.io lags upstream)"
        local codename
        codename="$(. /etc/os-release && echo "$VERSION_CODENAME")"
        add_apt_repo "docker" \
            "https://download.docker.com/linux/debian/gpg" \
            "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $codename stable"

        log "Installing Docker CE, containerd, Buildx and the Compose plugin"
        sudo apt-get install -y \
            docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

        sudo systemctl enable --now docker
        log "Docker installed ($(docker --version 2>/dev/null)); 'docker compose version' for Compose"
    fi

    # Runs even when Docker was already installed - see the header note on
    # ensure_user_in_group in lib/common.sh for why.
    ensure_user_in_group docker
}

# ---------------------------------------------------------------------------
# HashiCorp's apt repo, shared by Terraform and Vagrant below. Idempotent -
# safe to call from both without double-adding the repo.
# ---------------------------------------------------------------------------
_devops_add_hashicorp_repo() {
    [[ -f /etc/apt/sources.list.d/hashicorp.list ]] && return 0

    log "Adding the HashiCorp apt repo"
    local codename
    codename="$(. /etc/os-release && echo "$VERSION_CODENAME")"
    add_apt_repo "hashicorp" \
        "https://apt.releases.hashicorp.com/gpg" \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/hashicorp.gpg] https://apt.releases.hashicorp.com $codename main"
}

_devops_install_terraform() {
    if command -v terraform >/dev/null; then
        warn "Terraform already installed ($(terraform version 2>/dev/null | head -1)), skipping"
        return 0
    fi

    _devops_add_hashicorp_repo
    log "Installing Terraform"
    sudo apt-get install -y terraform
}

_devops_install_vagrant() {
    if command -v vagrant >/dev/null; then
        warn "Vagrant already installed ($(vagrant --version 2>/dev/null)), skipping"
        return 0
    fi

    _devops_add_hashicorp_repo
    log "Installing Vagrant"
    sudo apt-get install -y vagrant
}

# ---------------------------------------------------------------------------
# yq (mikefarah/yq), from its GitHub release - not the Python yq Debian ships.
# See the header note on why the version-string check matters here.
# ---------------------------------------------------------------------------
_devops_install_yq() {
    if command -v yq >/dev/null; then
        if yq --version 2>/dev/null | grep -q 'mikefarah/yq'; then
            warn "yq already installed ($(yq --version 2>/dev/null)), skipping"
            return 0
        fi
        warn "a different 'yq' is already on PATH ($(command -v yq)) - installing" \
             "mikefarah/yq to /usr/local/bin/yq will take precedence over it"
    fi

    local tag
    tag="$(curl -fsSL -m 30 "https://api.github.com/repos/mikefarah/yq/releases/latest" \
           | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
    if [[ -z "$tag" ]]; then
        err "Could not resolve the latest yq release - skipping"
        return 1
    fi

    log "Installing yq $tag to /usr/local/bin/yq"
    local tmp
    tmp="$(mktemp)"
    if ! curl -fL -m 120 \
        "https://github.com/mikefarah/yq/releases/download/${tag}/yq_linux_amd64" \
        -o "$tmp"; then
        err "yq download failed"
        rm -f "$tmp"
        return 1
    fi
    chmod +x "$tmp"
    sudo mv "$tmp" /usr/local/bin/yq
    log "yq installed ($(yq --version 2>/dev/null))"
}

# ---------------------------------------------------------------------------
# kubectl, from dl.k8s.io's stable release channel (not the version-pinned
# apt repo - see the header note). sha256-verified before install.
# ---------------------------------------------------------------------------
_devops_install_kubectl() {
    if command -v kubectl >/dev/null; then
        warn "kubectl already installed ($(kubectl version --client 2>/dev/null | head -1)), skipping"
        return 0
    fi

    local ver
    ver="$(curl -fsSL -m 30 https://dl.k8s.io/release/stable.txt)"
    if [[ -z "$ver" ]]; then
        err "Could not resolve the latest stable kubectl release - skipping"
        return 1
    fi

    log "Installing kubectl $ver to /usr/local/bin/kubectl"
    local tmp
    tmp="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap "rm -rf '$tmp'" RETURN

    if ! curl -fL -m 120 "https://dl.k8s.io/release/${ver}/bin/linux/amd64/kubectl" \
        -o "$tmp/kubectl"; then
        err "kubectl download failed"
        return 1
    fi
    if ! curl -fL -m 30 "https://dl.k8s.io/release/${ver}/bin/linux/amd64/kubectl.sha256" \
        -o "$tmp/kubectl.sha256"; then
        err "kubectl checksum download failed"
        return 1
    fi
    if ! (cd "$tmp" && echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check --status); then
        err "kubectl checksum verification failed - not installing"
        return 1
    fi

    sudo install -o root -g root -m 0755 "$tmp/kubectl" /usr/local/bin/kubectl
    log "kubectl installed ($(kubectl version --client 2>/dev/null | head -1))"
}

# ---------------------------------------------------------------------------
# Helm, via the official get-helm-3 install script.
# ---------------------------------------------------------------------------
_devops_install_helm() {
    if command -v helm >/dev/null; then
        warn "Helm already installed ($(helm version --short 2>/dev/null)), skipping"
        return 0
    fi

    log "Installing Helm (official get-helm-3 script)"
    if ! curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash; then
        err "Helm install failed"
        return 1
    fi
    log "Helm installed ($(helm version --short 2>/dev/null))"
}
