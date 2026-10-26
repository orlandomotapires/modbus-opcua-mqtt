#!/usr/bin/env bash
# Compila o app iOS, instala no iPhone e abre.
#
# Uso:  mobile/scripts/build-ios.sh            # build + instala no primeiro iPhone físico pareado
#       mobile/scripts/build-ios.sh --build    # só compila
#
# Variáveis opcionais:
#   DEVELOPMENT_TEAM  Team ID da Apple (padrão: lido do certificado "Apple Development" do keychain)
#   DEVICE            UDID/identificador do iPhone (padrão: primeiro iPhone físico pareado)
set -euo pipefail

BUNDLE_ID="br.edu.modbusopcua.CalculadoraCLP"
IOS_DIR="$(cd "$(dirname "$0")/../ios" && pwd)"
BUILD_DIR="$IOS_DIR/build"
APP="$BUILD_DIR/Build/Products/Debug-iphoneos/CalculadoraCLP.app"

if [[ -z "${DEVELOPMENT_TEAM:-}" ]]; then
  # O Team ID é o campo OU do primeiro certificado "Apple Development" válido
  IDENTIDADE="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p' | head -1)"
  if [[ -n "$IDENTIDADE" ]]; then
    DEVELOPMENT_TEAM="$(security find-certificate -c "$IDENTIDADE" -p 2>/dev/null \
      | openssl x509 -noout -subject 2>/dev/null | sed -n 's/.*OU=\([A-Z0-9]*\).*/\1/p')"
  fi
fi
if [[ -z "$DEVELOPMENT_TEAM" ]]; then
  echo "Nenhum certificado 'Apple Development' encontrado."
  echo "Abra o Xcode > Settings > Accounts, entre com seu Apple ID e rode de novo,"
  echo "ou defina DEVELOPMENT_TEAM=<TeamID>."
  exit 1
fi

# Regera o .xcodeproj se o XcodeGen estiver instalado (project.yml é a fonte)
if command -v xcodegen >/dev/null; then
  (cd "$IOS_DIR" && xcodegen generate --quiet)
fi

echo "==> Compilando (Team $DEVELOPMENT_TEAM)"
xcodebuild -project "$IOS_DIR/CalculadoraCLP.xcodeproj" -scheme CalculadoraCLP \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$BUILD_DIR" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  -quiet build
echo "==> App gerado: $APP"

[[ "${1:-}" == "--build" ]] && exit 0

if [[ -z "${DEVICE:-}" ]]; then
  JSON="$(mktemp)"
  xcrun devicectl list devices --json-output "$JSON" >/dev/null
  DEVICE="$(python3 - "$JSON" <<'PY'
import json, sys
for d in json.load(open(sys.argv[1]))["result"]["devices"]:
    hw = d.get("hardwareProperties", {})
    if hw.get("reality") == "physical" and hw.get("platform") == "iOS":
        print(d["identifier"])
        break
PY
)"
  rm -f "$JSON"
fi
if [[ -z "$DEVICE" ]]; then
  echo "Nenhum iPhone pareado. Conecte pelo cabo, toque em 'Confiar' e ative o Modo de Desenvolvedor."
  exit 1
fi

echo "==> Instalando no dispositivo $DEVICE"
xcrun devicectl device install app --device "$DEVICE" "$APP"

echo "==> Abrindo o app"
xcrun devicectl device process launch --device "$DEVICE" "$BUNDLE_ID" \
  || echo "Não abriu: no iPhone, vá em Ajustes > Geral > VPN e Gerenciamento de Dispositivo e confie no seu Apple ID."
