#!/bin/bash
# Applies KDE keyboard shortcuts from stuff/shortcuts/.
# Based on Arco Linux's KDE Plasma shortcut layout - ported unchanged from
# the sibling mx-setup repo's modules/shortcuts.sh.
#
# stuff/shortcuts/kglobalshortcutsrc and khotkeysrc ARE committed here (unlike
# mx-setup, which gitignores its own stuff/ - its copy was missing on disk
# when this module was ported over, and it's an unmodified public template
# rather than anything personal, so there was no reason to hide it here too).
# Fetched from etc/skel/.config/{kglobalshortcutsrc,khotkeysrc} in
# https://github.com/arcolinux/arcolinux-plasma. If they're ever missing (a
# stripped-down checkout, say), this warns and returns 1 rather than failing
# the whole run.

run_shortcuts_setup() {
    log "=== Applying KDE keyboard shortcuts ==="

    if dry; then
        log "[dry] would copy kglobalshortcutsrc and khotkeysrc to ~/.config/"
        return
    fi

    local src
    src="$(pwd)/stuff/shortcuts"

    [[ -f "$src/kglobalshortcutsrc" ]] || { warn "kglobalshortcutsrc not found in $src"; return 1; }
    [[ -f "$src/khotkeysrc" ]]         || { warn "khotkeysrc not found in $src"; return 1; }

    cp "$src/kglobalshortcutsrc" ~/.config/kglobalshortcutsrc
    cp "$src/khotkeysrc"         ~/.config/khotkeysrc

    # Signal KDE to pick up the new bindings if a session is running
    qdbus6 org.kde.khotkeys /modules/khotkeys \
        org.kde.khotkeys.reread_configuration 2>/dev/null || true
    dbus-send --session --type=signal /KGlobalSettings \
        org.kde.KGlobalSettings.notifyChange int32:3 int32:0 2>/dev/null || true

    log "Keyboard shortcuts applied. Log out and back in for full effect."
}
