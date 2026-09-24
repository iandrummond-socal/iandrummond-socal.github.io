#!/usr/bin/env bash
# dp-lock-hbr3.sh — pin the Apple Studio Display's DisplayPort link to
# 4 lanes @ HBR3 (8.1 Gb/s per lane) so amdgpu stops renegotiating the link
# rate, which blanks the panel to grey.
#
# Installed as /usr/local/bin/dp-lock-hbr3.sh. Run as root (debugfs) by
# dp-lock-hbr3.service at boot and, via 99-dp-lock-hbr3.rules, on every
# DRM hotplug. Logs under the "dp-lock-hbr3" tag:
#   journalctl -t dp-lock-hbr3
#
# The display is matched by its EDID, not by connector name, because the
# connector changes with port and plug order (DP-4 before, DP-2 after a reboot).

set -u

TAG=dp-lock-hbr3
LINK_SETTINGS="4 0x1e"          # lane count, link rate (0x1e = HBR3)
TIMEOUT=30                      # seconds to wait for the display to come up
DEBUGFS=/sys/kernel/debug/dri

# EDID match: manufacturer ID "APP" (bytes 8-9 = 06 10) and a monitor name
# descriptor containing this string.
EDID_NAME="${DP_LOCK_EDID_NAME:-StudioDisplay}"

log() { logger -t "$TAG" -- "$*"; echo "$TAG: $*" >&2; }

is_studio_display() {
    local edid=$1 mfg
    [[ -s $edid ]] || return 1
    mfg=$(od -An -tx1 -j8 -N2 "$edid" 2>/dev/null | tr -d ' \n')
    [[ $mfg == 0610 ]] || return 1
    # Monitor name lives in an 18-byte descriptor tagged 0xFC; a plain
    # string search over the 128-byte base block is enough to find it.
    head -c 128 "$edid" | tr -c '[:print:]' '\n' | grep -q -- "$EDID_NAME"
}

# Print "<card-minor> <connector>" for each enabled Studio Display connector.
find_connectors() {
    local dir name card
    for dir in /sys/class/drm/card*-DP-*; do
        [[ -d $dir ]] || continue
        [[ $(cat "$dir/status" 2>/dev/null) == connected ]] || continue
        [[ $(cat "$dir/enabled" 2>/dev/null) == enabled ]] || continue
        is_studio_display "$dir/edid" || continue
        name=${dir##*/}              # e.g. card1-DP-2
        card=${name%%-*}             # card1
        echo "${card#card} ${name#*-}"
    done
}

# debugfs is keyed by DRM minor (dri/1) on most kernels; newer ones may use
# the PCI address instead, so fall back to searching every dri directory.
link_settings_path() {
    local minor=$1 conn=$2 p
    p="$DEBUGFS/$minor/$conn/link_settings"
    [[ -w $p ]] && { echo "$p"; return 0; }
    for p in "$DEBUGFS"/*/"$conn"/link_settings; do
        [[ -w $p ]] && { echo "$p"; return 0; }
    done
    return 1
}

if [[ $EUID -ne 0 ]]; then
    log "must run as root"
    exit 1
fi

if [[ ! -d $DEBUGFS ]]; then
    mount -t debugfs none /sys/kernel/debug 2>/dev/null
    [[ -d $DEBUGFS ]] || { log "debugfs not available at $DEBUGFS"; exit 1; }
fi

deadline=$((SECONDS + TIMEOUT))
while :; do
    mapfile -t found < <(find_connectors)
    locked=0
    for entry in "${found[@]}"; do
        read -r minor conn <<<"$entry"
        if ! path=$(link_settings_path "$minor" "$conn"); then
            continue
        fi
        if echo "$LINK_SETTINGS" > "$path" 2>/dev/null; then
            log "locked $conn to 4 lanes @ HBR3"
            locked=1
        else
            log "failed to write '$LINK_SETTINGS' to $path"
        fi
    done
    ((locked)) && exit 0
    ((SECONDS >= deadline)) && break
    sleep 1
done

log "no enabled Studio Display connector found"
exit 0
