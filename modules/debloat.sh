#!/bin/bash
# Programs to remove on this MX Linux (KDE Plasma 6) install.
# Add one purge_pkgs line per group, tested on this machine first. purge_pkgs
# (lib/common.sh) filters to what's actually installed, so globs that match
# nothing and re-runs after everything's gone are no-ops, not apt errors.

run_debloat() {
    log "=== Debloating: removing unwanted packages ==="

    # Nothing below is reversible with apt alone (purge drops config too), so
    # this is the one hard gate in the whole script: no restore point, no run.
    require_snapshot "before new-setup debloat" || return 1

    debloat_libreoffice
    debloat_games
    debloat_mx_bloatware
    debloat_digikam_skanpage
    debloat_help_info_centers
    debloat_misc_apps
    debloat_mc_conky
    debloat_redundant_mx_tools
    debloat_extra_mx_utilities
    debloat_qdiskinfo
    debloat_smb4k
    debloat_print_extras
    debloat_bash_config
    debloat_papirus_folder_colors
    debloat_ibus_kmenuedit
    debloat_duplicate_apps
    debloat_niche_apps
    debloat_yakuake
    debloat_mx_wallpapers
    debloat_legacy_themes
    debloat_default_desktop_icons

    log "Removing now-unused dependencies"
    run sudo apt-get autoremove -y

    # Bring what remains up to date once the bloat is gone. full-upgrade (not
    # upgrade) so packages that gained/dropped a dependency still move; noninter-
    # active + -y so a primed-sudo run stays unattended.
    log "Updating package lists and upgrading everything that remains"
    run sudo apt-get update
    run sudo DEBIAN_FRONTEND=noninteractive apt-get full-upgrade -y

    log "Clearing downloaded package cache"
    run sudo apt-get clean
}

# LibreOffice suite + the UNO runtime it depends on. The runtime (ure,
# libuno-*) isn't pulled in by autoremove because it's not marked
# auto-installed, so it's purged explicitly here too.
debloat_libreoffice() {
    log "Purging LibreOffice"
    purge_pkgs 'libreoffice*' lo-main-helper mythes-en-us \
        ure libuno-cppu3t64 libuno-cppuhelpergcc3-3t64 \
        libuno-purpenvhelpergcc3-3t64 libuno-sal3t64 \
        libuno-salhelpergcc3-3t64 uno-libs-private
}

# All KDE/games-section packages bundled with MX Linux's KDE install.
# libkdegames6-6, kdegames-mahjongg-data-kf6, libkdegames6-i18n and
# libkmahjongg6 are shared libs; the latter three are auto-installed and
# get swept up by autoremove, but libkdegames6-6 isn't, so it's explicit here.
debloat_games() {
    log "Purging games"
    purge_pkgs kmahjongg kmines ksudoku peg-e libkdegames6-6
}

# Extra apps bundled by the MX Linux ISO that aren't needed here.
debloat_mx_bloatware() {
    log "Purging bundled extras (Strawberry, GIMP, PDF Arranger, Foliate, FSearch, qimgv, mx-tour)"
    purge_pkgs strawberry gimp gimp-data 'gir1.2-gimp-3.0' \
        libgimp-3.0-0 pdfarranger foliate fsearch qimgv mx-tour

    log "Purging mx-docs / mx-faq (all languages)"
    purge_pkgs 'mx-docs*' 'mx-faq*'
}

debloat_digikam_skanpage() {
    log "Purging digiKam and Skanpage"
    purge_pkgs digikam digikam-data digikam-private-libs skanpage
}

# kate/plasma-desktop/kde-standard/krdc only *recommend* khelpcenter, and
# plasma-desktop only recommends kinfocenter, so purging these doesn't
# drag those packages down with it (verify with `apt-get purge -s` first
# if you add more to this group).
debloat_help_info_centers() {
    log "Purging KHelpCenter, KInfoCenter, and GNU info/texinfo"
    purge_pkgs khelpcenter khelpcenter-data kinfocenter info install-info
}

# mx-viewer (MX's lightweight browser), krdc (remote desktop client),
# alsa-utils (CLI alsamixer/amixer/aplay), k3b (disc burning), kamoso
# (webcam app), VLC, and pavucontrol (only plasma-pa is kept as the
# volume control, since the KDE one is enough).
# Purging VLC drops phonon4qt6-backend-vlc; apt swaps in
# phonon4qt6-backend-null automatically so Phonon still has a backend.
debloat_misc_apps() {
    log "Purging mx-viewer, krdc, alsa-utils, k3b, kamoso, VLC, pavucontrol"
    purge_pkgs mx-viewer krdc alsa-utils k3b k3b-data libk3b8t64 \
        kamoso vlc vlc-bin vlc-data vlc-l10n vlc-plugin-base vlc-plugin-qt \
        vlc-plugin-video-output pavucontrol

    remove_stale_alsamixer_menu_entry
}

# mx-system diverts /usr/share/applications/alsamixer.desktop and ships its
# own copy, separate from the alsa-utils package — so purging alsa-utils
# above removes the alsamixer binary but leaves this launcher behind,
# still showing "Alsamixer" under Multimedia in the app menu.
remove_stale_alsamixer_menu_entry() {
    if [[ -f /usr/share/applications/alsamixer.desktop ]]; then
        log "Removing stale Alsamixer menu entry (owned by mx-system diversion)"
        run sudo rm -f /usr/share/applications/alsamixer.desktop
        kbuildsycoca6 --noincremental &>/dev/null || true
    fi
}

# mx-apps-kde is just an empty meta-package listing MX's bundled app set
# (hard-depends on mc), and conky-all is only depended on by mx-conky, so
# both are safe to drop alongside mc/conky themselves.
debloat_mc_conky() {
    log "Purging Midnight Commander and Conky"
    purge_pkgs mc mx-conky mx-conky-data mx-conky-data-bin \
        mx-conky-data-themes conky-toggle-mx conky-all mx-apps-kde

    # mx-system diverts /usr/share/applications/conky.desktop and ships its
    # own copy, so purging conky-all leaves this launcher behind - now broken
    # (points at a conky binary that's gone) and showing in the app menu.
    if [[ -f /usr/share/applications/conky.desktop ]]; then
        log "Removing stale Conky menu entry (owned by mx-system diversion)"
        run sudo rm -f /usr/share/applications/conky.desktop
        kbuildsycoca6 --noincremental &>/dev/null || true
    fi
}

# MX Tools that KDE Plasma's System Settings already covers natively, so
# they're redundant on KDE (MX Tools targets Xfce, which lacks these GUIs):
#   mx-datetime      -> kcm_clock (Date & Time)
#   mx-locale        -> kcm_regionandlang (Region & Language)
#   mx-user          -> kcm_users (Users)
#   mx-select-sound  -> kcm_pulseaudio / plasma-pa (Audio)
#   mx-tweak         -> built for Xfce; Plasma uses System Settings + panel edit
#   mx-welcome       -> first-boot welcome screen (onboarding only)
# The mx-tools hub only *recommends* mx-user/mx-select-sound, so it and the
# other MX tools (snapshot, packageinstaller, repo-manager, cleanup,
# bootrepair, and the kept partials) stay installed.
debloat_redundant_mx_tools() {
    log "Purging MX tools redundant on KDE (datetime, locale, user, select-sound, tweak, welcome)"
    purge_pkgs mx-datetime mx-locale mx-user mx-select-sound \
        mx-tweak mx-tweak-data mx-welcome mx-welcome-data
}

# More MX Tools entries not needed here:
#   user-installed-packages  - lists manually-installed packages
#   system-keyboard-qt       - console keyboard layout tool
#   quick-system-info-gui    - inxi wrapper (Quick System Info)
#   formatusb                - USB formatter
# system-keyboard-qt is a dependency of mx-installer (the live-media OS
# installer, dead weight on an installed system), so mx-installer and its
# gazelle-installer-data-mx get purged alongside it here on purpose.
debloat_extra_mx_utilities() {
    log "Purging user-installed-packages, system-keyboard-qt, quick-system-info-gui, formatusb (+ mx-installer)"
    purge_pkgs user-installed-packages system-keyboard-qt \
        quick-system-info-gui formatusb mx-installer gazelle-installer-data-mx
}

# qdiskinfo: CrystalDiskInfo-style SMART disk health viewer. No dependents.
# NOTE: yad is deliberately NOT removed - it's a hard dependency of
# orca-sops and is called at runtime by kept tools (live-usb-maker /
# dd-live-usb behind mx-live-usb-maker, papirus-folder-colors, isomount).
debloat_qdiskinfo() {
    log "Purging QDiskInfo"
    purge_pkgs qdiskinfo
}

# smb4k: standalone advanced Samba browser. Redundant on KDE - Dolphin
# browses shares natively via smb:// (kio-extras) and kdenetwork-filesharing
# handles sharing your own folders. No dependents.
debloat_smb4k() {
    log "Purging smb4k"
    purge_pkgs smb4k
}

# system-config-printer is the GTK printer GUI, redundant with KDE's
# print-manager (System Settings > Printers). hplip (HP drivers/scanner)
# and printer-driver-cups-pdf (print-to-PDF) depend on it, so they go too.
# Only do this with NO HP printer and no need for the print-to-PDF printer.
# CUPS + print-manager stay, so generic/network printers still work.
debloat_print_extras() {
    log "Purging system-config-printer, HP driver stack, and cups-pdf"
    purge_pkgs system-config-printer system-config-printer-common \
        hplip hplip-data printer-driver-cups-pdf printer-driver-hpcups \
        printer-driver-postscript-hp libsane-hpaio libhpmud0
}

# bash-config: MX GUI for editing bash aliases / prompt themes. No dependents.
debloat_bash_config() {
    log "Purging bash-config (MX bash alias/prompt GUI)"
    purge_pkgs bash-config
}

# papirus-folder-colors: MX applet for recoloring Papirus folder icons.
# Leaves the actual icon themes (papirus-icon-theme, papirus-mxblue) intact.
debloat_papirus_folder_colors() {
    log "Purging papirus-folder-colors app"
    purge_pkgs papirus-folder-colors
}

# ibus: input-method framework only needed for CJK / table-based input and
# the IME emoji picker - only purge this if that's not wired into your system
# (GTK/QT_IM_MODULE empty, plain XKB layouts in use). kmenuedit: KDE menu
# editor, only recommended by plasma-desktop so it removes cleanly.
debloat_ibus_kmenuedit() {
    log "Purging ibus stack and kmenuedit"
    purge_pkgs ibus ibus-data ibus-table ibus-table-emoticon kmenuedit
}

# Duplicate apps - KDE already provides an equivalent:
#   disk-manager (MX)  -> KDE Partition Manager (partitionmanager, kept)
#   plasma-discover    -> mx-packageinstaller + apt; only worth removing if
#                         Discover has no backend installed (non-functional).
# plasma-desktop only *recommends* plasma-discover, so it isn't dragged out.
debloat_duplicate_apps() {
    log "Purging duplicate apps (disk-manager, plasma-discover)"
    purge_pkgs disk-manager plasma-discover plasma-discover-common
}

# Niche / no-use-here apps:
#   orca + orca-sops        - screen reader (accessibility - skip this group
#                             if you or anyone using this machine needs it)
#   kmag                    - screen magnifier (accessibility, same caveat)
#   live-kernel-updater     - live-USB kernel updater, useless on an install
#   ktelnetservice5/6       - telnet:// URL handlers (archaic); owned by the
#                             core kio6 package so the launchers are just
#                             deleted rather than purging the package.
debloat_niche_apps() {
    log "Purging orca, kmag, live-kernel-updater"
    purge_pkgs orca orca-sops kmag live-kernel-updater

    log "Removing ktelnet service menu entries (kio6 is core, keep the package)"
    run sudo rm -f /usr/share/applications/ktelnetservice5.desktop \
               /usr/share/applications/ktelnetservice6.desktop
    kbuildsycoca6 --noincremental &>/dev/null || true
}

# yakuake: KDE drop-down terminal, standalone with no dependents. Not used
# here (Konsole is kept as the regular terminal).
debloat_yakuake() {
    log "Purging Yakuake"
    purge_pkgs yakuake
}

# All MX Linux wallpapers: the mx25-artwork package ships ~40 of them (it's
# wallpapers-only, no login/boot artwork), and the installer also drops an
# unowned default25.png. The lock screen references default25.png, so repoint
# it to the KDE Breeze "Next" wallpaper first to avoid a blank lock screen.
debloat_mx_wallpapers() {
    log "Purging MX wallpapers (mx25-artwork)"
    purge_pkgs mx25-artwork

    if grep -q 'default25' ~/.config/kscreenlockerrc 2>/dev/null; then
        log "Repointing lock screen off the MX default wallpaper"
        kwriteconfig6 --file kscreenlockerrc \
            --group Greeter --group Wallpaper --group org.kde.image --group General \
            --key Image "file:///usr/share/wallpapers/Next/"
    fi

    log "Removing leftover MX default wallpaper file"
    run sudo rm -f /usr/share/backgrounds/default25.png /usr/share/wallpapers/default25.png
}

# Legacy KDE4/Oxygen + DMZ themes, unused on Plasma 6. Only these three have
# no reverse deps. NOTE: adwaita-icon-theme and gnome-icon-theme are NOT
# touched - GTK 2/3 hard-depend on them, so removing them would drag out the
# GTK libraries and break every GTK app (Firefox, Thunderbird, ...).
debloat_legacy_themes() {
    log "Purging legacy Oxygen/DMZ themes"
    purge_pkgs oxygen-icon-theme kde-style-oxygen-qt6 dmz-cursor-theme
}

# Three .desktop launchers (FAQ, the MX user manual, a system-info shortcut)
# MX drops onto every new user's Desktop at first login - not owned by any
# package (dpkg -S finds nothing for them; their source .desktop files under
# /usr/share/applications are gone from this install already, likely via
# debloat_help_info_centers/debloat_misc_apps above, but the per-user copies
# on the Desktop were never cleaned up by that), so there's nothing for
# purge_pkgs to grab - just plain files to delete.
debloat_default_desktop_icons() {
    log "Removing default MX desktop icons (FAQ, Help, Quick System Info)"
    run rm -f ~/Desktop/FAQ.desktop ~/Desktop/Help.desktop ~/Desktop/Quick_System_Info.desktop
}
