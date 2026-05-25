#!/bin/bash
# apply-patch.sh — instala el parche btusb para 04ca:3807 (MediaTek MT7921).
# Uso: sudo ./apply-patch.sh

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: este script debe ejecutarse como root."
    echo "       Uso: sudo $0"
    exit 1
fi

exec "$(dirname "${BASH_SOURCE[0]}")/install-btusb-patch.sh" "$@"
