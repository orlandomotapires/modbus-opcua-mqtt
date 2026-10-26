#!/usr/bin/env bash
# Compila o app Android, instala no celular conectado (adb) e abre.
#
# Uso:  mobile/scripts/build-android.sh            # build + instala se houver celular no adb
#       mobile/scripts/build-android.sh --build    # só compila o APK
#
# Usa JDK 17 e o Android SDK instalados pelo Homebrew, a menos que JAVA_HOME/ANDROID_HOME já estejam definidos.
set -euo pipefail

APP_ID="br.edu.modbusopcua.calculadoraclp"
ANDROID_DIR="$(cd "$(dirname "$0")/../android" && pwd)"
APK="$ANDROID_DIR/app/build/outputs/apk/debug/app-debug.apk"

export JAVA_HOME="${JAVA_HOME_17:-/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home}"
export ANDROID_HOME="${ANDROID_HOME:-/opt/homebrew/share/android-commandlinetools}"
export PATH="$ANDROID_HOME/platform-tools:$PATH"

if [[ ! -x "$JAVA_HOME/bin/java" ]]; then
  echo "JDK 17 não encontrado. Instale com: brew install openjdk@17"
  exit 1
fi
if [[ ! -d "$ANDROID_HOME/platforms" ]]; then
  echo "Android SDK não encontrado. Instale com:"
  echo "  brew install --cask android-commandlinetools"
  echo "  sdkmanager \"platform-tools\" \"platforms;android-35\" \"build-tools;35.0.0\""
  exit 1
fi
[[ -f "$ANDROID_DIR/local.properties" ]] || echo "sdk.dir=$ANDROID_HOME" > "$ANDROID_DIR/local.properties"

echo "==> Compilando APK"
(cd "$ANDROID_DIR" && ./gradlew assembleDebug -q)
echo "==> APK gerado: $APK"

[[ "${1:-}" == "--build" ]] && exit 0

if ! adb devices | awk 'NR>1 && $2=="device"' | grep -q .; then
  echo "Nenhum celular no adb. Ative a Depuração USB, conecte o cabo e aceite a permissão."
  echo "Sem cabo: mande o APK acima para o celular e abra o arquivo."
  exit 1
fi

echo "==> Instalando"
adb install -r "$APK"

echo "==> Abrindo o app"
adb shell monkey -p "$APP_ID" -c android.intent.category.LAUNCHER 1 >/dev/null
