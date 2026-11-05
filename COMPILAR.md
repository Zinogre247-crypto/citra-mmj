# Compilar Citra MMJ 20240520 (APK arm64)

Estado: **código preparado, listo para lanzar la compilación en GitHub Actions**.
Todavía **no existe un APK compilado** — el primer intento lo hará la nube de GitHub.

---

## 1. Qué herramientas faltan (y por qué)

Estas son las que exige el propio proyecto (leídas de `src/android/build.gradle`
y `src/android/app/build.gradle`):

| Herramienta | Versión exacta | Para qué |
|---|---|---|
| **JDK 17** | 17 (Temurin) | Android Gradle Plugin 8.4.0 no arranca con menos |
| **Gradle** | **8.6** | el repo trae `gradle-wrapper.properties` pero **falta el script `gradlew`**, hay que usar Gradle del sistema |
| **Android SDK Platform** | **31** | `compileSdkVersion 31` / `targetSdkVersion 31` |
| **Android Build-Tools** | **34.0.0** | lo pide AGP 8.4 |
| **Android NDK** | **26.3.11579264** | fijado en `ndkVersion` |
| **CMake** | **3.22.1** | fijado en `externalNativeBuild` |
| **git** | cualquiera | la versión del APK sale de `git describe` |
| Recursos de máquina | ≥4 núcleos, ≥8 GB RAM, ~15 GB disco | Citra son cientos de archivos C++ y el `.cxx` intermedio pesa |

Además hay **34 dependencias** (Boost, Dynarmic, Crypto++, LibreSSL, Cubeb, Teakra,
libyuv, SoundTouch, fmt…) que se bajan como submódulos.

### Por qué Termux no sirve para compilar esto
El NDK de Android oficial solo existe para **x86_64** (Linux/macOS/Windows). Tu
Redmi 13C es **ARM64**: Termux no puede ejecutar el `clang` del NDK de forma nativa,
habría que emular x86_64 con qemu → compilación de varias horas por archivo. Termux
sí sirve para lo demás: descargar el APK, instalarlo con `adb` y probar MHXX.

👉 Por eso tu idea de **GitHub Actions** es la correcta: el runner `ubuntu-22.04` ya
tiene 4 núcleos, 16 GB de RAM y Linux x86_64. Es gratis en repos públicos (y 2000
min/mes en privados; un build de Citra tarda ~40–60 min).

---

## 2. Lo que ya arreglé en el código

1. **4 submódulos apuntaban a repositorios que Citra borró en 2024** (404):
   `ext-boost`, `ext-libressl-portable`, `ext-soundtouch` y `dynarmic-android`.
   - `boost` → `azahar-emu/ext-boost` (**commit idéntico** al original ✅)
   - `libressl` → `azahar-emu/ext-libressl-portable` (**commit idéntico** ✅)
   - `soundtouch` → `azahar-emu/soundtouch` (2.3.3, sin el commit original)
   - `dynarmic` → `GabiAle97/dynarmic-android` (fork de marzo 2022)
2. **Entrada duplicada** de `libyuv` en `.gitmodules` que rompía `git submodule init`: eliminada.
3. **Dynarmic validado**: el commit original `b6be02ea` no existe en ningún espejo
   público, pero comprobé con el compilador que `arm_dynarmic.cpp` y
   `arm_dynarmic_cp15.cpp` compilan **sin errores** contra el fork de 2022 (usa la
   misma API antigua `<dynarmic/A32/a32.h>`). Es el mejor sustituto disponible.
4. Añadido `scripts/prepare-sources.sh` (baja y fija todo automáticamente, probado
   de punta a punta: 185 MB de fuentes) y `.github/workflows/build-apk.yml`.

---

## 3. Pasos para compilar en GitHub (una sola vez)

```bash
# en tu PC o en Termux. El repo ya esta en la rama master y con los cambios commiteados.
cd citra-mmj-20240520
git remote add mio https://github.com/TU_USUARIO/citra-mmj.git
git push -u mio master
```

El nombre del repositorio de GitHub es libre (`citra-mmj`, `citra-mhxx`, etc.) y no
afecta en nada a la compilación. Lo único que importa es que la rama sea **`master`**
y que el workflow esté en la rama por defecto, o el botón *Run workflow* no aparecerá.

Luego en GitHub: pestaña **Actions → “Compilar APK” → Run workflow**.
Al terminar (~1 h), descarga el artefacto **`citra-mmj-debug-apk`**.

Instalación en el teléfono:
```bash
adb install -r citra-mmj-debug-apk/app-debug.apk
```
o copiando el `.apk` al teléfono y abriéndolo (permitir “instalar apps desconocidas”).

### Importante sobre el APK resultante
- Se instala como **`org.citra.emu.debug`**, es decir **al lado** de tu Citra actual.
  No reemplaza ni borra tu instalación `com.antutu.ABenchMark` ni tus partidas.
- Al tener otra firma, **no puede actualizar** la app original.
- **No hereda el truco Antutu** (esa variante se hace pasar por benchmark); el
  rendimiento puede ser algo distinto al de tu APK actual por ese motivo.
- Aun así, **haz copia de seguridad de tus partidas** antes de experimentar
  (`/Android/data/org.citra.emu/…` o la carpeta que uses).

---

## 4. Qué esperar del primer build

El primer intento puede fallar; lo normal es que dé errores de compilación en
puntos concretos (por el Dynarmic sustituido o por el SoundTouch más nuevo).
Si falla: descarga el artefacto `logs-de-compilacion` (o copia el error de la
pestaña Actions) y lo corregimos. **No toques aún ninguna opción de rendimiento**:
primero necesitamos una compilación reproducible que abra MHXX igual que la tuya.

Después, ya con build funcionando, el orden sensato de pruebas es:
1. Build sin cambios → comparar FPS con tu APK actual (misma zona: Hyper Astalos).
2. Solo entonces aplicar ajustes de código uno por uno, midiendo cada uno
   (por ejemplo: caché de shaders, precisión de texturas, hilos de Dynarmic,
   resolución de render, límites de CPU).
