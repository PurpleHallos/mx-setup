#!/bin/bash
# Bash aliases/settings, ported from the sibling mx-setup repo's
# modules/shell.sh, which itself ported them from Erik Dubois' ArcoLinux
# .bashrc (arcolinux-root/etc/skel/.bashrc-latest, 206 aliases). See that
# file's own header for the full ArcoLinux->Debian rationale (apt/dpkg
# rewrites, dropped ArcoLinux-only tooling, snapper->Timeshift, etc.) - it
# isn't repeated here. Changes made specifically for the move to new-setup:
#
#   * mx-setup's 'mx'/'mxdry'/'nmx' aliases (hardcoded to ~/mx-setup) became
#     'nws'/'nwsdry'/'nnws', pointed at THIS repo's actual on-disk path -
#     computed once via BASH_SOURCE (same trick modules/fastfetch.sh already
#     uses for its logo asset) and baked into the generated alias file at
#     write time via @NEW_SETUP_DIR@, not hardcoded to a guessed clone path.
#   * mx-setup's update/upd/upall/upcheck aliases pointed at mx-update
#     (modules/update.sh, deployed to /usr/local/bin) - that module hasn't
#     been ported to new-setup yet, so those now just run plain apt. Repoint
#     them at a real updater if update.sh ever gets ported.
#   * "the lazyvim module installs it" (EDITOR=nvim) dropped - lazyvim.sh
#     hasn't been ported either; the nvim check is just `command -v nvim`
#     regardless of how it got there.
#   * Every "mx-setup" marker/comment/backup-dir became "new-setup"
#     (~/.local/state/mx-setup -> ~/.local/state/new-setup, the .bashrc
#     marker blocks, etc.) so re-runs and hand-edits find the right thing.
#
# Everything else - the XDG migration, ble.sh, pokemon-colorscripts, the
# alias set itself - is unchanged from mx-setup's version. Verified on this
# machine before porting: unrar, 7z, unzip, rg, inxi, hwinfo, lshw, pactl and
# xrdb are all already present, so yt-dlp (yta-*/ytv-best) is the only
# package gap; nothing under ~/.config/bash, ~/.local/share/blesh or in
# ~/.bashrc yet, so there's no prior mx-setup shell install on this machine
# to collide with.
#
# Everything lands in ~/.config/bash/aliases.sh rather than ~/.bash_aliases,
# to keep $HOME clean (see _shell_xdg_migrate). .bashrc gets one marked line
# to source it. Personal aliases go in ~/.config/bash/aliases.local.sh,
# created once and never overwritten.

SHELL_REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

run_shell_setup() {
    log "=== Setting up bash aliases ==="

    if dry; then
        log "[dry] would install yt-dlp + pokemon-colorscripts"
        log "[dry] would build ble.sh into ~/.local/share/blesh and wire it into ~/.bashrc"
        log "[dry] would migrate stray dotfiles into ~/.config, ~/.local/state and ~/.cache"
        log "[dry] would write ~/.config/bash/aliases.sh and ~/.config/blesh/init.sh"
        log "[dry] would create ~/.config/bash/aliases.local.sh if missing"
        return
    fi

    _shell_install_deps
    _shell_install_pokemon
    _shell_install_blesh
    _shell_xdg_migrate
    _shell_write_blerc
    _shell_write_aliases
    _shell_write_personal
    # Order matters: the bash wiring appends to .bashrc, and ble-attach has to
    # stay the last line in the file, so ble.sh gets wired after it.
    _shell_wire_bash
    _shell_wire_blesh

    log "Bash aliases installed - run 'reload' or open a new terminal."
}

# Everything the alias file calls that this machine doesn't already ship.
_shell_install_deps() {
    log "Installing packages the aliases depend on"
    install_if_missing yt-dlp
}

# pokemon-colorscripts: the random Pokemon sprite printed on every new shell.
# Not in the Debian/MX repos, so it's installed from source the way upstream's
# install.sh does it - files to /usr/local/opt, symlink in /usr/local/bin.
_shell_install_pokemon() {
    if command -v pokemon-colorscripts >/dev/null; then
        warn "pokemon-colorscripts already installed, skipping"
        return
    fi
    if ! command -v git >/dev/null; then
        warn "git not installed, skipping pokemon-colorscripts"
        return
    fi

    log "Installing pokemon-colorscripts"
    local tmp
    tmp="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap "rm -rf '$tmp'" RETURN

    git clone --depth 1 -q https://gitlab.com/phoneybadger/pokemon-colorscripts.git \
        "$tmp/pcs" || { warn "clone failed, skipping pokemon-colorscripts"; return; }
    ( cd "$tmp/pcs" && sudo ./install.sh )
    log "pokemon-colorscripts installed"
}

# ble.sh - the fish-style line editor for bash: grey inline suggestions as you
# type (accept with the right-arrow), plus live syntax highlighting. Bash's own
# tab completion (bash-completion, already installed on MX) can't do this;
# ble.sh replaces bash's readline loop entirely, which is why it's a source
# build rather than an apt package - it isn't in the Debian repos.
#
# Builds to ~/.local, so no sudo. Needs make + gawk, both already on MX.
_shell_install_blesh() {
    if [[ -f ~/.local/share/blesh/ble.sh ]]; then
        warn "ble.sh already installed, skipping build"
        return
    fi
    if ! command -v make >/dev/null || ! command -v gawk >/dev/null; then
        warn "make/gawk missing, skipping ble.sh"
        return
    fi

    log "Building ble.sh (this takes a minute)"
    local tmp
    tmp="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap "rm -rf '$tmp'" RETURN

    # --recursive: ble.sh keeps its contrib/ files in a submodule.
    git clone --recursive --depth 1 --shallow-submodules -q \
        https://github.com/akinomyoga/ble.sh.git "$tmp/blesh" \
        || { warn "clone failed, skipping ble.sh"; return; }
    make -C "$tmp/blesh" -s install >/dev/null \
        || { warn "ble.sh build failed, skipping"; return; }
    log "ble.sh installed to ~/.local/share/blesh"
}

# ---------------------------------------------------------------------------
# XDG base directories
#
# Keeps $HOME from filling up with dotfiles: config in ~/.config, state (things
# that persist but aren't config) in ~/.local/state, throwaway data in ~/.cache.
# Only files that can be moved *safely* are moved - each one either has native
# XDG support or is redirected by an env var this script also sets.
#
# Deliberately NOT moved:
#   .bashrc/.profile/.bash_logout - bash reads these from $HOME, full stop.
#   .gtkrc-2.0    - GTK2_RC_FILES would have to be set session-wide, not just in
#                   bash, or apps launched from the KDE menu lose their theming.
#   .pki, .var, .claude* - owned by other tools, no XDG support to hook.
#   .vboxclient-*.pid - recreated by VirtualBox guest additions on every login;
#                   only relevant if VirtualBox (modules/apps.sh) is installed.
# ---------------------------------------------------------------------------
_shell_xdg_migrate() {
    log "Migrating dotfiles to XDG directories"
    mkdir -p ~/.config/bash ~/.config/blesh ~/.config/readline ~/.config/wget \
             ~/.local/state/bash ~/.cache/less

    # Move only if the source exists and the destination is still free, so a
    # re-run never clobbers a newer file with an older stray one.
    _shell_xdg_move ~/.blerc         ~/.config/blesh/init.sh
    _shell_xdg_move ~/.inputrc       ~/.config/readline/inputrc
    _shell_xdg_move ~/.bash_history  ~/.local/state/bash/history
    _shell_xdg_move ~/.bash_aliases  ~/.config/bash/aliases.sh
    _shell_xdg_move ~/.bash_aliases.local ~/.config/bash/aliases.local.sh

    # wget writes ~/.wget-hsts unless told otherwise; WGETRC (exported in the
    # alias file) points it here.
    if [[ ! -f ~/.config/wget/wgetrc ]]; then
        echo 'hsts-file = ~/.cache/wget-hsts' > ~/.config/wget/wgetrc
    fi
    if [[ -f ~/.wget-hsts ]]; then
        mv -f ~/.wget-hsts ~/.cache/wget-hsts
    fi

    # npm's cache dir. Moved rather than deleted - npm would rebuild it, but
    # it's not this script's to throw away.
    if [[ -d ~/.npm && ! -d ~/.cache/npm ]]; then
        mv ~/.npm ~/.cache/npm
        log "  ~/.npm -> ~/.cache/npm"
    fi

    # Backups this script made on earlier runs - safe to drop once the new
    # layout is in place, and they're the bulk of the clutter it added.
    local b
    for b in ~/.bashrc.backup-* ~/.bash_aliases.backup-*; do
        if [[ -f "$b" ]]; then
            rm -f "$b"
            warn "Removed old backup $(basename "$b")"
        fi
    done
}

_shell_xdg_move() {
    local src="$1" dst="$2"
    if [[ -f "$src" && ! -e "$dst" ]]; then
        mv -f "$src" "$dst"
        log "  ${src/#$HOME/\~} -> ${dst/#$HOME/\~}"
    fi
}

# ble.sh's own settings file, sourced while ble.sh loads. ble.sh looks for
# ~/.blerc first and falls back to $XDG_CONFIG_HOME/blesh/init.sh, so putting it
# in .config keeps it out of $HOME with no extra wiring.
_shell_write_blerc() {
    log "Writing ~/.config/blesh/init.sh"
    mkdir -p ~/.config/blesh
    cat > ~/.config/blesh/init.sh <<'EOF'
# Managed by new-setup's modules/shell.sh

# Inline auto-suggestion (the grey text), drawn from shell history and from
# completion candidates. History as a source is on by default - the old
# complete_auto_history switch reports itself as [obsolete] in 0.4, so it's
# deliberately not set here; use complete_auto_complete_opts=history-disabled
# if you ever want history suggestions off.
bleopt complete_auto_complete=1
bleopt complete_auto_delay=150      # ms of idle typing before the suggestion shows

# Grey suggestion text instead of ble.sh's default light-background style.
ble-face auto_complete=fg=245

# Right-arrow accepts the suggestion out of the box; C-f as well, as in fish.
# TAB is deliberately left alone - it stays normal completion, independent of
# the inline suggestion.
ble-bind -m auto_complete -f 'C-f' auto_complete/insert
EOF
}

# ---------------------------------------------------------------------------
# ~/.bashrc is shared territory.
#
# Plenty of third-party installers append to it (nvm, rustup, conda and
# friends all would). Their lines are left ALONE on purpose: most are
# load-bearing (a shell function, a required init, an env file to source), so
# deleting them breaks software that was installed deliberately. new-setup
# owns its marked blocks, nothing else.
#
# What does need defending is the one structural invariant this module relies
# on: ble-attach must be the LAST line in the file (see _shell_wire_blesh).
# Anything appended afterwards lands past it and runs against an
# already-attached editor. So the tail is re-asserted rather than the
# intruder removed - which works for any tool, including ones that don't
# exist yet.
#
# Call this after anything that may have appended to ~/.bashrc.
# ---------------------------------------------------------------------------
_shell_reassert_bashrc_tail() {
    local rc=~/.bashrc
    [[ -f "$rc" ]] || return 0
    # Already last (bar trailing blank lines)? Then there's nothing to repair.
    if [[ "$(grep -v '^[[:space:]]*$' "$rc" | tail -1)" == '# <<< new-setup ble.sh <<<' ]]; then
        return 0
    fi
    log "Something appended to ~/.bashrc after ble-attach - moving it back to the end"
    _shell_wire_blesh
}

# MX's stock .bashrc sources ~/.bash_aliases, which no longer exists now that the
# alias file lives in ~/.config/bash. This adds the one line that replaces it,
# in the same marker style as the ble.sh wiring so re-runs don't stack copies.
_shell_wire_bash() {
    local rc=~/.bashrc
    sed -i '/# >>> new-setup bash >>>/,/# <<< new-setup bash <<</d' "$rc"

    log "Wiring ~/.config/bash/aliases.sh into ~/.bashrc"
    {
        echo '# >>> new-setup bash >>>'
        echo '[[ -f ~/.config/bash/aliases.sh ]] && . ~/.config/bash/aliases.sh'
        echo '# <<< new-setup bash <<<'
    } >> "$rc"
}

# The two lines upstream recommends (README 1.3): load early with --attach=none,
# attach at the very end, so ble.sh doesn't interfere with the rest of .bashrc.
# Both are wrapped in markers so re-running replaces them instead of stacking,
# and so they're easy to find and delete by hand.
_shell_wire_blesh() {
    local rc=~/.bashrc
    [[ -f ~/.local/share/blesh/ble.sh ]] || { warn "ble.sh not installed, not wiring .bashrc"; return; }

    # Backups go to state, not $HOME - otherwise every run drops another
    # .bashrc.backup-* into the home dir the migration just cleaned up.
    mkdir -p ~/.local/state/new-setup
    cp -f "$rc" ~/.local/state/new-setup/"bashrc.backup-$(date +%Y.%m.%d-%H.%M.%S)"
    # Drop any previous block so this stays idempotent.
    sed -i '/# >>> new-setup ble.sh >>>/,/# <<< new-setup ble.sh <<</d' "$rc"

    log "Wiring ble.sh into ~/.bashrc"
    local tmp
    tmp="$(mktemp)"
    {
        echo '# >>> new-setup ble.sh >>>'
        echo '[[ $- == *i* ]] && source -- ~/.local/share/blesh/ble.sh --attach=none'
        echo '# <<< new-setup ble.sh <<<'
        cat "$rc"
        echo '# >>> new-setup ble.sh >>>'
        echo '[[ ! ${BLE_VERSION-} ]] || ble-attach'
        echo '# <<< new-setup ble.sh <<<'
    } > "$tmp"
    mv -f "$tmp" "$rc"
}

# Regenerated wholesale on every run: this file is owned by the script, and
# anything hand-written belongs in ~/.config/bash/aliases.local.sh instead. A
# timestamped backup is kept anyway in case something was edited in place.
_shell_write_aliases() {
    mkdir -p ~/.config/bash
    if [[ -f ~/.config/bash/aliases.sh ]]; then
        cp -f ~/.config/bash/aliases.sh \
              ~/.config/bash/"aliases.sh.backup-$(date +%Y.%m.%d-%H.%M.%S)"
    fi

    log "Writing ~/.config/bash/aliases.sh"
    cat > ~/.config/bash/aliases.sh <<'EOF'
# Managed by new-setup's modules/shell.sh - regenerated on every run.
# Put your own aliases in ~/.config/bash/aliases.local.sh (sourced at the end).

### ENVIRONMENT ###
if command -v nvim >/dev/null; then
    export EDITOR='nvim'
    export VISUAL='nvim'
else
    export EDITOR='nano'
    export VISUAL='nano'
fi

# Unlimited history, de-duplicated, timestamped, shared across terminals.
export HISTCONTROL=ignoreboth:erasedups
export HISTSIZE=-1
export HISTFILESIZE=-1
export HISTTIMEFORMAT='%F %T '
PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND; }history -a"

[[ -d "$HOME/.bin"       ]] && PATH="$HOME/.bin:$PATH"
[[ -d "$HOME/.local/bin" ]] && PATH="$HOME/.local/bin:$PATH"
# npm's user prefix, if one is ever set up. Prepended last so it beats
# /usr/bin - a user-local Claude Code (or anything else) can only self-update
# from a user-writable install.
[[ -d "$HOME/.npm-global/bin" ]] && PATH="$HOME/.npm-global/bin:$PATH"

### XDG - keep $HOME free of stray dotfiles ###
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"

# Each of these otherwise drops a dotfile straight into $HOME.
export HISTFILE="$XDG_STATE_HOME/bash/history"   # was ~/.bash_history
export INPUTRC="$XDG_CONFIG_HOME/readline/inputrc" # was ~/.inputrc
export WGETRC="$XDG_CONFIG_HOME/wget/wgetrc"     # was ~/.wget-hsts
export LESSHISTFILE="$XDG_CACHE_HOME/less/history" # pre-empts ~/.lesshst
export npm_config_cache="$XDG_CACHE_HOME/npm"    # was ~/.npm

### SHELL OPTIONS ###
shopt -s autocd         # 'Documents' alone cd's into it
shopt -s cdspell        # autocorrect cd typos
shopt -s dirspell       # autocorrect directory names during completion
shopt -s cmdhist        # multi-line commands stored as one history entry
shopt -s histappend     # append to history, don't overwrite
shopt -s expand_aliases
shopt -s globstar       # ** matches recursively
shopt -s checkwinsize
shopt -s dotglob

# Case-insensitive TAB completion, and ↑/↓ search history by what's typed.
bind "set completion-ignore-case on" 2>/dev/null
bind "set show-all-if-ambiguous on"  2>/dev/null
bind '"\e[A": history-search-backward' 2>/dev/null
bind '"\e[B": history-search-forward'  2>/dev/null

### LIST ###
alias ls='ls --color=auto'
alias ll='ls -alFh'
alias la='ls -A'
alias l='ls -CF'
alias l.="ls -A | grep -E '^\.'"
alias listdir="ls -d */"

### APT  (Arco's pacman aliases, translated) ###
alias sai='sudo apt install'            # was sps  (pacman -S)
alias sar='sudo apt remove'             # was spr  (pacman -R)
alias sarp='sudo apt purge'             # was sprs (pacman -Rs)
alias sarr='sudo apt autoremove --purge'
alias aptup='sudo apt update && sudo apt full-upgrade'
# mx-setup's 'update'/'upd'/'upall'/'upcheck' point at mx-update, a self-updater
# for its tarball-installed apps (deployed by its modules/update.sh). That
# module hasn't been ported here, so these just run plain apt for now -
# repoint them at a real updater if update.sh ever gets ported.
alias update='sudo apt update && sudo apt full-upgrade'
alias upd='sudo apt update && sudo apt full-upgrade'
alias upall='sudo apt update && sudo DEBIAN_FRONTEND=noninteractive apt full-upgrade -y'
alias upcheck='sudo apt update && apt list --upgradable'
alias search='apt search'
alias show='apt show'                   # was spsii (pacman -Sii)
alias owns='dpkg -S'                    # was spqo  (pacman -Qo) - which pkg owns a file
alias files='dpkg -L'                   # list files a package installed

# Which packages depend on this one - Arco's function_depends/'depends'.
function_depends() { apt-cache rdepends --installed "$1"; }
alias depends='function_depends'

# Fix typos, same as Arco did for pacman.
alias udpate='update'
alias upate='update'
alias updte='update'
alias updqte='update'

# Arco's 'unlock' removed pacman's db.lck. The apt equivalent: clear the dpkg/apt
# locks and finish any half-done install. Only run this with no apt running.
alias unlock='sudo rm -f /var/lib/apt/lists/lock /var/cache/apt/archives/lock /var/lib/dpkg/lock /var/lib/dpkg/lock-frontend && sudo dpkg --configure -a'

alias cleanup='sudo apt autoremove --purge && sudo apt clean'
alias list='apt-mark showmanual'        # explicitly installed (was pacman -Qqe)
alias listt='apt list --installed'
# Recently installed packages, newest last (was 'rip'/expac).
alias rip="grep ' install ' /var/log/dpkg.log | tail -200 | nl"
alias riplong="zgrep -h ' install ' /var/log/dpkg.log* | sort | tail -3000 | nl"
# Biggest installed packages (was 'big'/expac -H M).
alias big="dpkg-query -Wf '\${Installed-Size}\t\${Package}\n' | sort -n | nl"
# MX's repo manager replaces reflector/rate-mirrors for picking a fast mirror.
alias mirror='mx-repo-manager'

### SYSTEM INFO ###
alias hw='hwinfo --short'
alias probe='inxi -Fxxxz'               # was arcolinux-probe
alias mxver='cat /etc/mx-version'       # was iso/isoo (/etc/dev-rel)
alias howold='sudo lshw | grep -B 3 -A 8 BIOS'
alias microcode='grep . /sys/devices/system/cpu/vulnerabilities/*'
alias audio="pactl info | grep 'Server Name'"
alias kernels='ls /usr/lib/modules'
alias kernel='ls /usr/lib/modules'
alias xd='ls /usr/share/xsessions'
alias xdw='ls /usr/share/wayland-sessions'
alias userlist='cut -d: -f1 /etc/passwd | sort'
alias sysfailed='systemctl list-units --failed'
alias jctl='journalctl -p 3 -xb'        # errors since boot
alias free='free -mth'
alias df='df -h'
alias psa='ps auxf'
alias psgrep="ps aux | grep -v grep | grep -i -e VSZ -e"

### GREP / SEARCH ###
alias grep='grep --color=auto'
alias egrep='egrep --color=auto'
alias fgrep='fgrep --color=auto'
alias rg='rg --sort path'

### TIMESHIFT  (replaces Arco's snapper aliases) ###
alias snap='sudo timeshift --create --comments'
alias snapli='sudo timeshift --list'
alias snaprm='sudo timeshift --delete'

### CONFIG FILES  (Arco's n* family, on Debian paths) ###
alias nsources="sudo $EDITOR /etc/apt/sources.list"          # was npacman
alias nsourcesd="sudo $EDITOR /etc/apt/sources.list.d/"      # was nmirrorlist
alias ngrub="sudo $EDITOR /etc/default/grub"
alias nconfgrub="sudo $EDITOR /boot/grub/grub.cfg"
alias ninitramfs="sudo $EDITOR /etc/initramfs-tools/initramfs.conf"  # was nmkinitcpio
alias nfstab="sudo $EDITOR /etc/fstab"
alias nhosts="sudo $EDITOR /etc/hosts"
alias nhostname="sudo $EDITOR /etc/hostname"
alias nresolv="sudo $EDITOR /etc/resolv.conf"
alias nnsswitch="sudo $EDITOR /etc/nsswitch.conf"
alias nsamba="sudo $EDITOR /etc/samba/smb.conf"
alias nenvironment="sudo $EDITOR /etc/environment"
alias nsddm="sudo $EDITOR /etc/sddm.conf"
alias nsddmk="sudo $EDITOR /etc/sddm.conf.d/kde_settings.conf"
alias nlightdm="sudo $EDITOR /etc/lightdm/lightdm.conf"
alias nb="$EDITOR ~/.bashrc"
alias na="$EDITOR ~/.config/bash/aliases.local.sh"
alias nv="$EDITOR ~/.config/nvim"

### LOGS  (Arco read pacman.log; apt's equivalents) ###
alias lapt='less /var/log/apt/history.log'
alias lterm='less /var/log/apt/term.log'
alias ldpkg='less /var/log/dpkg.log'
alias lxorg='less /var/log/Xorg.0.log'

### SYSTEM MAINTENANCE ###
alias update-fc='sudo fc-cache -fv'
alias fix-permissions="sudo chown -R $USER:$USER ~/.config ~/.local"
alias merge='xrdb -merge ~/.Xresources'
alias setlocale='sudo localectl set-locale LANG=en_US.UTF-8'
alias give-me-qwerty-us='sudo localectl set-x11-keymap us'
alias tobash='sudo chsh $USER -s /bin/bash && echo "Now log out."'
alias tozsh='sudo chsh $USER -s /bin/zsh && echo "Now log out."'
alias ssn='sudo shutdown now'
alias sr='reboot'

### GIT ###
alias grh='git reset --hard'
alias rmgitcache='rm -r ~/.cache/git'

### DOWNLOAD ###
alias wget='wget -c'
alias yta-best='yt-dlp --extract-audio --audio-format best '
alias yta-mp3='yt-dlp --extract-audio --audio-format mp3 '
alias yta-flac='yt-dlp --extract-audio --audio-format flac '
alias ytv-best="yt-dlp -f 'bestvideo[ext=mp4]+bestaudio[ext=m4a]/bestvideo+bestaudio' --merge-output-format mp4 "

### TYPOS / SHORTCUTS ###
alias cd..='cd ..'
alias pdw='pwd'
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
# 'exec bash' rather than 'source ~/.bashrc': re-sourcing .bashrc makes ble.sh
# load a second time over an attached instance, which prints "[ble: reload]" and
# tears the editor down and back up. A fresh exec is silent, and it genuinely
# reloads everything - ble.sh config and ~/.config/blesh/init.sh included.
alias reload='exec bash'                # was 'cb' (copied from /etc/skel)

### THIS REPO ###
alias nws='@NEW_SETUP_DIR@/main.sh'
alias nwsdry='@NEW_SETUP_DIR@/main.sh --dry-run'
alias nnws="$EDITOR @NEW_SETUP_DIR@"

# ex = EXtractor for all kinds of archives - usage: ex <file>
# Straight from Arco's .bashrc, unchanged; it was already distro-agnostic.
ex() {
  if [ -f "$1" ] ; then
    case "$1" in
      *.tar.bz2)   tar xjf "$1"   ;;
      *.tar.gz)    tar xzf "$1"   ;;
      *.tar.xz)    tar xf "$1"    ;;
      *.tar.zst)   tar xf "$1"    ;;
      *.bz2)       bunzip2 "$1"   ;;
      *.rar)       unrar x "$1"   ;;
      *.gz)        gunzip "$1"    ;;
      *.tar)       tar xf "$1"    ;;
      *.tbz2)      tar xjf "$1"   ;;
      *.tgz)       tar xzf "$1"   ;;
      *.zip)       unzip "$1"     ;;
      *.Z)         uncompress "$1";;
      *.7z)        7z x "$1"      ;;
      *.deb)       ar x "$1"      ;;
      *)           echo "'$1' cannot be extracted via ex()" ;;
    esac
  else
    echo "'$1' is not a valid file"
  fi
}
alias extract='ex'

# Personal aliases - never overwritten by new-setup.
[[ -f ~/.config/bash/aliases.local.sh ]] && . ~/.config/bash/aliases.local.sh

### GREETING ###
# Random Pokemon on every new shell, sprite only (--no-title hides the name).
# The $- guard keeps the art out of non-interactive shells, so it can't corrupt
# scp/rsync/ssh-command output the way an unguarded greeting would.
if [[ $- == *i* ]] && command -v pokemon-colorscripts >/dev/null; then
    pokemon-colorscripts --random --no-title
fi
EOF

    # @NEW_SETUP_DIR@ is a literal placeholder in the heredoc above (the
    # heredoc is quoted, so $SHELL_REPO_DIR can't expand there directly) -
    # substitute in the real path now, resolved once at the top of this file.
    sed -i "s|@NEW_SETUP_DIR@|$SHELL_REPO_DIR|g" ~/.config/bash/aliases.sh
}

# Created once, then left alone forever.
_shell_write_personal() {
    mkdir -p ~/.config/bash
    if [[ -f ~/.config/bash/aliases.local.sh ]]; then
        warn "~/.config/bash/aliases.local.sh exists, leaving it untouched"
        return
    fi
    log "Creating ~/.config/bash/aliases.local.sh for personal aliases"
    cat > ~/.config/bash/aliases.local.sh <<'EOF'
# Personal aliases. new-setup never overwrites this file.
EOF
}
