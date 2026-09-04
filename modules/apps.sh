#!/bin/bash
# Applications that aren't part of the desktop look-and-feel: an image viewer,
# a video player, a system-info fetcher, the GitHub CLI, Spotify (+
# spicetify), Telegram Desktop, Zed, Obsidian, Brave, the Wrangler CLI, and
# Oracle VirtualBox.
# Ported from the sibling mx-setup repo's modules/apps.sh and re-verified
# against this machine, not copied wholesale.
#
# Verified on this machine (2026-08, trixie):
#  * gwenview/mpv/fastfetch: plain Debian packages, install_if_missing covers
#    them (fastfetch was already installed here, from MX's own repo).
#  * gh, telegram-desktop, spotify-client, zed: none are in Debian's configured
#    repos here (apt-cache policy/show all come back empty or, for gh, at the
#    stale 2.46.0-3 Debian ships) - same gap mx-setup found, so the same
#    vendor-repo/tarball routes apply.
#  * flatpak IS installed here (unlike mx-setup's box, where it's absent
#    entirely) but had zero remotes configured when this was first ported -
#    not a usable install source for any of gh/spotify/telegram/zed at
#    that point (same practical outcome as mx-setup's missing-flatpak box,
#    different reason). Obsidian's install below now adds the Flathub remote
#    (`flathub`, https://flathub.org/repo/flathub.flatpakrepo) since Flathub
#    is the only source it uses - telegram-desktop is on Flathub too and
#    would be worth reconsidering over its tarball now that the remote
#    exists, but that switch hasn't been made (untouched, still tarball-based
#    below).
#  * Node.js/Claude Code are deliberately NOT ported: this machine already
#    manages both through nvm (`node -v` -> v24, `claude` already installed at
#    ~/.nvm/versions/node/*/bin/claude). mx-setup's NodeSource-repo + user-owned
#    npm-prefix dance exists to work around a root-owned system Node - nvm
#    already gives a fully user-owned tree, so that whole mechanism doesn't
#    apply and adding NodeSource on top would just create a second, conflicting
#    Node install. If nvm's Node ever falls behind, `nvm install <major>` is
#    the fix, not this module.
#  * Wrangler, NEW versus mx-setup (no precedent there to port): installed as
#    a plain `npm install -g wrangler` against that same nvm-managed npm
#    (`npm config get prefix` -> ~/.nvm/versions/node/v24.20.0, user-owned,
#    same reasoning as Claude Code above) - no sudo, no separate repo/binary.
#  * Spotify's signing key rotates and expires (see mx-setup's history on
#    this) - the key ID pinned below was valid there as of 2026-02, expiring
#    2027-02-14, so it's still good today, but treat it as a live fact, not a
#    constant: if the repo add fails apt's signature check, fetch
#    dists/stable/Release.gpg from repository.spotify.com and read the actual
#    signing key id with `gpg --verify` before assuming this ID is still right.
#  * VirtualBox + Secure Boot, machine-specific and NEW versus mx-setup: this
#    ThinkPad has Secure Boot enabled (mokutil --sb-state) and is real
#    hardware (systemd-detect-virt: none), unlike mx-setup's machine which is
#    itself a throwaway VirtualBox guest and never actually boots a nested
#    guest either way. This machine's existing out-of-tree Wi-Fi drivers load
#    fine under Secure Boot because they go through DKMS against an already-
#    enrolled "DKMS module signing key" MOK (see new-setup/CLAUDE.md). Oracle's
#    virtualbox-7.2 package builds its kernel modules via /sbin/vboxconfig,
#    NOT through that DKMS path, so there is no guarantee those modules are
#    signed with a trusted key - the kernel may refuse to load vboxdrv here.
#    The install below still runs (matching mx-setup's shape) but only warns,
#    never aborts, if vboxdrv doesn't show up in lsmod afterward; if that
#    happens, check `dmesg` for a lockdown/signature-rejection message before
#    assuming it's just a build failure - the fix is enrolling a MOK for the
#    vbox modules or rebuilding them through DKMS, not scripted here since a
#    bad MOK/signing change is exactly the kind of thing new-setup's CLAUDE.md
#    says to keep hands off.
#  * spicetify's prefs detection needs a real Spotify prefs file, not the empty
#    placeholder mx-setup used to touch - that only worked there because
#    mx-setup's machine had already run Spotify by hand first. Here,
#    _apps_generate_spotify_prefs launches Spotify headlessly and closes it
#    once the file appears, so the whole module stays hands-off.
#  * Everything else below (spicetify's backup/Marketplace mechanics,
#    Telegram's tarball shape, Zed's official installer, the repo-add helper -
#    now `add_apt_repo` in lib/common.sh, shared with devops.sh) is carried
#    over unchanged from mx-setup - see its modules/apps.sh git history for
#    the original hard-won detail if something here needs revisiting.
#  * Obsidian, NEW versus mx-setup (no precedent there to port): not in
#    Debian's repos, so it installs from Flathub (`md.obsidian.Obsidian`),
#    adding the `flathub` remote first since none was configured (see the
#    flatpak note above). System-wide install/remote (`sudo flatpak`, no
#    `--user`), matching every other app module here being machine-wide
#    rather than per-user.
#  * Docker/Compose, Vagrant and Terraform live in their own `devops.sh`
#    module, not here - see that file.

run_apps_setup() {
    log "=== Installing applications ==="

    install_if_missing gwenview
    install_if_missing mpv
    install_if_missing fastfetch

    if dry; then
        log "[dry] would add the GitHub CLI, Spotify and Oracle VirtualBox apt repos,"
        log "[dry] install gh, the Spotify client and virtualbox-7.2 (building its kernel modules),"
        log "[dry] install spicetify + Marketplace and patch Spotify, with an apt"
        log "[dry] hook to re-apply it after every Spotify upgrade,"
        log "[dry] add $USER to vboxusers, install Telegram Desktop to /opt/telegram,"
        log "[dry] and install the Zed editor to ~/.local/zed.app"
        log "[dry] add the Flathub remote and install Obsidian from it"
        log "[dry] install Brave via its official install script"
        log "[dry] npm install -g wrangler (against the nvm-managed npm)"
        return 0
    fi

    # Each app is independent - one failing (we're under set -e) must not abort
    # the rest, or a single bad app silently skips everything after it in this
    # list, which is exactly what happened before this was added.
    _apps_install_gh          || warn "gh install failed, continuing"
    _apps_install_wrangler    || warn "wrangler install failed, continuing"
    _apps_install_spotify     || warn "Spotify install failed, continuing"
    _apps_install_spicetify   || warn "spicetify install failed, continuing"
    _apps_install_telegram    || warn "Telegram Desktop install failed, continuing"
    _apps_install_zed         || warn "Zed install failed, continuing"
    _apps_install_obsidian    || warn "Obsidian install failed, continuing"
    _apps_install_brave       || warn "Brave install failed, continuing"
    _apps_install_virtualbox  || warn "VirtualBox install failed, continuing"

    log "Applications installed."
}

_apps_install_gh() {
    if command -v gh >/dev/null; then
        warn "gh already installed ($(gh --version 2>/dev/null | head -1)), skipping"
        return 0
    fi
    log "Adding the GitHub CLI repo (Debian's gh is years behind)"
    add_apt_repo "github-cli" \
        "https://cli.github.com/packages/githubcli-archive-keyring.gpg" \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/github-cli.gpg] https://cli.github.com/packages stable main"
    log "Installing gh"
    sudo apt-get install -y gh
}

# ---------------------------------------------------------------------------
# Cloudflare's Wrangler CLI, via the nvm-managed npm (see the header note on
# why this machine's Node is user-owned already and needs no sudo here).
# ---------------------------------------------------------------------------
_apps_install_wrangler() {
    if command -v wrangler >/dev/null; then
        warn "wrangler already installed ($(wrangler --version 2>/dev/null | head -1)), skipping"
        return 0
    fi
    log "Installing wrangler"
    npm install -g wrangler
}

# ---------------------------------------------------------------------------
# Spotify desktop client, from Spotify's vendor apt repo (see the header note
# on why the key ID here needs re-checking rather than trusting it forever).
# ---------------------------------------------------------------------------
_apps_install_spotify() {
    if command -v spotify >/dev/null; then
        warn "Spotify already installed ($(dpkg-query -W -f='${Version}' spotify-client 2>/dev/null)), skipping"
        return 0
    fi
    log "Adding the Spotify repo (no Spotify client in Debian, no usable flatpak remote here)"
    add_apt_repo "spotify" \
        "https://download.spotify.com/debian/pubkey_5384CE82BA52C83A.gpg" \
        "deb [arch=amd64 signed-by=/etc/apt/keyrings/spotify.gpg] https://repository.spotify.com stable non-free"
    log "Installing the Spotify client"
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y spotify-client
}

# ---------------------------------------------------------------------------
# spicetify + Marketplace, and the apt hook that re-applies the patch after a
# Spotify upgrade. Mechanics carried over unchanged from mx-setup: the initial
# `backup apply` only works from a vanilla tree (xpui.spa present); an
# already-patched tree aborts with a version mismatch, so that step is guarded
# on xpui.spa, while Marketplace's own installer runs plain `apply` (safe over
# either state) and so always runs.
# ---------------------------------------------------------------------------
# spicetify/Marketplace both need Spotify's real prefs file to locate its
# install; an empty placeholder isn't enough (Spotify only writes it, with
# real content, on first run). Launches Spotify headlessly, waits for it to
# appear, then closes it - no window ever needs to stay open.
_apps_generate_spotify_prefs() {
    local prefs="$HOME/.config/spotify/prefs"

    if [[ -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" ]]; then
        warn "No display available to launch Spotify - open it manually once,"
        warn "then re-run this module so its prefs file can be generated."
        return 1
    fi

    log "Launching Spotify once to generate its prefs file"
    mkdir -p "$HOME/.config/spotify"
    nohup spotify --uri=spotify: >/dev/null 2>&1 &
    disown

    local i
    for ((i = 0; i < 30; i++)); do
        [[ -s "$prefs" ]] && break
        sleep 1
    done

    pkill -TERM -f '/usr/share/spotify/spotify' 2>/dev/null || true
    for ((i = 0; i < 10; i++)); do
        pgrep -f '/usr/share/spotify/spotify' >/dev/null || break
        sleep 1
    done
    pkill -KILL -f '/usr/share/spotify/spotify' 2>/dev/null || true

    if [[ -s "$prefs" ]]; then
        log "Spotify prefs file generated"
    else
        warn "Spotify prefs file still missing after waiting - spicetify may fail to detect it"
    fi
}

_apps_install_spicetify() {
    local spice="$HOME/.spicetify/spicetify"
    local apps=/usr/share/spotify/Apps

    if [[ ! -d /usr/share/spotify ]]; then
        warn "Spotify not installed - skipping spicetify (nothing to patch)"
        return 0
    fi

    if [[ -x "$spice" ]]; then
        warn "spicetify already installed ($("$spice" --version 2>/dev/null)), skipping CLI"
    else
        log "Installing spicetify (official installer -> ~/.spicetify)"
        if ! curl -fsSL https://raw.githubusercontent.com/spicetify/cli/main/install.sh | sh; then
            err "spicetify install failed"
            return 1
        fi
    fi
    export PATH="$HOME/.spicetify:$PATH"

    # /usr/share/spotify is root-owned and read-only - spicetify needs to write it.
    sudo chmod a+wr /usr/share/spotify
    sudo chmod a+wr -R /usr/share/spotify/Apps

    if [[ ! -s "$HOME/.config/spotify/prefs" ]]; then
        _apps_generate_spotify_prefs
    fi

    if [[ -e "$apps/xpui.spa" ]]; then
        log "Applying spicetify to Spotify"
        spicetify backup apply || err "spicetify backup apply failed"
    else
        warn "Spotify already patched (xpui.spa absent) - skipping initial apply"
    fi

    if [[ -d "$HOME/.config/spicetify/CustomApps/marketplace" ]]; then
        warn "spicetify Marketplace already installed, skipping"
    else
        log "Installing spicetify Marketplace"
        curl -fsSL https://raw.githubusercontent.com/spicetify/marketplace/main/resources/install.sh | sh \
            || warn "Marketplace install returned non-zero (continuing)"
    fi

    _apps_install_spicetify_reapply_hook

    log "spicetify ready. Restart Spotify to see it/Marketplace; open a new shell"
    log "for the 'spicetify' command on PATH (~/.spicetify was added to .bashrc)."
}

# Deploy the reapply-after-update script and its apt Post-Invoke hook. A
# Spotify upgrade restores the package-owned vanilla xpui.spa and resets the
# dir perms, silently dropping the patch - "xpui.spa present" is the vanilla
# signal this hook (and the guard above) both key off of.
_apps_install_spicetify_reapply_hook() {
    local script=/usr/local/bin/spicetify-reapply
    local hook=/etc/apt/apt.conf.d/99-spicetify-reapply
    local tmp
    tmp="$(mktemp)"

    cat > "$tmp" <<'SCRIPT'
#!/bin/sh
# Re-apply spicetify after the Spotify package is (re)installed or upgraded.
# Installed by new-setup (modules/apps.sh); runs as root from an APT
# Post-Invoke hook after every apt transaction, so it must stay cheap.
set -eu
SPOTIFY_DIR=/usr/share/spotify
XPUI_SPA="$SPOTIFY_DIR/Apps/xpui.spa"
SPICE_USER=@SPICE_USER@
SPICE_BIN=@SPICE_BIN@

[ -e "$XPUI_SPA" ] || exit 0
[ -x "$SPICE_BIN" ] || exit 0
id "$SPICE_USER" >/dev/null 2>&1 || exit 0

chmod a+wr "$SPOTIFY_DIR" 2>/dev/null || true
chmod a+wr -R "$SPOTIFY_DIR/Apps" 2>/dev/null || true

HOME_DIR="$(getent passwd "$SPICE_USER" | cut -d: -f6)"
echo "spicetify-reapply: Spotify changed, re-applying as $SPICE_USER"
runuser -u "$SPICE_USER" -- env HOME="$HOME_DIR" "$SPICE_BIN" backup apply >/dev/null 2>&1 \
    || echo "spicetify-reapply: 'backup apply' failed for $SPICE_USER - re-run it by hand" >&2
SCRIPT

    sed -i "s|@SPICE_USER@|$USER|; s|@SPICE_BIN@|$HOME/.spicetify/spicetify|" "$tmp"
    sudo install -Dm755 "$tmp" "$script"
    rm -f "$tmp"

    # Fail open (|| true) so a spicetify hiccup can never wedge apt itself.
    printf '%s\n' \
        '// Re-apply spicetify after Spotify is upgraded (installed by new-setup).' \
        'DPkg::Post-Invoke { "if [ -x /usr/local/bin/spicetify-reapply ]; then /usr/local/bin/spicetify-reapply || true; fi"; };' \
        | sudo tee "$hook" >/dev/null

    log "spicetify reapply hook installed ($script + apt Post-Invoke)"
}

# telegram.org/dl/desktop/linux 302-redirects to the versioned tarball; the
# resolved URL is the only place the latest version appears.
_apps_telegram_latest_url() {
    local url
    url="$(curl -fsSI -m 30 'https://telegram.org/dl/desktop/linux' \
           | sed -n 's/\r$//; s/^[Ll]ocation: //p' | tail -1)"
    echo "${url:-https://telegram.org/dl/desktop/linux}"
}

_apps_telegram_version() {
    echo "$1" | sed -n 's/.*tsetup\.\([0-9.]*\)\.tar\.xz/\1/p'
}

# ---------------------------------------------------------------------------
# Telegram Desktop, from the official tarball - not in Debian's repos here,
# and flatpak has no remote configured (see header note). /opt/telegram is
# user-owned so the bundled Updater can self-update in place.
# ---------------------------------------------------------------------------
_apps_install_telegram() {
    local url ver tmp
    url="$(_apps_telegram_latest_url)"
    ver="$(_apps_telegram_version "$url")"
    ver="${ver:-unknown}"

    if [[ "$(cat /opt/telegram/.new-setup-version 2>/dev/null)" == "$ver" && "$ver" != "unknown" ]]; then
        warn "Telegram Desktop $ver already installed, skipping"
        return 0
    fi

    log "Installing Telegram Desktop $ver to /opt/telegram"
    tmp="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap "rm -rf '$tmp'" RETURN

    if ! curl -fL --progress-bar -m 600 "$url" -o "$tmp/telegram.tar.xz"; then
        err "Telegram Desktop download failed"
        return 1
    fi
    tar -C "$tmp" -xJf "$tmp/telegram.tar.xz"
    if [[ ! -x "$tmp/Telegram/Telegram" ]]; then
        err "Telegram tarball did not contain the expected Telegram/ dir"
        return 1
    fi

    sudo rm -rf /opt/telegram
    sudo mv "$tmp/Telegram" /opt/telegram
    sudo chown -R "$USER:$USER" /opt/telegram
    sudo ln -sf /opt/telegram/Telegram /usr/local/bin/telegram

    sudo tee /usr/share/applications/telegram.desktop >/dev/null <<'EOF'
[Desktop Entry]
Type=Application
Name=Telegram Desktop
GenericName=Telegram
Comment=Official Telegram Desktop messenger
Exec=/opt/telegram/Telegram -- %u
Icon=telegram
Terminal=false
StartupWMClass=TelegramDesktop
Categories=Network;InstantMessaging;Chat;
MimeType=x-scheme-handler/tg;
Keywords=telegram;chat;messenger;
EOF
    sudo update-desktop-database /usr/share/applications 2>/dev/null || true
    echo "$ver" > /opt/telegram/.new-setup-version
    log "Telegram Desktop $ver installed"
}

# ---------------------------------------------------------------------------
# Zed editor, from the official installer. No sudo - everything lands under
# ~/.local, including the .desktop entry, which the installer rewrites with
# absolute Exec/Icon paths itself.
# ---------------------------------------------------------------------------
_apps_install_zed() {
    if [[ -x "$HOME/.local/bin/zed" ]]; then
        warn "Zed already installed ($("$HOME/.local/bin/zed" --version 2>/dev/null | head -1)), skipping"
        return 0
    fi

    log "Installing the Zed editor (~400MB download)"
    if ! curl -fsSL -m 60 https://zed.dev/install.sh | sh; then
        err "Zed install failed"
        return 1
    fi

    update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
    log "Zed installed ($("$HOME/.local/bin/zed" --version 2>/dev/null | head -1))"
}

# ---------------------------------------------------------------------------
# Obsidian, from Flathub. System-wide remote + install (no `--user`) so it
# matches every other app module here.
# ---------------------------------------------------------------------------
APPS_OBSIDIAN_FLATPAK_ID="md.obsidian.Obsidian"

_apps_ensure_flathub() {
    if flatpak remote-list | grep -q '^flathub'; then
        warn "flathub remote already configured, skipping"
        return 0
    fi
    log "Adding the Flathub remote"
    sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
}

_apps_install_obsidian() {
    install_if_missing flatpak
    _apps_ensure_flathub || return 1

    if flatpak list --app --columns=application | grep -qx "$APPS_OBSIDIAN_FLATPAK_ID"; then
        warn "Obsidian already installed via flatpak, skipping"
        return 0
    fi

    log "Installing Obsidian from Flathub"
    sudo flatpak install -y --noninteractive flathub "$APPS_OBSIDIAN_FLATPAK_ID"
}

# ---------------------------------------------------------------------------
# Brave browser, from the official install script (adds Brave's own apt repo
# and signing key, then installs brave-browser via apt itself - nothing to
# duplicate here with add_apt_repo).
# ---------------------------------------------------------------------------
_apps_install_brave() {
    if command -v brave-browser >/dev/null; then
        warn "Brave already installed ($(brave-browser --version 2>/dev/null)), skipping"
        return 0
    fi

    log "Installing Brave (official install script)"
    if ! curl -fsS https://dl.brave.com/install.sh | sh; then
        err "Brave install failed"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Oracle VirtualBox. Headers first: vboxconfig compiles against the running
# kernel and fails outright without them. See the header note on why this
# machine's Secure Boot + vboxconfig combination is untested and only warns
# rather than aborts if the modules don't end up loaded.
# ---------------------------------------------------------------------------
_apps_install_virtualbox() {
    if command -v VBoxManage >/dev/null; then
        warn "VirtualBox already installed ($(VBoxManage --version 2>/dev/null)), skipping"
    else
        install_if_missing dkms
        install_if_missing "linux-headers-$(uname -r)"

        log "Adding the Oracle VirtualBox repo"
        add_apt_repo "virtualbox" \
            "https://www.virtualbox.org/download/oracle_vbox_2016.asc" \
            "deb [arch=amd64 signed-by=/etc/apt/keyrings/virtualbox.gpg] https://download.virtualbox.org/virtualbox/debian trixie contrib"

        log "Installing VirtualBox 7.2 (builds kernel modules, takes a minute)"
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y virtualbox-7.2

        sudo /sbin/vboxconfig >/dev/null 2>&1 || true

        if lsmod | grep -q '^vboxdrv'; then
            log "VirtualBox kernel modules loaded"
        else
            warn "vboxdrv did not load - with Secure Boot enabled here, check 'dmesg' for a"
            warn "signature-rejection/lockdown message before assuming it's a build failure"
            warn "(see the Secure Boot note at the top of this file); also try 'sudo /sbin/vboxconfig'"
        fi
    fi

    # Runs even when VirtualBox was already installed - see the header note
    # on ensure_user_in_group in lib/common.sh for why.
    ensure_user_in_group vboxusers
}
