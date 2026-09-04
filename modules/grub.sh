#!/bin/bash
# GRUB kernel command-line tweaks and the boot theme. Secure Boot is enabled
# on this machine; none of this touches anything that needs to be signed -
# GRUB_CMDLINE_LINUX_DEFAULT is a plain text boot parameter, and a GRUB theme
# is just data (background/fonts/theme.txt) that grub itself reads at boot,
# not a kernel module or boot-chain binary. Keep it that way: no DKMS, kernel
# module, or shim/MOK signing changes belong in this module.

GRUB_THEME_REPO="https://github.com/PurpleHallos/Particle-circle-grub-theme.git"
GRUB_THEME_NAME="grub-theme-sidebar" # install.sh's THEME_NAME-THEME_VARIANT, sidebar is the only variant
GRUB_THEME_SCREEN="1600p" # matches this machine's 2560x1600 panel

run_grub_setup() {
    log "=== GRUB command-line setup ==="
    quiet_boot_loglevel
    install_grub_theme
}

# Suppresses most kernel boot log spam on top of the distro-default "quiet
# splash" so the framebuffer boot screen stays clean. loglevel=3 only shows
# KERN_ERR and worse; nothing below that is hidden from `journalctl -b` or
# `dmesg`, it just isn't printed to the console during boot.
quiet_boot_loglevel() {
    local grub_file="/etc/default/grub"

    if ! grep -qxF 'GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"' "$grub_file"; then
        warn "GRUB_CMDLINE_LINUX_DEFAULT in $grub_file doesn't match the expected" \
             '"quiet splash" (already changed, or a different distro default) - skipping'
        return 0
    fi

    log "Adding loglevel=3 to GRUB_CMDLINE_LINUX_DEFAULT"
    run sudo sed -i \
        's/^GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"$/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash loglevel=3"/' \
        "$grub_file"
    run sudo update-grub
}

# Installs the Particle Circle sidebar GRUB theme from
# https://github.com/PurpleHallos/Particle-circle-grub-theme into
# /usr/share/grub/themes (install.sh's default, non-'-b' location - this repo
# doesn't use '-b' since GRUB_DIR here is already grub's own theme dir, not
# something under /boot). install.sh itself points GRUB_THEME at it in
# /etc/default/grub and runs update-grub, and self-elevates via sudo when not
# already root - sudo is primed passwordless by main.sh's require_sudo, so it
# proceeds without a second password prompt.
install_grub_theme() {
    log "=== Installing the Particle Circle GRUB theme ==="

    local theme_dir="/usr/share/grub/themes/${GRUB_THEME_NAME}"

    if dry; then
        log "[dry] would clone $GRUB_THEME_REPO and run its install.sh -t sidebar -s $GRUB_THEME_SCREEN"
        log "[dry] (installs into $theme_dir, points GRUB_THEME at it, runs update-grub)"
        return 0
    fi

    if [[ -f "$theme_dir/theme.txt" ]]; then
        warn "GRUB theme already installed at $theme_dir, skipping"
        return 0
    fi

    install_if_missing imagemagick

    local tmp
    tmp="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap "rm -rf '$tmp'" RETURN

    log "Cloning Particle Circle GRUB theme"
    if ! git clone --depth 1 -q "$GRUB_THEME_REPO" "$tmp/grub-theme"; then
        err "GRUB theme clone failed"
        return 1
    fi

    (cd "$tmp/grub-theme" && ./install.sh -t sidebar -s "$GRUB_THEME_SCREEN")
    log "GRUB theme installed to $theme_dir"
}
