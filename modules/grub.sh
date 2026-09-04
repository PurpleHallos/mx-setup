#!/bin/bash
# GRUB kernel command-line tweaks. Secure Boot is enabled on this machine, but
# this only edits GRUB_CMDLINE_LINUX_DEFAULT in /etc/default/grub - a plain
# text boot parameter, not a kernel/module binary - so it never touches
# anything that needs to be signed. Keep it that way: no DKMS, kernel module,
# or shim/MOK signing changes belong in this module.

run_grub_setup() {
    log "=== GRUB command-line setup ==="
    quiet_boot_loglevel
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
