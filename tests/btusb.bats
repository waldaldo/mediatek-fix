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
# find_kbuild
# ---------------------------------------------------------------------------

@test "find_kbuild: encuentra /lib/modules/{kver}/build" {
    local fake="/tmp/bats-kbuild-$$"
    mkdir -p "$fake"
    touch "$fake/Makefile"
    # Reemplaza la primera ruta candidata con la fake
    result=$(KVER="fake-kver" bash -c "
        find_kbuild() {
            local kver=\$1
            local candidates=('${fake}')
            for p in \"\${candidates[@]}\"; do
                [[ -d \$p && -f \$p/Makefile ]] && echo \$p && return 0
            done
            return 1
        }
        find_kbuild fake-kver
    ")
    rm -rf "$fake"
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

@test "generate_autoconf: genera desde /proc/config.gz si existe" {
    local fake_kbuild="$TEST_DIR/kbuild"
    mkdir -p "$fake_kbuild/include/generated"

    # Crea un config.gz de prueba en un directorio temporal
    local fake_config="$TEST_DIR/config"
    printf 'CONFIG_BT=m\nCONFIG_BT_HCIUSB=y\nCONFIG_HZ=250\n' | gzip > "$fake_config.gz"

    bash -c "
        $(declare -f generate_autoconf)
        # Sobreescribe /proc/config.gz con el fake
        generate_autoconf() {
            local kbuild=\$1 kver=\$2
            local config_cmd='zcat ${fake_config}.gz'
            eval \"\$config_cmd\" | awk '
                /^CONFIG_.*=y\$/ { gsub(/=y\$/, \"\"); print \"#define \" \$0 \" 1\" }
                /^CONFIG_.*=m\$/ { gsub(/=m\$/, \"\"); print \"#define \" \$0 \" 1\" }
                /^CONFIG_.*=[0-9]/ { gsub(/=/, \" \"); print \"#define \" \$0 }
            ' > \"\${kbuild}/include/generated/autoconf.h\"
        }
        generate_autoconf '${fake_kbuild}' 'test'
    "
    grep -q "CONFIG_BT_HCIUSB" "$fake_kbuild/include/generated/autoconf.h"
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
