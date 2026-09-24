#!/usr/bin/env bash
# Install the Studio Display flicker fix. Run with sudo from this directory.
set -euo pipefail
cd "$(dirname "$0")"
install -Dm755 dp-lock-hbr3.sh       /usr/local/bin/dp-lock-hbr3.sh
install -Dm644 dp-lock-hbr3.service  /etc/systemd/system/dp-lock-hbr3.service
install -Dm644 99-dp-lock-hbr3.rules /etc/udev/rules.d/99-dp-lock-hbr3.rules
systemctl daemon-reload
systemctl enable --now dp-lock-hbr3.service
udevadm control --reload-rules
journalctl -t dp-lock-hbr3 -n 5 --no-pager
