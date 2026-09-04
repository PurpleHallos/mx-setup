#!/bin/bash
# Per-application Catppuccin themes, as opposed to modules/theme.sh's
# desktop-wide (KDE global theme/SDDM/icons) Catppuccin setup. Currently
# just Zed's editor theme; more apps' themes may get added here later
# following the same shape (one _app_themes_install_<app> function per app,
# called from run_app_themes_setup).

# catppuccin/zed publishes one release JSON per accent, each bundling all
# four Catppuccin flavours (Latte/Frappe/Macchiato/Mocha) as named Zed
# themes inside a single file - not one file per flavour. Pinned release,
# not "latest" - same reasoning as the JetBrainsMono pin in modules/fonts.sh.
APP_THEMES_ZED_RELEASE_URL="https://github.com/catppuccin/zed/releases/download/v0.2.25/catppuccin-blue.json"
APP_THEMES_ZED_DIR="$HOME/.config/zed"
# Exact "name" fields from inside that JSON's "themes" array (verified by
# downloading it and inspecting the JSON directly, not guessed) - "blue" to
# match the accent already chosen for the rest of the desktop
# (modules/theme.sh's THEME_CATPPUCCIN_ACCENT).
APP_THEMES_ZED_DARK_THEME="Catppuccin Mocha (blue)"
APP_THEMES_ZED_LIGHT_THEME="Catppuccin Latte (blue)"

run_app_themes_setup() {
    log "=== Setting up per-application Catppuccin themes ==="

    if dry; then
        log "[dry] would install the Catppuccin Zed theme (blue accent) and set it active"
        return 0
    fi

    _app_themes_install_zed

    log "App themes done. Zed needs a restart to fully pick up the new theme."
}

# Zed's own docs describe installing the BASE Catppuccin extension through
# Zed's in-app extension manager (command palette > "zed: extensions") and
# only the per-accent JSON through a themes/ file - there's no documented
# CLI/headless path for the extension-manager step, and it isn't needed
# anyway: dropping the accent JSON straight into ~/.config/zed/themes/ and
# pointing settings.json at its theme name by hand (see
# _app_themes_set_zed_theme) works without installing anything through the
# extension manager at all.
_app_themes_install_zed() {
    if [[ ! -d "$APP_THEMES_ZED_DIR" ]]; then
        warn "$APP_THEMES_ZED_DIR not found - is Zed installed? (modules/apps.sh) Skipping."
        return 1
    fi

    log "Installing the Catppuccin Zed theme"
    mkdir -p "$APP_THEMES_ZED_DIR/themes"
    curl -fsSL -m 60 --retry 2 -o "$APP_THEMES_ZED_DIR/themes/catppuccin-blue.json" "$APP_THEMES_ZED_RELEASE_URL" \
        || { err "Catppuccin Zed theme download failed"; return 1; }

    _app_themes_set_zed_theme
}

# settings.json is JSONC (comments + a trailing comma after "dark", both
# confirmed present in Zed's own default file) - the same situation
# modules/fastfetch.sh's config.jsonc is in, same fix: a targeted text
# substitution of just the "theme" block, not a full JSON parse/rewrite that
# would silently drop the comments. Handles a re-run (the block already
# there, from a previous run of this or from picking a theme by hand in Zed)
# by replacing it in place; a "theme" key missing entirely (a stripped-down
# settings.json, since Zed's own default one always has it) falls back to
# inserting right after the file's opening brace.
_app_themes_set_zed_theme() {
    local settings="$APP_THEMES_ZED_DIR/settings.json"
    [[ -f "$settings" ]] || { warn "$settings not found, skipping theme activation"; return 1; }

    python3 - "$settings" "$APP_THEMES_ZED_DARK_THEME" "$APP_THEMES_ZED_LIGHT_THEME" <<'PYEOF'
import re
import sys

path, dark, light = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path, "r", encoding="utf-8") as fh:
    text = fh.read()

block = (
    '"theme": {\n'
    '    "mode": "dark",\n'
    f'    "light": "{light}",\n'
    f'    "dark": "{dark}",\n'
    '  }'
)

pattern = re.compile(r'"theme"\s*:\s*\{[^{}]*\}', re.DOTALL)
if pattern.search(text):
    text = pattern.sub(block, text, count=1)
else:
    text = re.sub(r'\{', '{\n  ' + block + ',', text, count=1)

with open(path, "w", encoding="utf-8") as fh:
    fh.write(text)
PYEOF

    log "Set Zed's theme to $APP_THEMES_ZED_DARK_THEME"
}
