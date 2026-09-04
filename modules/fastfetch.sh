#!/bin/bash
# Fastfetch customization: the "Tsukiyomi Fetch" theme from
# https://github.com/Thunder-Blaze/tsukiyomi-fetch - a fixed custom logo (see
# below) and a boxed System Specs / Software Specs layout. Upstream also
# ships a "Personal Stats" section that shells out to a bundled Rust binary
# for live GitHub/Discord/Anilist/MyAnimeList/Reddit/Twitter/CodeChef/
# Codeforces/LeetCode/Simkl/Instagram stats - that binary (a prebuilt
# x86-64 ELF checked into the upstream repo) is still installed to
# ~/.config/fastfetch/tsukiyomi-fetch, but its module entries are stripped
# out of config.jsonc/config2.jsonc below, since most of those platforms need
# per-platform usernames/tokens nobody's filled in and a couple (Instagram in
# particular) hit upstream rate limits even when configured. Run
# `~/.config/fastfetch/tsukiyomi-fetch --setup` yourself and hand-add module
# entries back into the configs for whichever platforms you actually want.
#
# Upstream's logo block picks a random image from pngs/ and has no explicit
# "type", so fastfetch auto-detects an image protocol from the terminal - on
# this machine's Konsole that picked something Konsole can't actually render
# (garbled escape-sequence output instead of the logo). Two changes on top of
# upstream, both applied post-copy below:
#  * the source is pinned to assets/fastfetch-logo.png (a specific character
#    picture the user chose), not a random pick from pngs/.
#  * "type": "sixel" is forced - fastfetch transmits the actual image as a
#    Sixel graphic. Tried "kitty" first (this machine's Konsole is 25.4.2,
#    KONSOLE_VERSION=250402), but on this Konsole build it silently
#    degrades to the same letter-shaded ASCII art as "chafa" instead of
#    drawing the picture or erroring, so that's confirmed NOT to work here.
#    If sixel also fails to render (garbled output, or the same ASCII
#    fallback again), the known-good fallback is "type": "chafa" - it does
#    draw *something* everywhere, just as ASCII/block-art, not a real image.

FASTFETCH_TSUKIYOMI_REPO="https://github.com/Thunder-Blaze/tsukiyomi-fetch.git"
FASTFETCH_DIR="$HOME/.config/fastfetch"
FASTFETCH_LOGO_ASSET="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/assets/fastfetch-logo.png"

run_fastfetch_setup() {
    log "=== Installing the Tsukiyomi Fetch fastfetch theme ==="

    install_if_missing fastfetch

    if dry; then
        log "[dry] would clone $FASTFETCH_TSUKIYOMI_REPO and copy its fastfetch/*"
        log "[dry] (config.jsonc, config2.jsonc, pngs/, the tsukiyomi-fetch binary)"
        log "[dry] into $FASTFETCH_DIR, then pin the logo to $FASTFETCH_LOGO_ASSET"
        return 0
    fi

    if [[ -x "$FASTFETCH_DIR/tsukiyomi-fetch" ]]; then
        warn "Tsukiyomi Fetch already installed, skipping"
    else
        _fastfetch_install_tsukiyomi || return 1
    fi

    log "Tsukiyomi Fetch installed - run 'fastfetch' to see it."
    log "Personal Stats modules were stripped from config.jsonc/config2.jsonc."
    log "Run '$FASTFETCH_DIR/tsukiyomi-fetch --setup' and hand-add module"
    log "entries back in for whichever platforms you actually want."
}

_fastfetch_install_tsukiyomi() {
    local tmp
    tmp="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap "rm -rf '$tmp'" RETURN

    log "Cloning Tsukiyomi Fetch"
    if ! git clone --depth 1 -q "$FASTFETCH_TSUKIYOMI_REPO" "$tmp/tsukiyomi-fetch"; then
        err "Tsukiyomi Fetch clone failed"
        return 1
    fi

    if [[ -d "$FASTFETCH_DIR" ]]; then
        local backup="${FASTFETCH_DIR}.bak-$(date +%Y%m%d_%H%M%S)"
        warn "Existing $FASTFETCH_DIR found - backing it up to $backup"
        mv "$FASTFETCH_DIR" "$backup"
    fi

    mkdir -p "$FASTFETCH_DIR"
    cp -r "$tmp/tsukiyomi-fetch/fastfetch/." "$FASTFETCH_DIR/"
    chmod +x "$FASTFETCH_DIR/tsukiyomi-fetch"

    if [[ -f "$FASTFETCH_LOGO_ASSET" ]]; then
        cp "$FASTFETCH_LOGO_ASSET" "$FASTFETCH_DIR/fastfetch-logo.png"
    else
        warn "Custom logo asset not found at $FASTFETCH_LOGO_ASSET - leaving upstream's random pngs/ pick"
    fi

    # See the header note: pin the logo to the fixed asset (when present) and
    # force sixel-protocol rendering so it shows the actual picture instead
    # of garbled escape-sequence bytes or chafa's ASCII-art reconstruction.
    for f in "$FASTFETCH_DIR/config.jsonc" "$FASTFETCH_DIR/config2.jsonc"; do
        sed -i '/"logo": {/a\        "type": "sixel",' "$f"
        if [[ -f "$FASTFETCH_DIR/fastfetch-logo.png" ]]; then
            sed -i "s|\"source\": .*|\"source\": \"$FASTFETCH_DIR/fastfetch-logo.png\",|" "$f"
        fi
        _fastfetch_strip_personal_stats "$f"
    done

    log "Tsukiyomi Fetch files installed to $FASTFETCH_DIR"
}

# Drops every "modules" array entry that shells out to tsukiyomi-fetch (its
# "text" contains "tsukiyomi-fetch wrapper"), plus the "Personal Stats"
# header label. config.jsonc also boxes that section in its own
# single-line-glyph ┌/└ border (unlike config2.jsonc's outer ╔/╚ border,
# which wraps the whole layout and must survive) - a stripped section's
# ┌/└ border line is detected by checking whether its nearest non-"break"
# neighbor was itself removed, so it goes with it. A trailing "break" that
# would otherwise leave two in a row where the section used to be is
# collapsed down to one. Marker-based rather than hardcoded line numbers, so
# it survives minor upstream formatting drift.
_fastfetch_strip_personal_stats() {
    local f="$1"
    python3 - "$f" <<'PYEOF'
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as fh:
    lines = fh.readlines()

records = []  # (start, end) inclusive line indices; every module entry here
              # is a flat object (no nested braces) or a bare "break" string.
i, n = 0, len(lines)
in_modules = False
while i < n:
    if not in_modules:
        if '"modules": [' in lines[i]:
            in_modules = True
        i += 1
        continue
    stripped = lines[i].strip()
    if stripped in (']', '],'):
        break
    if stripped.startswith('{'):
        start = i
        while not lines[i].strip().startswith('}'):
            i += 1
        records.append((start, i))
        i += 1
    else:
        records.append((i, i))
        i += 1


def text_of(r):
    return ''.join(lines[r[0]:r[1] + 1])


def is_break(r):
    return lines[r[0]].strip().startswith('"break"')


def is_section_box(r):
    t = text_of(r)
    return ('┌' in t or '└' in t) and '╔' not in t and '╚' not in t


remove = [
    'tsukiyomi-fetch wrapper' in text_of(r) or 'Personal Stats' in text_of(r)
    for r in records
]

for idx, r in enumerate(records):
    if remove[idx] or not is_section_box(r):
        continue
    j = idx - 1
    while j >= 0 and is_break(records[j]):
        j -= 1
    k = idx + 1
    while k < len(records) and is_break(records[k]):
        k += 1
    if (j >= 0 and remove[j]) or (k < len(records) and remove[k]):
        remove[idx] = True

prev_kept_was_break = False
for idx, r in enumerate(records):
    if remove[idx]:
        continue
    if is_break(r):
        if prev_kept_was_break:
            remove[idx] = True
            continue
        prev_kept_was_break = True
    else:
        prev_kept_was_break = False

drop_lines = set()
for idx, r in enumerate(records):
    if remove[idx]:
        drop_lines.update(range(r[0], r[1] + 1))

out = [line for i, line in enumerate(lines) if i not in drop_lines]
with open(path, "w", encoding="utf-8") as fh:
    fh.writelines(out)
PYEOF
}
