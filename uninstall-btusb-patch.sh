#!/bin/bash
# uninstall-btusb-patch.sh — restaura el módulo btusb original desde el backup.
# Uso: sudo ./uninstall-btusb-patch.sh

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: este script debe ejecutarse como root (sudo $0)."
    exit 1
fi

KVER=$(uname -r)
DEST="/lib/modules/${KVER}/kernel/drivers/bluetooth"

echo "==> Buscando backup en ${DEST}..."

ORIG_EXT=""
for ext in ko.zst ko.xz ko.gz ko; do
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
if command -v systemctl &>/dev/null; then
    systemctl restart bluetooth 2>/dev/null || true
elif command -v rc-service &>/dev/null; then
    rc-service bluetooth restart 2>/dev/null || true
elif command -v service &>/dev/null; then
    service bluetooth restart 2>/dev/null || true
fi

echo "==> Módulo original restaurado para kernel ${KVER}."
