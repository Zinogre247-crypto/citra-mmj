#!/usr/bin/env bash
# Prepara el arbol de Citra MMJ 20240520 para compilar.
#
# Problema: 4 de los 17 submodulos del repo original apuntan a repositorios
# que Citra borro en 2024 (citra-emu/ext-boost, citra-emu/dynarmic-android,
# citra-emu/ext-soundtouch, citra-emu/ext-libressl-portable).
# Este script los reapunta a espejos vivos y hace el checkout de submodulos.
#
# Uso:  bash scripts/prepare-sources.sh
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
GM=.gitmodules

log() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }

# --- 1. Reapuntar los submodulos muertos a espejos vivos -------------------
log "Reapuntando submodulos a espejos vivos"

# boost: mismo commit exacto que pedia el original (36603a1e)
git config -f $GM submodule.boost.url https://github.com/azahar-emu/ext-boost.git

# libressl: mismo commit exacto que pedia el original (7d01cb01)
git config -f $GM submodule.libressl.url https://github.com/azahar-emu/ext-libressl-portable.git

# soundtouch: el commit original (060181ea) ya no existe en ningun espejo;
# se usa 2.3.3 (e83424d5, marzo 2024, misma epoca).
git config -f $GM submodule.soundtouch.url https://github.com/azahar-emu/soundtouch.git
SOUNDTOUCH_SHA=e83424d5928ab8513d2d082779c275765dee31b9

# dynarmic: el commit original (b6be02ea) no existe en ningun espejo publico.
# Se usa el fork de 2022 que conserva la API antigua (<dynarmic/A32/a32.h>,
# la que este Citra incluye). Es el sustituto mas cercano disponible.
git config -f $GM submodule.dynarmic.url https://github.com/GabiAle97/dynarmic-android.git
DYNARMIC_SHA=75faabb30c441af08244b9bfa0a82269ae8d9942

# Entrada duplicada/rota que rompe `git submodule init`
git config -f $GM --remove-section submodule.externals/libyuv 2>/dev/null || true
# Nombre con barra: git la guarda como [submodule "externals/libyuv"]
sed -i '/^\[submodule "externals\/libyuv"\]/,+2d' $GM 2>/dev/null || true

git submodule sync --recursive >/dev/null

# --- 2. Clonar todos los submodulos menos los dos con commit no disponible -
log "Clonando submodulos (excepto dynarmic y soundtouch)"
mapfile -t PATHS < <(git config -f $GM --get-regexp 'submodule\..*\.path' | awk '{print $2}')
KEEP=()
for p in "${PATHS[@]}"; do
    case "$p" in
        externals/dynarmic|externals/soundtouch) ;;
        *) KEEP+=("$p") ;;
    esac
done
if [ ${#KEEP[@]} -gt 0 ]; then
    git submodule update --init --recursive --depth 1 --jobs 4 -- "${KEEP[@]}" || true
fi

# --- 3. Fijar a mano los dos submodulos con commit propio ------------------
pin_submodule() {
    local path="$1" url="$2" sha="$3"
    log "Fijando $path @ ${sha:0:8}"
    rm -rf "$path"
    git clone --quiet "$url" "$path"
    git -C "$path" checkout --quiet "$sha"
    git -C "$path" submodule update --init --depth 1 --recursive --jobs 4 || true
    git update-index --add --cacheinfo "160000,$sha,$path"
}

pin_submodule externals/dynarmic   https://github.com/GabiAle97/dynarmic-android.git "$DYNARMIC_SHA"
pin_submodule externals/soundtouch https://github.com/azahar-emu/soundtouch.git        "$SOUNDTOUCH_SHA"

# --- 4. Verificacion rapida ------------------------------------------------
log "Verificando"
fail=0
check() { [ -e "$1" ] && echo "  ok   $1" || { echo "  FALTA $1"; fail=1; }; }
check externals/dynarmic/include/dynarmic/A32/a32.h
check externals/dynarmic/src/CMakeLists.txt
check externals/soundtouch/CMakeLists.txt
check externals/boost/boost/icl/interval_set.hpp
check externals/fmt/include/fmt/format.h
check externals/cryptopp/cryptopp/cryptlib.cpp
check externals/libressl/CMakeLists.txt
check externals/cubeb/CMakeLists.txt
check externals/libyuv/CMakeLists.txt
check externals/teakra/CMakeLists.txt
check externals/nihstro/include
check externals/enet/include
check externals/inih/inih/ini.h
check externals/catch/single_include

if [ "$fail" -ne 0 ]; then
    echo "ERROR: faltan fuentes de dependencias (ver arriba)."; exit 1
fi
log "Fuentes listas en $ROOT"
