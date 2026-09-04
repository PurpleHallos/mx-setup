#!/bin/bash
# Shared helpers sourced by main.sh and every module.

log()  { echo -e "\033[1;32m[+]\033[0m $*"; }
warn() { echo -e "\033[1;33m[!]\033[0m $*"; }
err()  { echo -e "\033[1;31m[-]\033[0m $*" >&2; }

# ---------------------------------------------------------------------------
# Dry run
#
# DRYRUN=1 (env, or --dry-run on main.sh) makes every mutating command print
# instead of execute.
# ---------------------------------------------------------------------------
DRYRUN="${DRYRUN:-0}"
export DRYRUN

dry() { [[ "$DRYRUN" == "1" ]]; }

# Run a command, or just show it under DRYRUN=1. Every apt/rm/systemctl call
# in the modules goes through this, so a dry run touches nothing at all.
run() {
    if dry; then
        echo -e "\033[1;34m[dry]\033[0m $(printf '%q ' "$@")"
        return 0
    fi
    "$@"
}

# Purge one or more packages, each of which may be a shell-style glob. Only the
# packages dpkg actually knows about are passed to apt, so a re-run (everything
# already gone) or a glob that matches nothing is a clean no-op instead of an
# apt error: `apt-get purge 'glob*'` returns 100 when nothing matches, and
# `apt-get purge <unknown-pkg>` does too - either of which would abort the whole
# run under `set -e`. An already-removed but still-known package returns 0 and is
# harmless to include, so the filter only has to drop the truly-absent ones.
purge_pkgs() {
    local pat name
    local -a matched=()
    for pat in "$@"; do
        # dpkg-query -W expands globs against installed/config-remaining packages;
        # it prints nothing (and errors to stderr, dropped) when none match.
        while IFS= read -r name; do
            [[ -n "$name" ]] && matched+=("$name")
        done < <(dpkg-query -W -f='${Package}\n' "$pat" 2>/dev/null)
    done
    if [[ ${#matched[@]} -eq 0 ]]; then
        warn "none of [$*] present, skipping"
        return 0
    fi
    run sudo apt-get purge -y "${matched[@]}"
}

# Prompt for the sudo password once, up front, and keep the credential warm in
# the background so a long unattended run never stops half-way to re-ask. The
# keep-alive subshell watches the main script's PID and exits when it does; an
# EXIT trap also tears it down. No-op under a dry run, which touches nothing.
require_sudo() {
    dry && return 0
    log "Priming sudo - you'll be asked for your password once, up front"
    if ! sudo -v; then
        err "sudo authentication failed"
        return 1
    fi
    # $$ inside the subshell is still the main shell's PID, so this stops once
    # main.sh exits. Refresh well inside the default 15-minute sudo timeout.
    ( while kill -0 "$$" 2>/dev/null; do sudo -n true 2>/dev/null; sleep 50; done ) &
    SUDO_KEEPALIVE_PID=$!
    trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null' EXIT
}

install_if_missing() {
    local pkg="$1"
    if ! dpkg -s "$pkg" &>/dev/null; then
        log "Installing $pkg"
        run sudo apt-get install -y "$pkg"
    else
        warn "$pkg already installed, skipping"
    fi
}

# ---------------------------------------------------------------------------
# Add $USER to a system group if not already a member. Deliberately called
# unconditionally by callers (not skipped when the package that needs the
# group was already installed) - an "already installed, skipping" early
# return must never also skip group membership, or a machine where e.g.
# Docker/VirtualBox pre-existed would never get $USER into docker/vboxusers.
#   $1 group name
# ---------------------------------------------------------------------------
ensure_user_in_group() {
    local group="$1"
    if id -nG "$USER" | tr ' ' '\n' | grep -qx "$group"; then
        warn "$USER already in the $group group, skipping"
        return 0
    fi
    log "Adding $USER to the $group group (re-login, or 'newgrp $group', for it to take effect)"
    run sudo usermod -aG "$group" "$USER"
}

# ---------------------------------------------------------------------------
# Add a signed apt repository. Keyring in /etc/apt/keyrings, one .list file, and
# an index refresh scoped to just that list so the whole of apt isn't re-fetched.
# Shared by any module that needs a vendor repo (apps.sh's gh/Spotify/
# VirtualBox, devops.sh's Docker/HashiCorp).
#   $1 name (used for the file names)  $2 key URL  $3 the deb line
# ---------------------------------------------------------------------------
add_apt_repo() {
    local name="$1" key_url="$2" deb_line="$3"
    local keyring="/etc/apt/keyrings/${name}.gpg"
    local list="/etc/apt/sources.list.d/${name}.list"

    sudo install -d -m 0755 /etc/apt/keyrings
    curl -fsSL "$key_url" | sudo gpg --dearmor --yes -o "$keyring"
    sudo chmod go+r "$keyring"
    echo "$deb_line" | sudo tee "$list" >/dev/null

    sudo apt-get update \
        -o Dir::Etc::sourcelist="$list" \
        -o Dir::Etc::sourceparts=/dev/null \
        -o APT::Get::List-Cleanup=0 >/dev/null
}

# ---------------------------------------------------------------------------
# Restore point
#
# Taken before anything destructive runs. A snapshot that silently failed is
# worse than no snapshot, so a failure here ABORTS the run — set
# SKIP_SNAPSHOT=1 to proceed deliberately without one (e.g. on a throwaway VM).
# ---------------------------------------------------------------------------
require_snapshot() {
    local tag="${1:-new-setup}"

    if [[ "${SKIP_SNAPSHOT:-0}" == "1" ]]; then
        warn "SKIP_SNAPSHOT=1 - continuing with no restore point"
        return 0
    fi
    if dry; then
        log "[dry] would take a Timeshift snapshot: $tag"
        return 0
    fi
    local reply
    read -r -p "Take a Timeshift snapshot before continuing? [Y/n] " reply
    if [[ "${reply,,}" == "n" || "${reply,,}" == "no" ]]; then
        warn "Skipping snapshot - no restore point will be taken."
        return 0
    fi
    if ! command -v timeshift >/dev/null; then
        err "timeshift not installed - no restore point can be taken."
        err "Install it (sudo apt-get install timeshift) or re-run with SKIP_SNAPSHOT=1."
        return 1
    fi

    log "Taking Timeshift snapshot: $tag"
    if ! sudo timeshift --create --comments "$tag" --tags O; then
        err "Snapshot failed - aborting before anything is removed."
        err "Configure a snapshot device in Timeshift, or re-run with SKIP_SNAPSHOT=1."
        return 1
    fi
    log "Snapshot created."
}
