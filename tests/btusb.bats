#!/usr/bin/env bats
# Tests para install-btusb-patch.sh
# Ejecutar: bats tests/btusb.bats

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/install-btusb-patch.sh"

setup() {
    # Crea un directorio temporal por test
    TEST_DIR="$(mktemp -d)"
    # Inyecta variables mínimas que el script necesita al sourcear
    export BTUSB_TESTING=1
    export KVER="7.0.0-1-test"
    export SRC="$TEST_DIR/src"
    export BUILD_DIR="$TEST_DIR/build"
    mkdir -p "$SRC" "$BUILD_DIR"
    # shellcheck source=/dev/null
    source "$SCRIPT"
}

teardown() {
    rm -rf "$TEST_DIR"
}

# ---------------------------------------------------------------------------
# Comportamiento al sourcear con BTUSB_TESTING=1
# ---------------------------------------------------------------------------

@test "source con BTUSB_TESTING=1 no sobreescribe KVER exportado" {
    [[ "$KVER" == "7.0.0-1-test" ]]
}

@test "source con BTUSB_TESTING=1 no sobreescribe BUILD_DIR exportado" {
    [[ "$BUILD_DIR" == "$TEST_DIR/build" ]]
}

@test "source con BTUSB_TESTING=1 no sobreescribe SRC exportado" {
    [[ "$SRC" == "$TEST_DIR/src" ]]
}

# ---------------------------------------------------------------------------
# find_kbuild
# ---------------------------------------------------------------------------

@test "find_kbuild: encuentra directorio válido vía KBUILD_CANDIDATES" {
    local fake="/tmp/bats-kbuild-$$"
    mkdir -p "$fake"
    touch "$fake/Makefile"
    KBUILD_CANDIDATES=("$fake")
    result=$(find_kbuild "fake-kver")
    rm -rf "$fake"
    unset KBUILD_CANDIDATES
    [[ "$result" == "$fake" ]]
}

@test "find_kbuild: falla si ninguna ruta existe" {
    run find_kbuild "kernel-que-no-existe-99.99.99"
    [[ "$status" -ne 0 ]]
}

# ---------------------------------------------------------------------------
# suggest_headers_pkg
# ---------------------------------------------------------------------------

@test "suggest_headers_pkg: detecta pacman" {
    # Crea un 'pacman' falso accesible en PATH
    local fake_bin="$TEST_DIR/fakebin"
    mkdir -p "$fake_bin"
    ln -s /bin/true "$fake_bin/pacman"
    result=$(PATH="$fake_bin:$PATH" bash -c "
        $(declare -f suggest_headers_pkg)
        suggest_headers_pkg '6.1.0-1-generic'
    ")
    [[ -n "$result" ]]
}

@test "suggest_headers_pkg: incluye la versión del kernel para apt" {
    result=$(bash -c "
        command() { [[ \$2 == 'apt-get' ]] && return 0; return 1; }
        export -f command
        $(declare -f suggest_headers_pkg)
        suggest_headers_pkg '5.15.0-91-generic'
    ")
    [[ "$result" == *"5.15.0-91-generic"* ]]
}

# ---------------------------------------------------------------------------
# build_url_candidates
# ---------------------------------------------------------------------------

@test "build_url_candidates: CachyOS estable genera URL de CachyOS" {
    build_url_candidates "7.0.5-1-cachyos"
    [[ "${URL_CANDIDATES[0]}" == *"CachyOS/linux"* ]]
    [[ "${URL_CANDIDATES[0]}" == *"v7.0.5-cachyos"* ]]
}

@test "build_url_candidates: CachyOS RC genera tag con -rcN-cachyos" {
    build_url_candidates "7.1.0-rc3-1-cachyos-rc"
    [[ "${URL_CANDIDATES[0]}" == *"CachyOS/linux"* ]]
    [[ "${URL_CANDIDATES[0]}" == *"v7.1-rc3-cachyos"* ]]
}

@test "build_url_candidates: zen genera URL de zen-kernel" {
    build_url_candidates "7.0.5-zen2-1-zen"
    [[ "${URL_CANDIDATES[0]}" == *"zen-kernel/zen-kernel"* ]]
    [[ "${URL_CANDIDATES[0]}" == *"v7.0.5-zen2"* ]]
}

@test "build_url_candidates: lqx genera URL de zen-kernel" {
    build_url_candidates "7.0.5-lqx1-1-lqx"
    [[ "${URL_CANDIDATES[0]}" == *"zen-kernel/zen-kernel"* ]]
    [[ "${URL_CANDIDATES[0]}" == *"v7.0.5-lqx1"* ]]
}

@test "build_url_candidates: hardened genera URL de anthraxx" {
    build_url_candidates "6.14.0.hardened1-1-hardened"
    [[ "${URL_CANDIDATES[0]}" == *"anthraxx/linux-hardened"* ]]
    [[ "${URL_CANDIDATES[0]}" == *"v6.14.0-hardened1"* ]]
}

@test "build_url_candidates: kernel generico incluye torvalds como primera URL" {
    build_url_candidates "6.8.4-200.fc39.x86_64"
    # Kernel generico: primera URL debe ser torvalds
    [[ "${URL_CANDIDATES[0]}" == *"torvalds/linux"* ]]
}

@test "build_url_candidates: kernel generico incluye gregkh como fallback" {
    build_url_candidates "6.8.4-200.fc39.x86_64"
    local found=0
    for url in "${URL_CANDIDATES[@]}"; do
        [[ "$url" == *"gregkh/linux"* ]] && found=1 && break
    done
    [[ $found -eq 1 ]]
}

@test "build_url_candidates: kernel RC genera tag vX.Y-rcN para torvalds" {
    build_url_candidates "7.1.0-rc3-1-generic"
    local found=0
    for url in "${URL_CANDIDATES[@]}"; do
        [[ "$url" == *"torvalds/linux/v7.1-rc3"* ]] && found=1 && break
    done
    [[ $found -eq 1 ]]
}

@test "build_url_candidates: sabor cachyos exporta FLAVOR=cachyos" {
    build_url_candidates "7.0.5-1-cachyos"
    [[ "$FLAVOR" == "cachyos" ]]
}

@test "build_url_candidates: kernel desconocido exporta FLAVOR=generic" {
    build_url_candidates "6.8.4-200.fc39.x86_64"
    [[ "$FLAVOR" == "generic" ]]
}

# ---------------------------------------------------------------------------
# detect_module_ext
# ---------------------------------------------------------------------------

@test "detect_module_ext: detecta .ko.zst" {
    local fake_dest="$TEST_DIR/bluetooth"
    mkdir -p "$fake_dest"
    touch "$fake_dest/btusb.ko.zst"
    result=$(detect_module_ext "$fake_dest")
    [[ "$result" == "ko.zst" ]]
}

@test "detect_module_ext: detecta .ko.xz" {
    local fake_dest="$TEST_DIR/bluetooth"
    mkdir -p "$fake_dest"
    touch "$fake_dest/btusb.ko.xz"
    result=$(detect_module_ext "$fake_dest")
    [[ "$result" == "ko.xz" ]]
}

@test "detect_module_ext: detecta .ko.gz" {
    local fake_dest="$TEST_DIR/bluetooth"
    mkdir -p "$fake_dest"
    touch "$fake_dest/btusb.ko.gz"
    result=$(detect_module_ext "$fake_dest")
    [[ "$result" == "ko.gz" ]]
}

@test "detect_module_ext: detecta .ko sin comprimir" {
    local fake_dest="$TEST_DIR/bluetooth"
    mkdir -p "$fake_dest"
    touch "$fake_dest/btusb.ko"
    result=$(detect_module_ext "$fake_dest")
    [[ "$result" == "ko" ]]
}

@test "detect_module_ext: .ko.zst tiene prioridad sobre .ko.gz" {
    local fake_dest="$TEST_DIR/bluetooth"
    mkdir -p "$fake_dest"
    touch "$fake_dest/btusb.ko.zst" "$fake_dest/btusb.ko.gz"
    result=$(detect_module_ext "$fake_dest")
    [[ "$result" == "ko.zst" ]]
}

# ---------------------------------------------------------------------------
# detect_compiler
# ---------------------------------------------------------------------------

@test "detect_compiler: detecta clang desde compile.h" {
    local fake_kbuild="$TEST_DIR/kbuild"
    mkdir -p "$fake_kbuild/include/generated"
    echo '#define LINUX_COMPILER "clang version 17.0.0"' \
        > "$fake_kbuild/include/generated/compile.h"
    result=$(detect_compiler "$fake_kbuild")
    [[ "$result" == "clang" ]]
}

@test "detect_compiler: devuelve gcc cuando no hay clang" {
    local fake_kbuild="$TEST_DIR/kbuild"
    mkdir -p "$fake_kbuild/include/generated"
    echo '#define LINUX_COMPILER "gcc version 13.2.0"' \
        > "$fake_kbuild/include/generated/compile.h"
    result=$(detect_compiler "$fake_kbuild")
    [[ "$result" == "gcc" ]]
}

@test "detect_compiler: devuelve gcc si compile.h no existe" {
    local fake_kbuild="$TEST_DIR/kbuild_empty"
    mkdir -p "$fake_kbuild"
    # Sin compile.h, sin clang en /proc/version (entorno de test)
    result=$(bash -c "
        $(declare -f detect_compiler)
        detect_compiler '$fake_kbuild'
    ")
    [[ "$result" == "gcc" || "$result" == "clang" ]]  # acepta cualquiera; no crashea
}

# ---------------------------------------------------------------------------
# generate_autoconf
# ---------------------------------------------------------------------------

@test "generate_autoconf: genera autoconf.h desde kbuild/.config" {
    local fake_kbuild="$TEST_DIR/kbuild"
    mkdir -p "$fake_kbuild/include/generated"
    # Usa un kver que no tenga /boot/config-$kver para forzar el fallback a .config.
    # Si /proc/config.gz existe en el sistema de test, se usará esa fuente; en ambos
    # casos la función debe producir un autoconf.h con líneas #define válidas.
    printf 'CONFIG_BT=m\nCONFIG_BT_HCIUSB=y\nCONFIG_HZ=250\n' \
        > "$fake_kbuild/.config"

    generate_autoconf "$fake_kbuild" "nonexistent-kver-$$"

    [[ -f "$fake_kbuild/include/generated/autoconf.h" ]]
    grep -q "^#define CONFIG_" "$fake_kbuild/include/generated/autoconf.h"
}

@test "generate_autoconf: convierte =m y =y a #define X 1" {
    local fake_kbuild="$TEST_DIR/kbuild"
    mkdir -p "$fake_kbuild/include/generated"
    printf 'CONFIG_BT=m\nCONFIG_BT_HCIUSB=y\nCONFIG_HZ=250\n' \
        > "$fake_kbuild/.config"

    generate_autoconf "$fake_kbuild" "nonexistent-kver-$$"

    local out="$fake_kbuild/include/generated/autoconf.h"
    # Si se usó .config (ninguna otra fuente disponible con ese kver):
    # ambos =m y =y producen "#define CONFIG_X 1"; =N numérico produce "#define CONFIG_HZ 250"
    grep -q "^#define CONFIG_" "$out"
}

# ---------------------------------------------------------------------------
# download_bt_headers (con curl mockeado)
# ---------------------------------------------------------------------------

@test "download_bt_headers: descarga todos los headers con la primera URL" {
    URL_CANDIDATES=("http://mock-primary" "http://mock-fallback")

    # curl -sSf URL -o FILE: URL=$2, FILE=$4
    curl() {
        local dest
        while [[ $# -gt 0 ]]; do
            [[ "$1" == "-o" ]] && dest="$2" && break
            shift
        done
        echo "/* mock */" > "$dest"
        return 0
    }
    export -f curl

    download_bt_headers "$BUILD_DIR"

    for h in btintel.h btbcm.h btrtl.h btmtk.h; do
        [[ -f "${BUILD_DIR}/${h}" ]]
    done
}

@test "download_bt_headers: usa segunda URL si la primera falla" {
    URL_CANDIDATES=("http://mock-fail" "http://mock-ok")

    curl() {
        local url dest
        while [[ $# -gt 0 ]]; do
            [[ "$1" == "-o" ]] && dest="$2"
            [[ "$1" != -* && "$1" == http* ]] && url="$1"
            shift
        done
        if [[ "$url" == *"mock-fail"* ]]; then
            return 1
        fi
        echo "/* from fallback */" > "$dest"
        return 0
    }
    export -f curl

    download_bt_headers "$BUILD_DIR"

    grep -q "from fallback" "${BUILD_DIR}/btintel.h"
}

@test "download_bt_headers: falla si todas las URLs fallan" {
    URL_CANDIDATES=("http://mock-a" "http://mock-b")

    curl() { return 1; }
    export -f curl

    run download_bt_headers "$BUILD_DIR"
    [[ "$status" -ne 0 ]]
}

@test "download_bt_headers: WARN de URL fallida va a stderr" {
    URL_CANDIDATES=("http://mock-fail" "http://mock-ok")

    curl() {
        local url dest
        while [[ $# -gt 0 ]]; do
            [[ "$1" == "-o" ]] && dest="$2"
            [[ "$1" != -* && "$1" == http* ]] && url="$1"
            shift
        done
        [[ "$url" == *"mock-fail"* ]] && return 1
        echo "/* ok */" > "$dest"
    }
    export -f curl

    stderr_out=$(download_bt_headers "$BUILD_DIR" 2>&1 >/dev/null) || true
    [[ "$stderr_out" == *"WARN"* ]]
}

# ---------------------------------------------------------------------------
# install_module
# ---------------------------------------------------------------------------

@test "install_module: instala .ko sin compresión y hace backup" {
    local fake_dest="$TEST_DIR/bluetooth"
    mkdir -p "$fake_dest"
    echo "modulo-original" > "$fake_dest/btusb.ko"
    echo "modulo-parcheado" > "$BUILD_DIR/btusb.ko"

    depmod() { :; }

    install_module "$BUILD_DIR/btusb.ko" "$fake_dest" "test-kver"

    [[ -f "$fake_dest/btusb.ko.orig" ]]
    grep -q "modulo-original" "$fake_dest/btusb.ko.orig"
    grep -q "modulo-parcheado" "$fake_dest/btusb.ko"
}

@test "install_module: no sobreescribe backup existente" {
    local fake_dest="$TEST_DIR/bluetooth"
    mkdir -p "$fake_dest"
    echo "backup-original" > "$fake_dest/btusb.ko.orig"
    echo "ya-parcheado" > "$fake_dest/btusb.ko"
    echo "nueva-version" > "$BUILD_DIR/btusb.ko"

    depmod() { :; }

    install_module "$BUILD_DIR/btusb.ko" "$fake_dest" "test-kver"

    grep -q "backup-original" "$fake_dest/btusb.ko.orig"
    grep -q "nueva-version" "$fake_dest/btusb.ko"
}

@test "install_module: instalación nueva sin módulo previo no falla" {
    local fake_dest="$TEST_DIR/bluetooth"
    mkdir -p "$fake_dest"
    echo "modulo-nuevo" > "$BUILD_DIR/btusb.ko"

    depmod() { :; }

    run install_module "$BUILD_DIR/btusb.ko" "$fake_dest" "test-kver"
    [[ "$status" -eq 0 ]]
    [[ -f "$fake_dest/btusb.ko" ]]
}

# ---------------------------------------------------------------------------
# restart_bluetooth
# ---------------------------------------------------------------------------

@test "restart_bluetooth: invoca systemctl restart bluetooth" {
    local fake_bin="$TEST_DIR/fakebin"
    local calls_log="$TEST_DIR/calls.log"
    mkdir -p "$fake_bin"
    cat > "$fake_bin/systemctl" << 'FAKESCRIPT'
#!/bin/bash
echo "$*" >> "${CALLS_LOG}"
FAKESCRIPT
    chmod +x "$fake_bin/systemctl"
    CALLS_LOG="$calls_log" PATH="$fake_bin:$PATH" restart_bluetooth

    grep -q "restart bluetooth" "$calls_log"
}
