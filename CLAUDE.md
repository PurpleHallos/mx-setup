# new-setup

Fresh-install setup automation for this specific machine: a ThinkPad X13 Yoga
Gen 2 (11th-gen Intel i5-1145G7), running MX Linux with KDE Plasma 6, Secure
Boot enabled. Modeled on the sibling `mx-setup` repo (same author, same
machine class), but rebuilt here module-by-module rather than copied wholesale
- currently covers debloat, ThinkPad hardware setup, app installs, a system
font, a fastfetch theme, bash aliases, KDE keyboard shortcuts, a Catppuccin
Mocha desktop theme, and per-application Catppuccin themes; more modules
(lazyvim, antigravity, an update-checker, etc.) may get ported over from
`mx-setup` later.

Entry point is `./main.sh`:
- `./main.sh debloat` - purge bundled/unwanted packages (`modules/debloat.sh`)
- `./main.sh thinkpad` - ThinkPad hardware setup: battery charge thresholds,
  fingerprint reader detection, and natural (inverted) touchpad scrolling
  (`modules/thinkpad.sh`)
- `./main.sh apps` - install gwenview/mpv/fastfetch/gh/wrangler/
  Spotify+spicetify/Telegram Desktop/Zed/Obsidian/Brave/VirtualBox
  (`modules/apps.sh`)
- `./main.sh devops` - install Docker CE + Compose v2, Vagrant, Terraform,
  jq, yq, kubectl, and Helm (`modules/devops.sh`)
- `./main.sh fonts` - install Ubuntu (Google Fonts) and set it as the KDE +
  GTK system UI font, and install JetBrainsMono Nerd Font as the fixed/
  monospace font (`modules/fonts.sh`)
- `./main.sh fastfetch` - install the Tsukiyomi Fetch fastfetch theme
  (`modules/fastfetch.sh`)
- `./main.sh shell` - bash aliases/settings ported from `mx-setup`
  (ArcoLinux's `.bashrc` translated to apt/dpkg), ble.sh, pokemon-colorscripts,
  and an XDG-directory dotfile migration (`modules/shell.sh`)
- `./main.sh shortcuts` - copies `kglobalshortcutsrc`/`khotkeysrc` (Arco
  Linux's KDE layout) from `stuff/shortcuts/` into `~/.config/`
  (`modules/shortcuts.sh`) - unlike mx-setup, `stuff/` is committed here,
  not gitignored; see the note below
- `./main.sh theme` - Catppuccin Mocha (Blue accent): the KDE global theme
  (`catppuccin/kde`), the SDDM login theme (`catppuccin/sddm`) with
  `assets/sddm-background.jpg` as its wallpaper, and Papirus-Dark icons
  (`papirus-icon-theme` apt package) (`modules/theme.sh`)
- `./main.sh app-themes` - per-application Catppuccin themes, as opposed to
  `theme`'s desktop-wide one; currently just Zed's (`catppuccin/zed`, Blue
  accent, dropped into `~/.config/zed/themes/` with `settings.json`'s
  `theme` block pointed at it) (`modules/app-themes.sh`)
- `./main.sh grub` - adds `loglevel=3` to `GRUB_CMDLINE_LINUX_DEFAULT` to
  quiet kernel boot log spam, then installs the Particle Circle sidebar GRUB
  theme from `PurpleHallos/Particle-circle-grub-theme` (sidebar variant,
  `1600p` screen size for this machine's 2560x1600 panel) into
  `/usr/share/grub/themes`, then runs `update-grub` (`modules/grub.sh`)
- `./main.sh all` - all of the above, in that order
- `--dry-run` (or `DRYRUN=1`) on any target prints every mutating command
  instead of running it

Shared helpers live in `lib/common.sh` (`run`, `purge_pkgs`, `require_sudo`,
`require_snapshot`, `install_if_missing`, `add_apt_repo`,
`ensure_user_in_group`). `debloat` requires a Timeshift snapshot before it
purges anything; `SKIP_SNAPSHOT=1` overrides that gate.

## Machine-specific facts worth knowing before editing modules

- **Secure Boot is enabled.** No module touches DKMS, kernel modules, or
  shim/MOK signing - keep it that way unless there's a real need, since
  anything unsigned there won't load. `modules/grub.sh` is the one exception
  to "don't touch GRUB", and deliberately a narrow one: it only edits
  `GRUB_CMDLINE_LINUX_DEFAULT` (a plain text boot parameter) and installs a
  GRUB theme (background/fonts/`theme.txt` - plain data grub reads at boot,
  not a boot-chain binary) - never anything that needs to be signed. Keep any
  future GRUB changes to that same category.
- Three out-of-tree Wi-Fi drivers already run via DKMS (`8812au`,
  `broadcom-sta`, `rtl8821cu`), already rebuilding/signing fine across kernel
  upgrades. A `debloat` run's `full-upgrade` can pull in a new kernel, which
  retriggers that DKMS rebuild - if a MOK Manager prompt appears on next boot,
  that's normal, don't skip it.
- **`power-profiles-daemon` is installed and active** (KDE's battery widget
  talks to it directly) - don't add TLP without first deciding to replace it,
  since the two fight over the same power knobs.
- **Fan is already in EC-controlled auto mode** via `thinkpad_acpi` /
  `platform_profile` (low-power/balanced/performance) - don't add `thinkfan`
  without a real reason; it needs the legacy `fan_control=1` interface, which
  overrides the EC's own curve.
- Battery charge thresholds work natively through `thinkpad_acpi` sysfs
  (`charge_control_start_threshold` / `charge_control_end_threshold`) - no
  `tp-smapi-dkms` needed, and installing it can conflict with `thinkpad_acpi`
  over the same nodes.
- Fingerprint reader is a Synaptics sensor, detected via `lsusb`, handled by
  `fprintd` (userspace only, no kernel module). PAM wiring
  (login/sudo/unlock) is deliberately left to System Settings > Users >
  Fingerprint, not scripted - a bad PAM edit can lock out authentication
  entirely.
- **Node.js/Claude Code are managed via nvm on this machine already**, not
  by `modules/apps.sh` - don't add mx-setup's NodeSource-repo install for
  either; it would create a second, conflicting Node install alongside nvm's.
- `flatpak` is installed here but has zero remotes configured - so, like
  mx-setup's machine (which lacks flatpak entirely), it's not currently a
  usable install source, just for a different reason. Worth rechecking if a
  remote (e.g. Flathub) ever gets added.
- VirtualBox's kernel modules build via `/sbin/vboxconfig`, not through the
  DKMS + MOK path the Wi-Fi drivers use - with Secure Boot enabled, there's
  no guarantee `vboxdrv` loads. `modules/apps.sh` only warns if it doesn't;
  see that file's header for what to check before treating it as a bug.
- `modules/fastfetch.sh` strips tsukiyomi-fetch's "Personal Stats" module
  entries out of `config.jsonc`/`config2.jsonc` (most need per-platform
  usernames/tokens nobody's filled in, and Instagram hits upstream rate
  limits even when configured). The binary itself is still installed to
  `~/.config/fastfetch/tsukiyomi-fetch` - run `--setup` and hand-add module
  entries back in for whichever platforms you actually want.
- `modules/shell.sh`'s `update`/`upd`/`upall`/`upcheck` aliases just run
  plain apt - `mx-setup`'s `mx-update` self-updater (`modules/update.sh`,
  for its tarball-installed apps) hasn't been ported here yet.
- `modules/shortcuts.sh` needs `stuff/shortcuts/kglobalshortcutsrc` and
  `khotkeysrc` (Arco Linux's KDE layout) to do anything. mx-setup gitignores
  its own copy and it was missing from disk when this was ported, so both
  were re-fetched from `etc/skel/.config/` in
  https://github.com/arcolinux/arcolinux-plasma (identical byte-for-byte to
  the same paths in arcolinux-plasma-nemesis, checked at port time) and
  committed into `stuff/shortcuts/` here instead of gitignored - it's an
  unmodified public template, not personal data, and a from-scratch clone
  needs it to actually reproduce this setup. It overwrites
  `~/.config/kglobalshortcutsrc`/`khotkeysrc` outright (no merge) when run.
- `modules/theme.sh` hardcodes the flavour/accent/window-decoration choices
  (Mocha, Blue, Classic - started on Mauve, switched after the
  Mauve-colored active-task highlight clashed with other panel icons)
  rather than prompting - all three components were installed and
  hand-verified live on this machine before being scripted (see the
  module's own comments for exactly how each was checked). It assumes
  `sddm-greeter-qt6` (this machine's greeter) and hardcodes
  `plasma-changeicons`'s path since that binary isn't on `$PATH` - both are
  worth re-checking if this ever runs on a different Plasma install. The
  module also sets `AccentColorFromWallpaper=true` in `kdeglobals`
  (System Settings > Colors > "Accent color: from wallpaper"), which then
  overrides just the Selection/Highlight color on top of whatever the KDE
  color scheme provides - that config key isn't documented anywhere, it was
  found by extracting strings from the compiled Colors KCM
  (`kcm_colors.so`).

## Rules for Claude Code in this repo

- **Never add a `Co-Authored-By: Claude` trailer — or any other AI
  attribution — to git commits or PRs.** Same policy as `mx-setup`.
