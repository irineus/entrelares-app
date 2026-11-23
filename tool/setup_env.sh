#!/usr/bin/env bash
# tool/setup_env.sh — bootstrap idempotente do ambiente de build do Entrelares (Flutter) (Linux).
#
# Instala/garante: JDK 17, FVM, Flutter 3.50.1 (via .fvmrc), Android SDK
# (cmdline-tools, platform-tools, platforms;android-36, build-tools;36.0.0,
# NDK 28.2.13676358 — versões que o Flutter 3.50.1 declara em FlutterExtension.kt).
# Escreve tool/env (source-ável) com ANDROID_HOME/JAVA_HOME/PATH e termina com
# `fvm flutter doctor`, falhando com mensagem clara se algo essencial faltar.
#
# Uso:
#   bash tool/setup_env.sh
#   source tool/env
#
# Em sessões de nuvem com rede restrita:
#   - Se o clone git do Flutter (github.com) for bloqueado, o script cai para o
#     tarball OFICIAL de storage.googleapis.com (mesmo canal de release — não é mirror).
#   - Se dl.google.com (Android SDK) for bloqueado, o script PARA e reporta o domínio.
#     ENTRELARES_SKIP_ANDROID=1 pula a parte Android (permite analyze/test sem build apk).
set -euo pipefail

# ---------------------------------------------------------------- constantes
FLUTTER_VERSION="3.50.1"   # fonte da verdade é o .fvmrc; aqui só para o fallback/checagem
FLUTTER_SHA256="4ad17fc8462fbcef2ba19ff4a78c0a16b7147fde1add8578e267ea62cdb92678"
ANDROID_PLATFORM="android-36"      # compileSdk padrão do Flutter 3.50.1
BUILD_TOOLS="36.0.0"
NDK_VERSION="28.2.13676358"        # ndkVersion padrão do Flutter 3.50.1
CMDLINE_TOOLS_URL="https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$REPO_ROOT/tool/env"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/android-sdk}"
export FVM_CACHE_PATH="${FVM_CACHE_PATH:-$HOME/.fvm-cache}"
PUB_BIN="$HOME/.pub-cache/bin"

log()  { printf '\n==> %s\n' "$*"; }
fail() { printf '\nERRO: %s\n' "$*" >&2; exit 1; }

fvmrc_version="$(sed -n 's/.*"flutter"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$REPO_ROOT/.fvmrc")"
[ "$fvmrc_version" = "$FLUTTER_VERSION" ] || \
  fail ".fvmrc pede Flutter '$fvmrc_version' mas este script pina $FLUTTER_VERSION — alinhe os dois (decisão de versão é do usuário, registrada no board)."

# ------------------------------------------------------------------- JDK 17
log "JDK 17"
JDK17_HOME=""
for d in /usr/lib/jvm/java-17-openjdk-amd64 /usr/lib/jvm/temurin-17-jdk-amd64; do
  [ -x "$d/bin/javac" ] && JDK17_HOME="$d" && break
done
if [ -z "$JDK17_HOME" ]; then
  command -v apt-get >/dev/null || fail "sem apt-get e sem JDK 17 — instale um JDK 17 manualmente."
  SUDO=""; [ "$(id -u)" -ne 0 ] && SUDO="sudo"
  $SUDO apt-get update -qq && $SUDO apt-get install -y -qq openjdk-17-jdk-headless \
    || fail "instalação do openjdk-17 via apt falhou (rede?)."
  JDK17_HOME="/usr/lib/jvm/java-17-openjdk-amd64"
fi
[ -x "$JDK17_HOME/bin/javac" ] || fail "JDK 17 não encontrado após instalação."
export JAVA_HOME="$JDK17_HOME"
"$JAVA_HOME/bin/java" -version 2>&1 | head -1

# ---------------------------------------------------------------------- FVM
log "FVM"
export PATH="$PUB_BIN:$FVM_CACHE_PATH/versions/$FLUTTER_VERSION/bin:$PATH"
if ! command -v fvm >/dev/null; then
  if command -v dart >/dev/null; then
    dart pub global activate fvm
  else
    # sem Dart no sistema: traz o Flutter pinado por tarball oficial (que embute o
    # Dart) e usa esse Dart para ativar o FVM.
    install_flutter_tarball() {
      local dest="$FVM_CACHE_PATH/versions/$FLUTTER_VERSION"
      [ -x "$dest/bin/flutter" ] && return 0
      log "baixando Flutter $FLUTTER_VERSION (tarball oficial)"
      mkdir -p "$FVM_CACHE_PATH/versions"
      local tmp; tmp="$(mktemp -d)"
      curl -fsSL -o "$tmp/flutter.tar.xz" \
        "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
        || fail "download do Flutter falhou — domínio storage.googleapis.com bloqueado?"
      echo "$FLUTTER_SHA256  $tmp/flutter.tar.xz" | sha256sum -c - \
        || fail "sha256 do tarball do Flutter não confere."
      tar -xf "$tmp/flutter.tar.xz" -C "$tmp"
      mv "$tmp/flutter" "$dest"
      rm -rf "$tmp"
      git config --global --add safe.directory "$dest" 2>/dev/null || true
    }
    install_flutter_tarball
    "$FVM_CACHE_PATH/versions/$FLUTTER_VERSION/bin/dart" pub global activate fvm
  fi
fi
command -v fvm >/dev/null || fail "fvm não ficou disponível no PATH ($PUB_BIN)."

# ------------------------------------------------- Flutter 3.50.1 (via FVM)
log "Flutter $FLUTTER_VERSION"
if [ ! -x "$FVM_CACHE_PATH/versions/$FLUTTER_VERSION/bin/flutter" ]; then
  # caminho normal: clone git do FVM; fallback: tarball oficial (rede restrita)
  if ! (cd "$REPO_ROOT" && fvm install); then
    log "fvm install falhou (github.com bloqueado?) — tentando tarball oficial"
    tmp="$(mktemp -d)"
    curl -fsSL -o "$tmp/flutter.tar.xz" \
      "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
      || fail "download do Flutter falhou — domínios github.com E storage.googleapis.com bloqueados."
    echo "$FLUTTER_SHA256  $tmp/flutter.tar.xz" | sha256sum -c - || fail "sha256 do tarball não confere."
    tar -xf "$tmp/flutter.tar.xz" -C "$tmp"
    mkdir -p "$FVM_CACHE_PATH/versions"
    mv "$tmp/flutter" "$FVM_CACHE_PATH/versions/$FLUTTER_VERSION"
    rm -rf "$tmp"
    git config --global --add safe.directory "$FVM_CACHE_PATH/versions/$FLUTTER_VERSION" 2>/dev/null || true
  fi
fi
actual="$(cd "$REPO_ROOT" && fvm flutter --version 2>/dev/null | sed -n 's/^Flutter \([0-9.]*\).*/\1/p')"
[ "$actual" = "$FLUTTER_VERSION" ] || fail "fvm flutter --version reporta '$actual', esperado $FLUTTER_VERSION."
echo "Flutter $actual OK"

# -------------------------------------------------------------- Android SDK
if [ "${ENTRELARES_SKIP_ANDROID:-0}" = "1" ]; then
  log "Android SDK PULADO (ENTRELARES_SKIP_ANDROID=1) — build apk indisponível"
else
  log "Android SDK"
  SDKMANAGER="$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager"
  if [ ! -x "$SDKMANAGER" ]; then
    tmp="$(mktemp -d)"
    curl -fsSL -o "$tmp/cmdtools.zip" "$CMDLINE_TOOLS_URL" \
      || fail "download das cmdline-tools falhou — domínio dl.google.com bloqueado pela política de rede? Reporte o domínio; não use mirrors não oficiais."
    mkdir -p "$ANDROID_HOME/cmdline-tools"
    unzip -q "$tmp/cmdtools.zip" -d "$tmp"
    rm -rf "$ANDROID_HOME/cmdline-tools/latest"
    mv "$tmp/cmdline-tools" "$ANDROID_HOME/cmdline-tools/latest"
    rm -rf "$tmp"
  fi
  yes | "$SDKMANAGER" --licenses >/dev/null 2>&1 || true
  "$SDKMANAGER" --install "platform-tools" "platforms;$ANDROID_PLATFORM" \
    "build-tools;$BUILD_TOOLS" "ndk;$NDK_VERSION" \
    || fail "sdkmanager --install falhou (rede/licenças?)."
  yes | "$SDKMANAGER" --licenses >/dev/null 2>&1 || true
  (cd "$REPO_ROOT" && fvm flutter config --android-sdk "$ANDROID_HOME" >/dev/null)
fi

# ------------------------------------------------------------------ tool/env
log "escrevendo $ENV_FILE"
cat > "$ENV_FILE" <<EOF
# Gerado por tool/setup_env.sh — 'source tool/env' para usar na sessão atual.
export JAVA_HOME="$JAVA_HOME"
export ANDROID_HOME="$ANDROID_HOME"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export FVM_CACHE_PATH="$FVM_CACHE_PATH"
# o SDK pinado no PATH: o shim do fvm (pub global) invoca 'dart', e 'flutter'/'dart'
# diretos apontam para a MESMA versão que o fvm resolve pelo .fvmrc
export PATH="$PUB_BIN:$FVM_CACHE_PATH/versions/$FLUTTER_VERSION/bin:\$JAVA_HOME/bin:\$ANDROID_HOME/platform-tools:\$PATH"
EOF

# ------------------------------------------------------------------- doctor
log "fvm flutter doctor"
cd "$REPO_ROOT"
fvm flutter doctor || true
[ -x "$FVM_CACHE_PATH/versions/$FLUTTER_VERSION/bin/flutter" ] || fail "Flutter ausente ao final."
"$JAVA_HOME/bin/javac" -version >/dev/null 2>&1 || fail "JDK 17 ausente ao final."
if [ "${ENTRELARES_SKIP_ANDROID:-0}" != "1" ]; then
  [ -x "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" ] || fail "Android SDK ausente ao final."
fi
log "ambiente pronto. Rode: source tool/env"
