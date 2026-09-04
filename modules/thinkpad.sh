#!/bin/bash
# ThinkPad-specific hardware setup (tested on a ThinkPad X13 Yoga Gen 2,
# 11th-gen Intel, thinkpad_acpi + platform_profile, Synaptics fingerprint
# reader). Re-check the "skipped on purpose" items below before reusing this
# on different ThinkPad hardware - the reasoning is model-dependent.

run_thinkpad_setup() {
    log "=== ThinkPad hardware setup ==="

    configure_battery_thresholds
    check_fingerprint_reader
    configure_natural_scrolling

    # --- Deliberately NOT done here, and why ---
    #
    # TLP: power-profiles-daemon is already installed and active on this
    # machine (KDE's battery widget talks to it directly). TLP and
    # power-profiles-daemon both try to own the same CPU/power knobs and
    # actively conflict if both run - installing TLP without first masking
    # power-profiles-daemon (and losing the KDE power-profile UI) would fight
    # itself, not improve battery life. Skip unless you deliberately want to
    # switch power backends.
    #
    # thinkfan: this model's fan is already in EC-controlled "auto" mode via
    # thinkpad_acpi (cat /proc/acpi/ibm/fan -> level: auto) and exposes
    # platform_profile (low-power/balanced/performance) instead of the old
    # fan_control=1 interface thinkfan needs. Forcing fan_control=1 to let
    # thinkfan drive the fan overrides the embedded controller's own curve -
    # on hardware where thinkfan isn't actually needed, a wrong fan config
    # (e.g. a copy-pasted config for a different ThinkPad model) can mean the
    # fan doesn't spool up when it should. Not worth the risk here.
    #
    # tp-smapi-dkms: legacy battery/fan interface for older (pre-2011-ish)
    # ThinkPads. This model's battery thresholds already work natively
    # through thinkpad_acpi (see configure_battery_thresholds below) -
    # installing tp-smapi-dkms on top can conflict with thinkpad_acpi over
    # the same battery sysfs nodes.
}

# thinkpad_acpi exposes charge_control_start_threshold /
# charge_control_end_threshold directly under the battery's power_supply
# node - no extra package needed, and the EC persists these across reboots
# on its own. 75/80 is a conservative "keep it mostly charged but stop
# short of 100%" setting to reduce battery wear; raise charge_control_end
# back to 100 (or just delete the systemd unit below) if you want full
# capacity for travel instead.
configure_battery_thresholds() {
    local start=75 stop=80
    local bat
    bat="$(basename "$(ls -d /sys/class/power_supply/BAT* 2>/dev/null | head -1)")"

    if [[ -z "$bat" || ! -f "/sys/class/power_supply/$bat/charge_control_start_threshold" ]]; then
        warn "No charge_control_start_threshold found - skipping battery threshold setup"
        return 0
    fi

    log "Setting battery charge thresholds on $bat: start=${start}% stop=${stop}%"
    run sudo sh -c "echo $start > /sys/class/power_supply/$bat/charge_control_start_threshold"
    run sudo sh -c "echo $stop > /sys/class/power_supply/$bat/charge_control_end_threshold"

    # Belt-and-suspenders: reapply on every boot in case a firmware update or
    # battery swap ever resets the EC value back to 0/100.
    log "Installing systemd unit to reapply thresholds on every boot"
    run sudo tee /etc/systemd/system/thinkpad-battery-thresholds.service >/dev/null <<EOF
[Unit]
Description=Reapply ThinkPad battery charge thresholds
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'echo $start > /sys/class/power_supply/$bat/charge_control_start_threshold; echo $stop > /sys/class/power_supply/$bat/charge_control_end_threshold'

[Install]
WantedBy=multi-user.target
EOF
    run sudo systemctl daemon-reload
    run sudo systemctl enable --now thinkpad-battery-thresholds.service
}

# Detection only - no PAM changes. Wiring fingerprint auth into
# login/sudo/screen-unlock means editing /etc/pam.d/*, and a mistake there
# can lock you out of authentication entirely. Plasma 6 has its own
# Fingerprint page under System Settings > Users that does this safely and
# interactively, so point at that instead of scripting it.
check_fingerprint_reader() {
    if ! lsusb 2>/dev/null | grep -qiE 'fingerprint|synaptics|goodix|validity|elan'; then
        warn "No fingerprint reader detected, skipping"
        return 0
    fi

    install_if_missing fprintd

    if dry; then
        log "[dry] would check fingerprint enrollment status"
        return 0
    fi

    if fprintd-list "$(whoami)" 2>&1 | grep -q "no fingers enrolled"; then
        warn "Fingerprint reader detected but no fingers enrolled."
        warn "Enroll one with: fprintd-enroll   (or System Settings > Users > Fingerprint)"
        warn "Then enable fingerprint login/unlock/sudo from System Settings, not from this script."
    else
        log "Fingerprint reader already has enrolled prints."
    fi
}

# Natural (inverted) touchpad scrolling - content follows finger direction
# instead of the traditional "wheel" direction. Verified live on this
# machine (2026-09): toggling System Settings > Input Devices > Touchpad's
# natural-scrolling switch wrote NaturalScroll=true under a per-device
# Libinput group in kcminputrc, keyed [Libinput][<vendor-dec>][<product-dec>]
# [<device name>] - 1267/12691 below are this ThinkPad's touchpad
# (ELAN0674:00 04F3:3193 Touchpad, 0x04F3=1267, 0x3193=12691) in decimal.
# KDE's kded_touchpad module watches kcminputrc and applies changes live
# (same as the GUI toggle did), so no reconfigure/reload call is needed.
# Re-check the vendor/product IDs (cat /proc/bus/input/devices) before
# reusing this on different ThinkPad hardware - a different touchpad chip
# means a different group, and writing to the wrong one silently no-ops.
configure_natural_scrolling() {
    log "Enabling natural (inverted) touchpad scrolling"
    run kwriteconfig6 --file kcminputrc \
        --group Libinput --group 1267 --group 12691 \
        --group "ELAN0674:00 04F3:3193 Touchpad" \
        --key NaturalScroll --type bool true
}
