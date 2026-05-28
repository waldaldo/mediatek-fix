#!/bin/bash
# uninstall-btusb-patch.sh — restaura el módulo btusb original desde el backup.
# Uso: sudo ./uninstall-btusb-patch.sh

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: este script debe ejecutarse como root (sudo $0)."
    exit 1
fi

# Carga utilidades compartidas.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib-btusb.sh
source "${SCRIPT_DIR}/lib-btusb.sh"

KVER=$(uname -r)
DEST="$(btusb_dest "$KVER")"

echo "==> Buscando backup en ${DEST}..."

ORIG_EXT=""
for ext in "${BTUSB_EXTENSIONS[@]}"; do
    if [[ -f "${DEST}/btusb.${ext}.orig" ]]; then
        ORIG_EXT="$ext"
        break
    fi
done

if [[ -z "$ORIG_EXT" ]]; then
    echo "ERROR: No se encontró ningún backup (btusb.*.orig) en ${DEST}."
    echo "       El parche no fue instalado con este script, o el backup fue eliminado."
    exit 1
fi

echo "==> Restaurando btusb.${ORIG_EXT} desde backup..."
cp "${DEST}/btusb.${ORIG_EXT}.orig" "${DEST}/btusb.${ORIG_EXT}"
rm -f "${DEST}/btusb.${ORIG_EXT}.orig"

depmod -a "${KVER}"

echo "==> Recargando módulo btusb..."
if modprobe -r btusb 2>/dev/null; then
    modprobe btusb
else
    echo "    AVISO: El módulo btusb está en uso; el módulo original se activará tras reiniciar."
fi

echo "==> Reiniciando bluetooth..."
if ! restart_bluetooth; then
    echo "    AVISO: No se pudo reiniciar el servicio bluetooth. Verifica manualmente."
fi

echo "==> Módulo original restaurado para kernel ${KVER}."
