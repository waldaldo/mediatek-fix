#!/bin/bash
# install-btusb-patch.sh
# Compila e instala el módulo btusb parcheado para el kernel actual.
# Se ejecuta automáticamente via pacman hook al actualizar los headers del kernel.

set -euo pipefail

KVER=$(uname -r)
KBUILD="/lib/modules/${KVER}/build"
SRC="/usr/local/src/btusb-patch"
BUILD_DIR=$(mktemp -d /tmp/btusb-build.XXXXXX)
trap 'rm -rf "$BUILD_DIR"' EXIT

# ---------------------------------------------------------------------------
# Detectar sabor del kernel, tag del repositorio y URL base de headers BT.
# Exporta: FLAVOR, HEADERS_PKG, KERNEL_TAG, BASE_URL, FALLBACK_URL
# ---------------------------------------------------------------------------
detect_kernel() {
    local kver="$1"
    local base
    base=$(echo "$kver" | sed 's/^\([0-9]*\.[0-9]*\.[0-9]*\).*/\1/')

    if echo "$kver" | grep -q '\-zen'; then
        FLAVOR="zen"
        HEADERS_PKG="linux-zen-headers"
        KERNEL_TAG=$(echo "$kver" | sed 's/\([0-9]*\.[0-9]*\.[0-9]*\)-\(zen[0-9]*\)-.*/v\1-\2/')
        BASE_URL="https://raw.githubusercontent.com/zen-kernel/zen-kernel/${KERNEL_TAG}/drivers/bluetooth"
        FALLBACK_URL="https://raw.githubusercontent.com/torvalds/linux/v${base}/drivers/bluetooth"

    elif echo "$kver" | grep -q '\-lqx'; then
        FLAVOR="lqx"
        HEADERS_PKG="linux-lqx-headers"
        KERNEL_TAG=$(echo "$kver" | sed 's/\([0-9]*\.[0-9]*\.[0-9]*\)-\(lqx[0-9]*\)-.*/v\1-\2/')
        # lqx comparte repo con zen-kernel
        BASE_URL="https://raw.githubusercontent.com/zen-kernel/zen-kernel/${KERNEL_TAG}/drivers/bluetooth"
        FALLBACK_URL="https://raw.githubusercontent.com/gregkh/linux/v${base}/drivers/bluetooth"

    elif echo "$kver" | grep -q '\.hardened'; then
        FLAVOR="hardened"
        HEADERS_PKG="linux-hardened-headers"
        # uname: 6.14.0.hardened1-1-hardened → tag GitHub: v6.14.0-hardened1
        KERNEL_TAG=$(echo "$kver" | sed 's/\([0-9]*\.[0-9]*\.[0-9]*\)\.\(hardened[0-9]*\)-.*/v\1-\2/')
        BASE_URL="https://raw.githubusercontent.com/anthraxx/linux-hardened/${KERNEL_TAG}/drivers/bluetooth"
        FALLBACK_URL="https://raw.githubusercontent.com/gregkh/linux/v${base}/drivers/bluetooth"

    elif echo "$kver" | grep -q '\-lts'; then
        FLAVOR="lts"
        HEADERS_PKG="linux-lts-headers"
        KERNEL_TAG="v${base}"
        BASE_URL="https://raw.githubusercontent.com/gregkh/linux/${KERNEL_TAG}/drivers/bluetooth"
        FALLBACK_URL="$BASE_URL"

    elif echo "$kver" | grep -q '\-rt'; then
        FLAVOR="rt"
        HEADERS_PKG="linux-rt-headers"
        KERNEL_TAG="v$(echo "$kver" | sed 's/\([0-9]*\.[0-9]*\.[0-9]*\)_.*/\1/')"
        BASE_URL="https://raw.githubusercontent.com/gregkh/linux/${KERNEL_TAG}/drivers/bluetooth"
        FALLBACK_URL="$BASE_URL"

    else
        FLAVOR="arch"
        HEADERS_PKG="linux-headers"
        KERNEL_TAG="v${base}"
        BASE_URL="https://raw.githubusercontent.com/gregkh/linux/${KERNEL_TAG}/drivers/bluetooth"
        FALLBACK_URL="$BASE_URL"
    fi
}

# Descarga los cuatro headers internos del subsistema bluetooth.
# Usa FALLBACK_URL si el primario falla (solo si son distintos).
download_bt_headers() {
    local dest="$1"
    for header in btintel.h btbcm.h btrtl.h btmtk.h; do
        echo "    -> ${header}"
        if ! curl -sSf "${BASE_URL}/${header}" -o "${dest}/${header}" 2>/dev/null; then
            if [[ "$FALLBACK_URL" != "$BASE_URL" ]]; then
                echo "       WARN: fallo ${BASE_URL}, usando fallback ${FALLBACK_URL}..."
                curl -sSf "${FALLBACK_URL}/${header}" -o "${dest}/${header}" || {
                    echo "ERROR: No se pudo descargar ${header}"
                    exit 1
                }
            else
                echo "ERROR: No se pudo descargar ${header} desde ${BASE_URL}"
                exit 1
            fi
        fi
    done
}

# --- Detectar kernel ---
detect_kernel "$KVER"
echo "==> Compilando btusb parcheado para kernel ${KVER} (sabor: ${FLAVOR}, tag: ${KERNEL_TAG})"

# --- Verificar headers del kernel ---
if [[ ! -d "$KBUILD" ]]; then
    echo "ERROR: Headers del kernel no encontrados en $KBUILD"
    echo "       Instala ${HEADERS_PKG} antes de continuar."
    exit 1
fi

# --- Generar autoconf.h si falta ---
if [[ ! -f "${KBUILD}/include/generated/autoconf.h" ]]; then
    echo "==> Generando autoconf.h desde /proc/config.gz..."
    if [[ ! -f /proc/config.gz ]]; then
        echo "ERROR: /proc/config.gz no disponible."
        exit 1
    fi
    zcat /proc/config.gz | awk '
        /^CONFIG_.*=y$/ { gsub(/=y$/, ""); print "#define " $0 " 1" }
        /^CONFIG_.*=m$/ { gsub(/=m$/, ""); print "#define " $0 " 1" }
        /^CONFIG_.*=[0-9]/ { gsub(/=/, " "); print "#define " $0 }
        /^CONFIG_.*=".*"/ { n=index($0,"="); print "#define " substr($0,1,n-1) " " substr($0,n+1) }
    ' > "${KBUILD}/include/generated/autoconf.h"
fi

# --- Copiar fuentes al directorio de build temporal ---
cp "${SRC}/btusb.c" "${BUILD_DIR}/"
cp "${SRC}/compat.h" "${BUILD_DIR}/"

# --- Descargar headers internos del subsistema bluetooth ---
echo "==> Descargando headers bluetooth desde ${FLAVOR} ${KERNEL_TAG}..."
download_bt_headers "${BUILD_DIR}"

# --- Crear Makefile ---
cat > "${BUILD_DIR}/Makefile" << 'EOF'
obj-m := btusb.o
KDIR := /lib/modules/$(shell uname -r)/build
EXTRA_CFLAGS := -I$(PWD) -include $(PWD)/compat.h

all:
	$(MAKE) -C $(KDIR) M=$(PWD) modules

clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean
EOF

# --- Compilar ---
echo "==> Compilando..."
make -C "${BUILD_DIR}" 2>&1

if [[ ! -f "${BUILD_DIR}/btusb.ko" ]]; then
    echo "ERROR: La compilación falló, btusb.ko no generado."
    exit 1
fi

# --- Instalar ---
echo "==> Instalando btusb.ko..."
DEST="/lib/modules/${KVER}/kernel/drivers/bluetooth"

# Hacer backup del módulo original (solo la primera vez)
if [[ ! -f "${DEST}/btusb.ko.zst.orig" ]]; then
    cp "${DEST}/btusb.ko.zst" "${DEST}/btusb.ko.zst.orig"
    echo "    Backup guardado en btusb.ko.zst.orig"
fi

zstd -f "${BUILD_DIR}/btusb.ko" -o "${DEST}/btusb.ko.zst"
depmod -a "${KVER}"

echo "==> Listo. Reinicia el servicio bluetooth para aplicar los cambios:"
echo "    systemctl restart bluetooth"
