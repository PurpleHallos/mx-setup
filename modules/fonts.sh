#!/bin/bash
# Sets the system UI font to Ubuntu (https://fonts.google.com/specimen/Ubuntu,
# packaged for Debian/MX as fonts-ubuntu) and installs JetBrainsMono Nerd Font
# for the fixed/monospace font. Family name below ("JetBrainsMono Nerd Font
# Mono") matches what mx-setup's themes.sh already assumes is installed for
# its Graphite theme, and what its Hack Nerd Font install (same module,
# different font) does per-user under ~/.local/share/fonts - no sudo needed
# either way.

FONTS_JETBRAINS_URL="https://github.com/ryanoasis/nerd-fonts/releases/download/v3.5.1/JetBrainsMono.zip"
FONTS_JETBRAINS_DIR="$HOME/.local/share/fonts/JetBrainsMonoNerdFont"
FONTS_MONO_FAMILY="JetBrainsMono Nerd Font Mono"
FONTS_UI_PKG="fonts-ubuntu"
FONTS_UI_FAMILY="Ubuntu"
FONTS_SIZE=10

run_fonts_setup() {
    log "=== Installing Ubuntu font (system UI) and JetBrainsMono Nerd Font (fixed/mono) ==="

    if dry; then
        log "[dry] would apt-install $FONTS_UI_PKG and download $FONTS_JETBRAINS_URL to $FONTS_JETBRAINS_DIR,"
        log "[dry] refresh the font cache, and set $FONTS_UI_FAMILY as the KDE + GTK system font"
        log "[dry] ($FONTS_MONO_FAMILY as the fixed/monospace font)"
        return 0
    fi

    install_if_missing "$FONTS_UI_PKG"

    if ! _fonts_install_jetbrains; then
        err "JetBrainsMono Nerd Font not installed - leaving the fixed/monospace font unchanged"
        return 1
    fi
    _fonts_apply_system_font

    log "Ubuntu font set as system font; JetBrainsMono Nerd Font installed for fixed/monospace."
}

_fonts_install_jetbrains() {
    if compgen -G "$FONTS_JETBRAINS_DIR/JetBrainsMonoNerdFont-Regular.ttf" >/dev/null; then
        warn "JetBrainsMono Nerd Font already installed, skipping download"
        return 0
    fi

    log "Downloading JetBrainsMono Nerd Font v3.5.1 (~130MB)"
    local tmp
    tmp="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap "rm -rf '$tmp'" RETURN

    # -C - resumes a partial download across retries; this file is ~130MB and
    # this machine's link has been seen sustaining well under 1MB/s, so a
    # short timeout here just fails a perfectly good download in progress.
    if ! curl -fL --progress-bar --retry 3 --retry-delay 5 -C - \
        -m 1800 "$FONTS_JETBRAINS_URL" -o "$tmp/JetBrainsMono.zip"; then
        err "JetBrainsMono Nerd Font download failed"
        return 1
    fi

    mkdir -p "$FONTS_JETBRAINS_DIR"
    unzip -oq "$tmp/JetBrainsMono.zip" -d "$FONTS_JETBRAINS_DIR" '*.ttf'
    fc-cache -f "$FONTS_JETBRAINS_DIR" >/dev/null 2>&1
    log "JetBrainsMono Nerd Font installed to $FONTS_JETBRAINS_DIR"
}

# KDE General/fixed fonts, GTK 3 font, and the GNOME-settings-schema keys GTK
# apps read under Wayland (same keys mx-setup's theme-switch writes) - no
# logout needed, but some already-open apps only pick it up on restart.
_fonts_apply_system_font() {
    log "Setting $FONTS_UI_FAMILY as the system font (KDE + GTK), $FONTS_MONO_FAMILY as fixed/monospace"

    kwriteconfig6 --file kdeglobals --group General --key font  "$FONTS_UI_FAMILY,$FONTS_SIZE,-1,5,400,0,0,0,0,0,Regular"
    kwriteconfig6 --file kdeglobals --group General --key fixed "$FONTS_MONO_FAMILY,$FONTS_SIZE,-1,5,400,0,0,0,0,0,Regular"

    mkdir -p "$HOME/.config/gtk-3.0"
    kwriteconfig6 --file gtk-3.0/settings.ini --group Settings --key gtk-font-name "$FONTS_UI_FAMILY $FONTS_SIZE"

    gsettings set org.gnome.desktop.interface font-name           "$FONTS_UI_FAMILY $FONTS_SIZE"    2>/dev/null || true
    gsettings set org.gnome.desktop.interface monospace-font-name "$FONTS_MONO_FAMILY $FONTS_SIZE" 2>/dev/null || true
}
