#!/bin/bash
# Catppuccin Mocha across the desktop: the KDE global theme, the SDDM login
# theme with a chosen wallpaper, and Papirus-Dark icons. Also three
# desktop-layout tweaks that aren't a Catppuccin thing at all, just chosen in
# the same sitting: moving the Plasma panel to the top of the screen at
# 23px, expanding virtual desktops from a 1x2 to a 2x2 grid, and pulling the
# system accent color from the desktop wallpaper instead of a fixed choice.
# All of this was picked, applied and hand-verified interactively before
# this module was written - see each function's header for exactly what was
# checked and how.

THEME_CATPPUCCIN_KDE_REPO="https://github.com/catppuccin/kde.git"
# install.sh args: Flavour(1-4) Accent(1-14) WindowDecoration(1-2) auto
#   1=Mocha (darkest of the 4 flavours: Mocha/Macchiato/Frappe/Latte)
#   13=Blue (started on 4=Mauve, switched after noticing the active-task/
#     selection highlight it produced clashed with other panel icons;
#     the KDE global theme's own accent barely matters past this point
#     anyway, since _theme_configure_accent_from_wallpaper below overrides
#     the live Selection/Highlight color with one pulled from the wallpaper -
#     Blue is just what the color scheme + cursors + splash stay pinned to)
#   2=Classic (macOS-like button layout; 1=Modern has button-placement
#     quirks the installer itself warns about)
THEME_CATPPUCCIN_FLAVOUR=1
THEME_CATPPUCCIN_ACCENT=13
THEME_CATPPUCCIN_WINDECO=2

# Pinned release, not "latest" - same reasoning as the JetBrainsMono release
# pin in modules/fonts.sh. Re-checked against catppuccin/sddm's releases API
# when bumping this.
THEME_SDDM_RELEASE_URL="https://github.com/catppuccin/sddm/releases/download/v1.1.2/catppuccin-mocha-blue-sddm.zip"
THEME_SDDM_THEME_NAME="catppuccin-mocha-blue"
THEME_SDDM_WALLPAPER_ASSET="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/assets/sddm-background.jpg"

THEME_ICON_THEME="Papirus-Dark"
# Not on $PATH - it's a libexec helper bundled with plasma-workspace, found
# by searching the filesystem for it on this machine (Plasma 6, amd64).
THEME_PLASMA_CHANGEICONS="/usr/lib/x86_64-linux-gnu/libexec/plasma-changeicons"

# Bibata-Modern-Classic (https://store.kde.org/p/1914825) isn't packaged for
# apt, so - same reasoning as THEME_SDDM_WALLPAPER_ASSET above - the exact
# tarball is vendored into assets/ rather than fetched fresh each run (the
# KDE Store's product page is behind Anubis anti-bot protection, so an
# automated download URL for it isn't reliably scriptable anyway).
THEME_CURSOR_NAME="Bibata-Modern-Classic"
THEME_CURSOR_ASSET="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/assets/Bibata-Modern-Classic.tar.xz"

# Started as 2 desktops in 2 rows (1 per row); target is 4 in a 2x2 grid
# (2 per row) - "add one more to each row".
THEME_DESKTOP_COUNT=4
THEME_DESKTOP_ROWS=2

run_theme_setup() {
    log "=== Setting up the Catppuccin Mocha theme ==="

    if dry; then
        log "[dry] would install the Catppuccin KDE global theme (Mocha, Blue accent, Classic decorations)"
        log "[dry] would install the Catppuccin SDDM login theme with $THEME_SDDM_WALLPAPER_ASSET as its background"
        log "[dry] would install $THEME_ICON_THEME icons and set them as the active icon theme"
        log "[dry] would install $THEME_CURSOR_NAME as the cursor theme, for both Plasma and SDDM"
        log "[dry] would move the Plasma panel to the top of the screen and set it to 23px"
        log "[dry] would expand virtual desktops to a $THEME_DESKTOP_COUNT-desktop, $THEME_DESKTOP_ROWS-row grid"
        log "[dry] would enable the Wobbly Windows, Magic Lamp and Slide Back KWin effects"
        log "[dry] would set the system accent color to derive from the wallpaper"
        return 0
    fi

    _theme_install_catppuccin_kde
    _theme_install_catppuccin_sddm
    _theme_install_papirus_icons
    _theme_install_cursor
    _theme_configure_panel
    _theme_configure_virtual_desktops
    _theme_enable_kwin_effects
    _theme_configure_accent_from_wallpaper

    log "Theme setup done. SDDM changes need a logout/login to fully show."
}

# Catppuccin's own install.sh is safe and cheap to re-run (it just re-copies
# its files and re-applies), so this always runs it rather than guarding on
# something already being installed - re-running this module is exactly how
# you'd pick different choices later.
#
# Verified interactively before being scripted here: kpackagetool6,
# kwriteconfig6 and plasma-apply-lookandfeel (the tools install.sh's "auto"
# mode shells out to) are all already present on this machine as part of
# Plasma 6 itself - no apt install needed. After running, confirmed live via
# `kreadconfig6 --file kdeglobals --group General --key ColorScheme`
# (CatppuccinMochaBlue), the Aurorae theme in kwinrc, and cursorTheme in
# kcminputrc - all matched what install.sh's own defaults file sets. When
# switching accents (this went Mauve -> Blue), the old accent's now-orphaned
# global-theme package, color scheme file and cursor directory are removed
# by hand afterward - install.sh has no "uninstall previous accent" step of
# its own, since it doesn't assume you're replacing anything.
_theme_install_catppuccin_kde() {
    if ! command -v kpackagetool6 >/dev/null || ! command -v plasma-apply-lookandfeel >/dev/null; then
        warn "kpackagetool6/plasma-apply-lookandfeel not found, skipping Catppuccin KDE theme"
        return 1
    fi

    log "Installing the Catppuccin KDE global theme"
    local tmp
    tmp="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap "rm -rf '$tmp'" RETURN

    git clone --depth=1 -q "$THEME_CATPPUCCIN_KDE_REPO" "$tmp/catppuccin-kde" \
        || { err "Catppuccin KDE clone failed"; return 1; }
    (
        cd "$tmp/catppuccin-kde" &&
        chmod +x install.sh &&
        ./install.sh "$THEME_CATPPUCCIN_FLAVOUR" "$THEME_CATPPUCCIN_ACCENT" "$THEME_CATPPUCCIN_WINDECO" auto
    )

    _theme_prune_stale_accents
}

# install.sh has no "uninstall the previous accent" step - it only ever adds.
# Re-running this module after changing THEME_CATPPUCCIN_ACCENT would
# otherwise leave the old accent's global-theme package, color scheme file
# and cursor directory orphaned on disk (harmless, just clutter - matches
# what was cleaned up by hand the first time this was switched, Mauve ->
# Blue). catppuccin-mocha-dark-cursors is never touched: it's shared across
# every accent for this flavour, not accent-specific.
_theme_prune_stale_accents() {
    local accent_name
    case "$THEME_CATPPUCCIN_ACCENT" in
        1) accent_name=Rosewater ;; 2) accent_name=Flamingo ;; 3) accent_name=Pink ;;
        4) accent_name=Mauve ;; 5) accent_name=Red ;; 6) accent_name=Maroon ;;
        7) accent_name=Peach ;; 8) accent_name=Yellow ;; 9) accent_name=Green ;;
        10) accent_name=Teal ;; 11) accent_name=Sky ;; 12) accent_name=Sapphire ;;
        13) accent_name=Blue ;; 14) accent_name=Lavender ;;
        *) warn "Unknown accent number $THEME_CATPPUCCIN_ACCENT, skipping stale-accent cleanup"; return 1 ;;
    esac

    local dir
    for dir in ~/.local/share/plasma/look-and-feel/Catppuccin-Mocha-*; do
        [[ -d "$dir" && "$(basename "$dir")" != "Catppuccin-Mocha-$accent_name" ]] && rm -rf "$dir"
    done
    for dir in ~/.local/share/color-schemes/CatppuccinMocha*.colors; do
        [[ -f "$dir" && "$(basename "$dir")" != "CatppuccinMocha$accent_name.colors" ]] && rm -f "$dir"
    done
    for dir in ~/.local/share/icons/catppuccin-mocha-*-cursors; do
        [[ -d "$dir" ]] || continue
        [[ "$(basename "$dir")" == "catppuccin-mocha-dark-cursors" ]] && continue
        [[ "$(basename "$dir")" != "catppuccin-mocha-${accent_name,,}-cursors" ]] && rm -rf "$dir"
    done
}

# stuff/shortcuts is a precedent for committed, non-personal vendored data;
# THEME_SDDM_WALLPAPER_ASSET (assets/sddm-background.jpg) follows the same
# reasoning modules/fastfetch.sh's logo asset does - a specific picture
# chosen by hand, pinned into the repo rather than fetched fresh each run
# (source: https://wallhaven.cc/w/l8p6dy).
#
# Verified interactively: this machine's sddm-greeter is sddm-greeter-qt6
# (confirmed via `ldd`), matching this theme's QtVersion=6 requirement, and
# every qml6-module-qtquick-* dependency the theme's Main.qml/Components need
# is already installed as part of Plasma 6 - the README's Debian dependency
# list (qml-module-qtquick-*, no "6") targets a Qt5 SDDM greeter and doesn't
# apply here. Rendering was confirmed with
# `sddm-greeter-qt6 --test-mode --theme /usr/share/sddm/themes/$THEME_SDDM_THEME_NAME`
# (no QML errors; the one harmless warning about
# /var/lib/AccountsService/icons/ is for the user icon, which this theme's
# own theme.conf has UserIcon="false" for, so it's never shown).
_theme_install_catppuccin_sddm() {
    if [[ -d "/usr/share/sddm/themes/$THEME_SDDM_THEME_NAME" ]]; then
        warn "$THEME_SDDM_THEME_NAME SDDM theme already installed, skipping (re-applying activation below)"
    else
        if ! command -v unzip >/dev/null; then
            warn "unzip not found, skipping Catppuccin SDDM theme"
            return 1
        fi

        log "Installing the Catppuccin SDDM login theme"
        local tmp
        tmp="$(mktemp -d)"
        # shellcheck disable=SC2064
        trap "rm -rf '$tmp'" RETURN

        curl -fsSL -m 60 --retry 2 -o "$tmp/sddm-theme.zip" "$THEME_SDDM_RELEASE_URL" \
            || { err "Catppuccin SDDM theme download failed"; return 1; }
        unzip -q "$tmp/sddm-theme.zip" -d "$tmp" \
            || { err "Catppuccin SDDM theme extraction failed"; return 1; }

        if [[ -f "$THEME_SDDM_WALLPAPER_ASSET" ]]; then
            # theme.conf ships with CustomBackground="true" and
            # Background="backgrounds/wall.png" already - overwriting that
            # exact file means theme.conf needs no edits at all. Format
            # doesn't need to match the .png extension; Qt's image loader
            # detects it from content (confirmed: this file is really a
            # JPEG, kept that way to keep the repo asset small).
            cp "$THEME_SDDM_WALLPAPER_ASSET" "$tmp/$THEME_SDDM_THEME_NAME/backgrounds/wall.png"
        else
            warn "$THEME_SDDM_WALLPAPER_ASSET not found - leaving the theme's default background"
        fi

        sudo mv "$tmp/$THEME_SDDM_THEME_NAME" /usr/share/sddm/themes/ \
            || { err "Installing SDDM theme to /usr/share/sddm/themes/ failed"; return 1; }

        # Same "no uninstall step of its own" gap as the KDE global theme -
        # remove any other accent's SDDM theme dir left over from before.
        local dir
        for dir in /usr/share/sddm/themes/catppuccin-mocha-*; do
            [[ -d "$dir" && "$(basename "$dir")" != "$THEME_SDDM_THEME_NAME" ]] && sudo rm -rf "$dir"
        done
    fi

    _theme_set_sddm_key Current "$THEME_SDDM_THEME_NAME"
}

# Sets a single key= in /etc/sddm.conf's [Theme] section (Current=,
# CursorTheme=, ...) without touching anything else in the file (Autologin,
# Users, etc.) - handles a pre-existing line for that key, a [Theme] section
# with no such line yet, and a file with no [Theme] section at all, so this
# is safe on a from-scratch install too.
_theme_set_sddm_key() {
    local key="$1" value="$2" conf=/etc/sddm.conf

    if ! sudo test -f "$conf"; then
        printf '[Theme]\n%s=%s\n' "$key" "$value" | sudo tee "$conf" >/dev/null
        return
    fi
    if ! sudo grep -q '^\[Theme\]' "$conf"; then
        printf '\n[Theme]\n%s=%s\n' "$key" "$value" | sudo tee -a "$conf" >/dev/null
        return
    fi
    if sudo awk -v k="$key" '/^\[Theme\]/{f=1; next} /^\[/{f=0} f && $0 ~ "^"k"="{found=1} END{exit !found}' "$conf"; then
        sudo sed -i "/^\[Theme\]/,/^\[/ s/^$key=.*/$key=$value/" "$conf"
    else
        sudo sed -i "/^\[Theme\]/a $key=$value" "$conf"
    fi
    log "Set SDDM's $key to $value in $conf"
}

# papirus-icon-theme (the apt package, not a git clone) ships Papirus,
# Papirus-Dark and Papirus-Light together under /usr/share/icons - already
# present on this machine (`dpkg -l papirus-icon-theme`), same as the
# Papirus-mxblue variant that was this machine's icon theme before Papirus-Dark
# was picked here. `apt install` is safe/cheap to re-run if it's ever missing.
# plasma-changeicons (see THEME_PLASMA_CHANGEICONS above) applies the icon
# theme live, the same tool System Settings' icon picker uses - confirmed
# with `kreadconfig6 --file kdeglobals --group Icons --key Theme` reading
# back Papirus-Dark after running it.
_theme_install_papirus_icons() {
    if [[ ! -d "/usr/share/icons/$THEME_ICON_THEME" ]]; then
        log "Installing $THEME_ICON_THEME icons"
        sudo apt-get install -y papirus-icon-theme \
            || { err "papirus-icon-theme install failed"; return 1; }
    fi

    local changeicons="$THEME_PLASMA_CHANGEICONS"
    command -v plasma-changeicons >/dev/null && changeicons=plasma-changeicons
    if [[ -x "$changeicons" ]] || command -v "$changeicons" >/dev/null 2>&1; then
        "$changeicons" "$THEME_ICON_THEME"
        log "Set $THEME_ICON_THEME as the active icon theme"
    else
        warn "plasma-changeicons not found at $THEME_PLASMA_CHANGEICONS - set the icon theme by hand in System Settings"
    fi
}

# Extracted to /usr/share/icons (system-wide, needs sudo) rather than
# ~/.local/share/icons like the icon themes above - the SDDM greeter runs as
# its own user, which can't read into this user's home directory, so the
# cursor theme has to live somewhere it can see too. Same directory works
# for the live Plasma session as well (XDG_DATA_DIRS/icons already covers
# /usr/share/icons), so there's no need for a second, per-user copy.
# plasma-apply-cursortheme (confirmed present on this machine, part of
# plasma-workspace) is the same mechanism System Settings' cursor picker
# uses to apply a theme to the running session live; kwriteconfig6 is the
# fallback if it's ever missing. _theme_set_sddm_key (see above) then points
# the login screen at the same theme.
_theme_install_cursor() {
    if [[ ! -d "/usr/share/icons/$THEME_CURSOR_NAME" ]]; then
        if [[ ! -f "$THEME_CURSOR_ASSET" ]]; then
            warn "$THEME_CURSOR_ASSET not found, skipping cursor theme install"
            return 1
        fi
        log "Installing $THEME_CURSOR_NAME cursor theme"
        sudo tar -xf "$THEME_CURSOR_ASSET" -C /usr/share/icons \
            || { err "$THEME_CURSOR_NAME extraction failed"; return 1; }
    fi

    if command -v plasma-apply-cursortheme >/dev/null; then
        plasma-apply-cursortheme "$THEME_CURSOR_NAME"
    else
        kwriteconfig6 --file kcminputrc --group Mouse --key cursorTheme "$THEME_CURSOR_NAME"
    fi
    log "Set $THEME_CURSOR_NAME as the active Plasma cursor theme"

    _theme_set_sddm_key CursorTheme "$THEME_CURSOR_NAME"
}

# Uses Plasma's own scripting API (org.kde.PlasmaShell.evaluateScript) rather
# than hand-editing plasma-org.kde.plasma.desktop-appletsrc directly - that
# file is owned by a running plasmashell, so editing it live risks a write
# race; the scripting API is the same mechanism System Settings' own panel
# editor uses, applies instantly with no restart, and persists to that same
# config file on its own. Verified interactively: `panels()[0].location` and
# `.height` read back "top" and 23 immediately after, and a screenshot
# confirmed the panel actually moved (not just the property reporting
# changed).
_theme_configure_panel() {
    if ! command -v qdbus6 >/dev/null; then
        warn "qdbus6 not found, skipping panel layout change"
        return 1
    fi

    log "Moving the panel to the top, 23px tall"
    local result
    result="$(qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript '
        var p = panels()[0];
        if (p) {
            p.location = "top";
            p.height = 23;
        } else {
            print("no panel found");
        }
    ')"
    if [[ "$result" == *"no panel found"* ]]; then
        warn "No Plasma panel found to move"
        return 1
    fi
    return 0
}

# Uses KWin's own DBus interface (org.kde.KWin.VirtualDesktopManager) rather
# than hand-editing kwinrc's [Desktops] section directly, same reasoning as
# the panel: KWin owns that file live, and this is the same mechanism the
# Pager/virtual-desktop KCM uses. `count` is read-only (there's no "set
# desktop count" call) - the only way to add desktops is createDesktop at a
# position, one at a time, so this loops from the current count up to the
# target. Idempotent: if count is already >= target, it adds none. `rows` is
# a writable property; setting it is what turns "N desktops in a line" into
# an actual grid (confirmed interactively: creating 2 more on top of an
# existing 2-in-2-rows setup already yielded a 2x2 grid with no rows change
# needed, but setting it explicitly here makes the result correct
# regardless of whatever the starting rows value was).
_theme_configure_virtual_desktops() {
    local iface=org.kde.KWin.VirtualDesktopManager path=/VirtualDesktopManager
    local current
    current="$(qdbus6 org.kde.KWin "$path" org.freedesktop.DBus.Properties.Get "$iface" count 2>/dev/null)"
    if [[ -z "$current" ]]; then
        warn "Could not read KWin virtual desktop count, skipping"
        return 1
    fi

    if (( current >= THEME_DESKTOP_COUNT )); then
        warn "Already have $current virtual desktops (>= $THEME_DESKTOP_COUNT), not adding more"
    else
        log "Adding virtual desktops: $current -> $THEME_DESKTOP_COUNT"
        local i
        for (( i = current; i < THEME_DESKTOP_COUNT; i++ )); do
            qdbus6 org.kde.KWin "$path" org.kde.KWin.VirtualDesktopManager.createDesktop "$i" "Desktop $((i + 1))"
        done
    fi

    qdbus6 org.kde.KWin "$path" org.freedesktop.DBus.Properties.Set "$iface" rows "$THEME_DESKTOP_ROWS"
    log "Virtual desktops: $THEME_DESKTOP_COUNT arranged in $THEME_DESKTOP_ROWS rows"
}

# Three KWin window-management effects, not a Catppuccin thing - ported from
# the sibling mx-setup repo's modules/customizations.sh (same three Plugins
# keys, picked there in the same sitting as its other desktop tweaks):
#   wobblywindowsEnabled - windows wobble while being dragged/resized
#   magiclampEnabled     - Magic Lamp minimize animation
#   slidebackEnabled     - Slide Back: an obscured window slides back into
#                          view when the one covering it is moved away/closed
# Like the panel/virtual-desktop writes above, a bare kwriteconfig6 doesn't
# reach the running KWin - the reconfigure call below applies it live; a
# re-login also picks it up. Verified on this machine (2026-09): ran with a
# live plasmashell up, then read all three back with kreadconfig6 - each
# came back "true".
_theme_enable_kwin_effects() {
    log "Enabling KWin effects: Wobbly Windows, Magic Lamp, Slide Back"
    kwriteconfig6 --file kwinrc --group Plugins --key wobblywindowsEnabled true
    kwriteconfig6 --file kwinrc --group Plugins --key magiclampEnabled true
    kwriteconfig6 --file kwinrc --group Plugins --key slidebackEnabled true

    if command -v qdbus6 >/dev/null; then
        qdbus6 org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true
    else
        warn "qdbus6 not found - effects will take effect after next login"
    fi
}

# This is the exact toggle behind System Settings > Colors > "Accent color:"
# dropdown's "Accent color from wallpaper" option - found by extracting
# strings from the compiled KCM itself
# (/usr/lib/x86_64-linux-gnu/qt6/plugins/plasma/kcms/systemsettings/kcm_colors.so),
# since it isn't documented anywhere: the property is
# `accentColorFromWallpaper`, backed by kdeglobals [General]
# AccentColorFromWallpaper=true/false. It layers on top of whatever color
# scheme is active (CatppuccinMochaBlue here) - only the accent/Selection
# role switches source, the rest of the scheme's colors are untouched.
#
# plasmashell needs to reload to pick a fresh toggle up - confirmed by
# sampling the actual rendered pixel color of the panel's active-task
# highlight before and after a `plasmashell --replace` restart (before: a
# leftover Catppuccin Blue tone; after: a different, wallpaper-influenced
# one), not just by reading the config key back, since the resulting color
# itself is computed at runtime and never written back to kdeglobals as its
# own key. This module doesn't force that restart itself - same reasoning as
# not force-quitting a shell for modules/shell.sh - so it only takes full
# effect after the next logout/login, same as the SDDM changes above.
_theme_configure_accent_from_wallpaper() {
    log "Setting the system accent color to derive from the wallpaper"
    kwriteconfig6 --file kdeglobals --group General --key AccentColorFromWallpaper true
}
