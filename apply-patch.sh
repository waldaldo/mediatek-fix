#!/bin/bash
# apply-patch.sh — instalación manual del parche btusb.
# Uso: sudo ./apply-patch.sh
exec "$(dirname "${BASH_SOURCE[0]}")/install-btusb-patch.sh" "$@"
