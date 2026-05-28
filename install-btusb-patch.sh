#!/bin/bash
# install-btusb-patch.sh
# Compila e instala el módulo btusb parcheado para el kernel en ejecución.
# Compatible con cualquier distribución Linux.
#
#   Manual (desde el repo):  sudo ./apply-patch.sh
#                             sudo ./install-btusb-patch.sh
#   Hook de pacman:          /usr/local/bin/install-btusb-patch

set -euo pipefail

# Cuando se sourcea para tests (BTUSB_TESTING=1), las variables de entorno
# exportadas por el harness de tests no deben ser sobreescritas.
if [[ "${BTUSB_TESTING:-}" != "1" ]]; then
    KVER=$(uname -r)

    # Si el script está junto a btusb.c, usa ese directorio como fuente.
    # Si no, usa la ruta de instalación del sistema.
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [[ -f "${SCRIPT_DIR}/btusb.c" ]]; then
        SRC="${SCRIPT_DIR}"
    else
        SRC="/usr/local/src/btusb-patch"
    fi

    BUILD_DIR=$(mktemp -d /tmp/btusb-build.XXXXXX)
    trap 'rm -rf "$BUILD_DIR"' EXIT
fi

# Carga utilidades compartidas siempre (también en modo test).
# shellcheck source=lib-btusb.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-btusb.sh"

# ---------------------------------------------------------------------------
# Localiza el directorio de build del kernel en varias rutas estándar.
# Salida: ruta al directorio de headers del kernel, o vacío si no se encuentra.
# ---------------------------------------------------------------------------
find_kbuild() {
    local kver="$1"
    local candidates
    # KBUILD_CANDIDATES permite inyectar rutas alternativas en tests.
    # Si se provee desde el entorno,无声ly usa esas rutas sin auditoría.
    if [[ -v KBUILD_CANDIDATES && "${#KBUILD_CANDIDATES[@]}" -gt 0 ]]; then
        if [[ "${BTUSB_TESTING:-}" != "1" ]]; then
            echo "    INFO: usando KBUILD_CANDIDATES del entorno: ${KBUILD_CANDIDATES[*]}" >&2
        fi
        candidates=("${KBUILD_CANDIDATES[@]}")
    else
        candidates=(
            "/lib/modules/${kver}/build"        # Arch, openSUSE y mayoría de distros
            "/usr/src/linux-headers-${kver}"    # Debian / Ubuntu
            "/usr/src/kernels/${kver}"          # Fedora / RHEL / CentOS
            "/usr/src/linux-${kver}"            # Gentoo
        )
    fi
    local found=""
    for path in "${candidates[@]}"; do
        if [[ -d "$path" && -f "${path}/Makefile" ]]; then
            found="$path"
            break
        fi
    done
    if [[ -n "$found" ]]; then
        echo "$found"
        return 0
    fi
    echo "    paths checked: ${candidates[*]}" >&2
    return 1
}

# ---------------------------------------------------------------------------
# Sugiere el paquete de headers correcto según el gestor de paquetes presente.
# ---------------------------------------------------------------------------
suggest_headers_pkg() {
    local kver="$1"
    if command -v pacman &>/dev/null; then
        echo "el paquete *-headers correspondiente a tu kernel (ej: linux-headers)"
    elif command -v apt-get &>/dev/null; then
        echo "linux-headers-${kver}"
    elif command -v dnf &>/dev/null || command -v yum &>/dev/null; then
        echo "kernel-devel-${kver}"
    elif command -v zypper &>/dev/null; then
        echo "kernel-devel"
    elif command -v emerge &>/dev/null; then
        echo "sys-kernel/linux-headers"
    else
        echo "el paquete de headers del kernel de tu distribución"
    fi
}

# ---------------------------------------------------------------------------
# Construye la lista ordenada de URLs donde buscar los headers bluetooth.
# Empieza por el repo específico del sabor del kernel, termina en upstream.
# Exporta: FLAVOR, URL_CANDIDATES[]
# ---------------------------------------------------------------------------
build_url_candidates() {
    local kver="$1"
    local rc_tag
    rc_tag=$(echo "$kver" | sed -n 's/^\([0-9]*\.[0-9]*\)\.[0-9]*-\(rc[0-9]*\).*/v\1-\2/p')

    URL_CANDIDATES=()
    FLAVOR="generic"

    # --- Sabores conocidos: añaden su repo específico al frente de la lista ---

    if echo "$kver" | grep -qE '\-cachyos(-rc)?'; then
        FLAVOR="cachyos"
        local ctag
        [[ -n "$rc_tag" ]] && ctag="${rc_tag}-cachyos" \
            || ctag="v$(echo "$kver" | sed 's/^\([0-9]*\.[0-9]*\.[0-9]*\).*/\1/')-cachyos"
        URL_CANDIDATES+=("https://raw.githubusercontent.com/CachyOS/linux/${ctag}/drivers/bluetooth")

    elif echo "$kver" | grep -q '\-zen'; then
        FLAVOR="zen"
        URL_CANDIDATES+=("https://raw.githubusercontent.com/zen-kernel/zen-kernel/$(echo "$kver" | sed 's/\([0-9]*\.[0-9]*\.[0-9]*\)-\(zen[0-9]*\)-.*/v\1-\2/')/drivers/bluetooth")

    elif echo "$kver" | grep -q '\-lqx'; then
        FLAVOR="lqx"
        URL_CANDIDATES+=("https://raw.githubusercontent.com/zen-kernel/zen-kernel/$(echo "$kver" | sed 's/\([0-9]*\.[0-9]*\.[0-9]*\)-\(lqx[0-9]*\)-.*/v\1-\2/')/drivers/bluetooth")

    elif echo "$kver" | grep -q '\.hardened'; then
        FLAVOR="hardened"
        URL_CANDIDATES+=("https://raw.githubusercontent.com/anthraxx/linux-hardened/$(echo "$kver" | sed 's/\([0-9]*\.[0-9]*\.[0-9]*\)\.\(hardened[0-9]*\)-.*/v\1-\2/')/drivers/bluetooth")
    fi

    # --- Upstream siempre disponible como fallback ---

    # torvalds/linux: tagea vX.Y (sin patch level) o vX.Y-rcN para RCs
    local torvalds_tag="${rc_tag:-v$(echo "$kver" | sed 's/^\([0-9]*\.[0-9]*\)\..*/\1/')}"
    URL_CANDIDATES+=("https://raw.githubusercontent.com/torvalds/linux/${torvalds_tag}/drivers/bluetooth")

    # gregkh/linux: estable con patch level completo (vX.Y.Z)
    local gregkh_tag="${rc_tag:-v$(echo "$kver" | sed 's/^\([0-9]*\.[0-9]*\.[0-9]*\).*/\1/')}"
    URL_CANDIDATES+=("https://raw.githubusercontent.com/gregkh/linux/${gregkh_tag}/drivers/bluetooth")
}

# ---------------------------------------------------------------------------
# Descarga los cuatro headers internos del subsistema bluetooth.
# Prueba cada URL de URL_CANDIDATES en orden hasta encontrar una que funcione.
# ---------------------------------------------------------------------------
download_bt_headers() {
    local dest="$1"
    local -A results=()  # header → final path on success
    local pids=()

    download_one() {
        local header="$1" dest="$2" url
        local tmp
        tmp=$(mktemp "${dest}/${header}.XXXXXX")
        for url in "${URL_CANDIDATES[@]}"; do
            if curl -sSf --max-time 30 "${url}/${header}" -o "$tmp" 2>/dev/null; then
                mv "$tmp" "${dest}/${header}"
                return 0
            fi
            echo "       WARN: fallo ${header} <- ${url}" >&2
        done
        rm -f "$tmp"
        return 1
    }

    for header in btintel.h btbcm.h btrtl.h btmtk.h; do
        echo "    -> ${header}"
        download_one "$header" "$dest" &
        pids+=($!)
    done

    local failed=0
    for pid in "${pids[@]}"; do
        wait "$pid" || ((failed++))
    done

    if [[ $failed -gt 0 ]]; then
        echo "ERROR: falló la descarga de ${failed} header(s)."
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# Genera autoconf.h a partir de la configuración del kernel.
# Busca en /proc/config.gz, /boot/config-KVER y KBUILD/.config.
# ---------------------------------------------------------------------------
generate_autoconf() {
    local kbuild="$1" kver="$2"
    echo "==> Generando autoconf.h..."
    local cfg_file="" cfg_zcat=0
    if [[ -f /proc/config.gz ]]; then
        cfg_file="/proc/config.gz"
        cfg_zcat=1
    elif [[ -f "/boot/config-${kver}" ]]; then
        cfg_file="/boot/config-${kver}"
    elif [[ -f "${kbuild}/.config" ]]; then
        cfg_file="${kbuild}/.config"
    else
        echo "ERROR: No se encontró la configuración del kernel."
        echo "       Prueba: zcat /proc/config.gz, /boot/config-${kver} o ${kbuild}/.config"
        exit 1
    fi
    local out_dir="${kbuild}/include/generated"
    mkdir -p "$out_dir" || {
        echo "ERROR: No se puede crear ${out_dir}."
        echo "       Verifica los permisos del paquete de headers del kernel."
        exit 1
    }
    { [[ $cfg_zcat -eq 1 ]] && zcat "$cfg_file" || cat "$cfg_file"; } | awk '
        /^CONFIG_.*=y$/ { gsub(/=y$/, ""); print "#define " $0 " 1" }
        /^CONFIG_.*=m$/ { gsub(/=m$/, ""); print "#define " $0 " 1" }
        /^CONFIG_.*=[0-9]/ { gsub(/=/, " "); print "#define " $0 }
        /^CONFIG_.*=".*"/ { n=index($0,"="); print "#define " substr($0,1,n-1) " " substr($0,n+1) }
    ' > "${out_dir}/autoconf.h" || exit 1

    if [[ ! -s "${out_dir}/autoconf.h" ]]; then
        echo "ERROR: autoconf.h está vacío — ningún CONFIG_ reconocido en ${cfg_file}."
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# Detecta el compilador con el que fue construido el kernel.
# ---------------------------------------------------------------------------
detect_compiler() {
    local kbuild="$1"
    # Verifica que la palabra "clang" aparezca como compilador registrado,
    # no como substring de otro texto.
    if grep -q '\bclang\b' "${kbuild}/include/generated/compile.h" 2>/dev/null; then
        echo "clang"
    elif grep -q '\bclang\b' /proc/version 2>/dev/null; then
        echo "clang"
    else
        echo "gcc"
    fi
}

# ---------------------------------------------------------------------------
# Instala btusb.ko con la compresión correcta y hace backup del original.
# ---------------------------------------------------------------------------
install_module() {
    local ko_src="$1" dest="$2" kver="$3"
    local ext orig
    ext=$(detect_module_ext "$dest")
    orig="${dest}/btusb.${ext}.orig"

    if [[ ! -f "$orig" ]]; then
        if [[ -f "${dest}/btusb.${ext}" ]]; then
            cp "${dest}/btusb.${ext}" "$orig"
            echo "    Backup: ${orig}"
        else
            echo "    WARN: No existe ${dest}/btusb.${ext}; se omite backup (instalación nueva)."
        fi
    fi

    case "$ext" in
        ko.zst) zstd -f "$ko_src" -o "${dest}/btusb.ko.zst" ;;
        ko.xz)  xz -f -k "$ko_src" && mv "${ko_src}.xz" "${dest}/btusb.ko.xz" ;;
        ko.gz)  gzip -f -k "$ko_src" && mv "${ko_src}.gz" "${dest}/btusb.ko.gz" ;;
        ko)     cp "$ko_src" "${dest}/btusb.ko" ;;
    esac

    depmod -a "$kver"
}

# ===========================================================================
# Main
# ===========================================================================

main() {
    # --- Verificar root ---
    [[ $EUID -eq 0 ]] || { echo "ERROR: este script debe ejecutarse como root (sudo)."; exit 1; }

    # --- Localizar headers del kernel ---
    KBUILD=$(find_kbuild "$KVER") || {
        echo "ERROR: Headers del kernel no encontrados para ${KVER}."
        echo "       Instala: $(suggest_headers_pkg "$KVER")"
        exit 1
    }

    # --- Construir lista de URLs para los headers bluetooth ---
    build_url_candidates "$KVER"
    echo "==> Kernel: ${KVER} (sabor: ${FLAVOR})"
    echo "==> Headers: ${KBUILD}"
    echo "==> Fuente:  ${SRC}"

    # --- Verificar fuentes ---
    if [[ ! -f "${SRC}/btusb.c" || ! -f "${SRC}/compat.h" ]]; then
        echo "ERROR: Fuentes no encontradas en ${SRC}"
        echo "       Copia btusb.c y compat.h a ${SRC} o ejecuta desde el repositorio."
        exit 1
    fi

    # --- Generar autoconf.h si falta ---
    if [[ ! -f "${KBUILD}/include/generated/autoconf.h" ]]; then
        generate_autoconf "$KBUILD" "$KVER"
    fi

    # --- Preparar build temporal ---
    cp "${SRC}/btusb.c" "${BUILD_DIR}/"
    cp "${SRC}/compat.h" "${BUILD_DIR}/"

    # --- Descargar headers internos del subsistema bluetooth ---
    echo "==> Descargando headers bluetooth..."
    download_bt_headers "${BUILD_DIR}"

    # --- Crear Makefile con la ruta correcta de headers ---
    cat > "${BUILD_DIR}/Makefile" << EOF
obj-m := btusb.o
KDIR := ${KBUILD}
EXTRA_CFLAGS := -I\$(CURDIR) -include \$(CURDIR)/compat.h

all:
	\$(MAKE) -C \$(KDIR) M=\$(CURDIR) modules

clean:
	\$(MAKE) -C \$(KDIR) M=\$(CURDIR) clean
EOF

    # --- Detectar compilador y compilar ---
    KBUILD_CC=$(detect_compiler "$KBUILD")
    echo "==> Compilando con ${KBUILD_CC}..."
    if [[ "$KBUILD_CC" == "clang" ]]; then
        make -C "${BUILD_DIR}" LLVM=1 LLVM_IAS=1
    else
        make -C "${BUILD_DIR}" CC=gcc
    fi

    [[ ! -f "${BUILD_DIR}/btusb.ko" ]] && { echo "ERROR: La compilación falló."; exit 1; }

    # --- Instalar ---
    echo "==> Instalando btusb.ko..."
    install_module "${BUILD_DIR}/btusb.ko" "$(btusb_dest "$KVER")" "$KVER"

    # --- Recargar módulo btusb ---
    echo "==> Recargando módulo btusb..."
    if modprobe -r btusb 2>/dev/null; then
        modprobe btusb
    else
        echo "    AVISO: El módulo btusb está en uso; el nuevo módulo se activará tras reiniciar."
    fi

    # --- Reiniciar servicio bluetooth ---
    echo "==> Reiniciando bluetooth..."
    if ! restart_bluetooth; then
        echo "    AVISO: No se pudo reiniciar el servicio bluetooth. Verifica manualmente."
    fi

    echo "==> Listo."
}

# Permite hacer `source install-btusb-patch.sh` en tests sin ejecutar main.
[[ "${BTUSB_TESTING:-}" == "1" ]] || main
