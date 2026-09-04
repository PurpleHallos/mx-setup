#!/bin/bash
# Entry point for setting up this MX Linux install.
# Usage:
#   ./main.sh            run everything
#   ./main.sh debloat    run only the debloat module
#   ./main.sh thinkpad   run only the ThinkPad hardware setup (battery thresholds,
#                        fingerprint reader, natural touchpad scrolling)
#   ./main.sh apps       run only the application installs
#   ./main.sh devops     run only the devops tooling (Docker+Compose, Vagrant, Terraform)
#   ./main.sh fonts      run only the font install (Ubuntu UI font + JetBrainsMono Nerd Font mono)
#   ./main.sh fastfetch  run only the fastfetch theme install (Tsukiyomi Fetch)
#   ./main.sh shell      run only the bash alias setup
#   ./main.sh shortcuts  apply KDE keyboard shortcuts from stuff/shortcuts/
#   ./main.sh theme      install the Catppuccin Mocha theme (KDE, SDDM, icons)
#   ./main.sh app-themes install per-application Catppuccin themes (Zed)
#   ./main.sh grub       quiet the kernel boot log (loglevel=3 in GRUB_CMDLINE_LINUX_DEFAULT)
#
# Any target also accepts --dry-run (or DRYRUN=1) to print every mutating
# command without executing it. The debloat module additionally requires a
# Timeshift snapshot before it will touch anything; SKIP_SNAPSHOT=1 overrides.

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

# Accept --dry-run in any position, then drop it from the argument list.
args=()
for a in "$@"; do
    case "$a" in
        --dry-run|-n) DRYRUN=1 ;;
        *) args+=("$a") ;;
    esac
done
set -- "${args[@]+"${args[@]}"}"

source lib/common.sh
source modules/debloat.sh
source modules/thinkpad.sh
source modules/apps.sh
source modules/devops.sh
source modules/fonts.sh
source modules/fastfetch.sh
source modules/shell.sh
source modules/shortcuts.sh
source modules/theme.sh
source modules/app-themes.sh
source modules/grub.sh

if dry; then warn "DRY RUN - showing commands only, nothing will be changed"; fi

# Ask for the sudo password once, up front, and keep it warm for the rest of the
# run (no-op under a dry run). Everything below that touches the system then goes
# through without stopping to prompt half-way.
require_sudo

case "${1:-all}" in
    debloat)  run_debloat ;;
    thinkpad) run_thinkpad_setup ;;
    apps)     run_apps_setup ;;
    devops)   run_devops_setup ;;
    fonts)    run_fonts_setup ;;
    fastfetch) run_fastfetch_setup ;;
    shell)    run_shell_setup ;;
    shortcuts) run_shortcuts_setup ;;
    theme)    run_theme_setup ;;
    app-themes) run_app_themes_setup ;;
    grub)     run_grub_setup ;;
    all)
        run_debloat
        run_thinkpad_setup
        run_apps_setup
        run_devops_setup
        run_fonts_setup
        run_fastfetch_setup
        run_shell_setup
        run_shortcuts_setup
        run_theme_setup
        run_app_themes_setup
        run_grub_setup
        ;;
    *)
        err "Unknown target: $1 (expected: debloat | thinkpad | apps | devops | fonts | fastfetch | shell | shortcuts | theme | app-themes | grub | all)"
        exit 1
        ;;
esac

log "Done."
