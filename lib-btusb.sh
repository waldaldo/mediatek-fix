#!/bin/bash
# lib-btusb.sh — funciones y constantes compartidas entre install y uninstall.
# No ejecuta main; fuente este archivo antes de llamar a cualquier función.

# ---------------------------------------------------------------------------
# Constantes
# ---------------------------------------------------------------------------
# Orden de prioridad: mayor primero (zstd > xz > gz > sin comprimir).
readonly BTUSB_EXTENSIONS=(ko.zst ko.xz ko.gz ko)

# Ruta donde vive el módulo btusb en /lib/modules.
btusb_dest() {
    local kver="${1:-$(uname -r)}"
    echo "/lib/modules/${kver}/kernel/drivers/bluetooth"
}

# ---------------------------------------------------------------------------
# Detecta la extensión del módulo btusb instalado (zst, xz, gz, o sin comprimir).
# ---------------------------------------------------------------------------
detect_module_ext() {
    local dest="${1:?usage: detect_module_ext <dest_dir>}"
    for ext in "${BTUSB_EXTENSIONS[@]}"; do
        [[ -f "${dest}/btusb.${ext}" ]] && echo "$ext" && return 0
    done
    echo "ko"
}

# ---------------------------------------------------------------------------
# Reinicia el servicio bluetooth usando el init system disponible.
# Devuelve 0 si al menos un intento tuvo éxito, 1 si todos fallaron.
# ---------------------------------------------------------------------------
restart_bluetooth() {
    local ret=1
    if command -v systemctl &>/dev/null; then
        systemctl restart bluetooth 2>/dev/null && ret=0
    elif command -v rc-service &>/dev/null; then
        rc-service bluetooth restart 2>/dev/null && ret=0
    elif command -v service &>/dev/null; then
        service bluetooth restart 2>/dev/null && ret=0
    fi
    return "$ret"
}
