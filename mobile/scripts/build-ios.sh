#!/usr/bin/env bash
# Compila o app iOS, instala no iPhone e abre.
#
# Uso:  mobile/scripts/build-ios.sh            # build + instala no iPhone conectado
#       mobile/scripts/build-ios.sh --build    # só compila
#
# Variáveis opcionais:
#   DEVELOPMENT_TEAM  Team ID da Apple (padrão: lido do certificado "Apple Development" do keychain)
#   DEVICE            UDID/identificador do iPhone (padrão: iPhone físico conectado, senão o primeiro pareado)
set -euo pipefail

BUNDLE_ID="br.edu.modbusopcua.CalculadoraCLP"
IOS_DIR="$(cd "$(dirname "$0")/../ios" && pwd)"
BUILD_DIR="$IOS_DIR/build"
APP="$BUILD_DIR/Build/Products/Debug-iphoneos/CalculadoraCLP.app"

BUILD_ONLY=false
[[ "${1:-}" == "--build" ]] && BUILD_ONLY=true

if [[ -z "${DEVELOPMENT_TEAM:-}" ]]; then
  # O Team ID é o campo OU do primeiro certificado "Apple Development" válido
  IDENTIDADE="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p' | head -1)"
  if [[ -n "$IDENTIDADE" ]]; then
    DEVELOPMENT_TEAM="$(security find-certificate -c "$IDENTIDADE" -p 2>/dev/null \
      | openssl x509 -noout -subject 2>/dev/null | sed -n 's/.*OU=\([A-Z0-9]*\).*/\1/p')"
  fi
fi
if [[ -z "${DEVELOPMENT_TEAM:-}" ]]; then
  echo "Nenhum certificado 'Apple Development' encontrado."
  echo "Abra o Xcode > Settings > Accounts, entre com seu Apple ID e rode de novo,"
  echo "ou defina DEVELOPMENT_TEAM=<TeamID>."
  exit 1
fi

DEVICE_ID=""
DEVICE_UDID=""
if ! $BUILD_ONLY; then
  # Escolhe o iPhone: DEVICE informado, senão o físico conectado (cabo/rede), senão o primeiro pareado
  JSON="$(mktemp)"
  xcrun devicectl list devices --json-output "$JSON" >/dev/null
  ESCOLHIDO="$(python3 -c '
import json, sys
pedido = sys.argv[2]
fisicos = [d for d in json.load(open(sys.argv[1]))["result"]["devices"]
           if d.get("hardwareProperties", {}).get("reality") == "physical"
           and d.get("hardwareProperties", {}).get("platform") == "iOS"]
if pedido:
    fisicos = [d for d in fisicos if pedido in (d["identifier"], d["hardwareProperties"].get("udid"))]
fisicos.sort(key=lambda d: d.get("connectionProperties", {}).get("tunnelState") != "connected")
if fisicos:
    d = fisicos[0]
    print(d["identifier"], d["hardwareProperties"]["udid"], d.get("deviceProperties", {}).get("name", ""))
' "$JSON" "${DEVICE:-}")"
  rm -f "$JSON"
  if [[ -z "$ESCOLHIDO" ]]; then
    echo "Nenhum iPhone pareado. Conecte pelo cabo, toque em 'Confiar' e ative o Modo de Desenvolvedor."
    exit 1
  fi
  read -r DEVICE_ID DEVICE_UDID DEVICE_NOME <<< "$ESCOLHIDO"
  echo "==> iPhone: $DEVICE_NOME ($DEVICE_UDID)"
fi

# Regera o .xcodeproj se o XcodeGen estiver instalado (project.yml é a fonte)
if command -v xcodegen >/dev/null; then
  (cd "$IOS_DIR" && xcodegen generate --quiet)
fi

# Compilar para o aparelho específico faz o Xcode registrá-lo no perfil de provisionamento
DESTINO="generic/platform=iOS"
[[ -n "$DEVICE_UDID" ]] && DESTINO="id=$DEVICE_UDID"

echo "==> Compilando (Team $DEVELOPMENT_TEAM)"
xcodebuild -project "$IOS_DIR/CalculadoraCLP.xcodeproj" -scheme CalculadoraCLP \
  -destination "$DESTINO" \
  -derivedDataPath "$BUILD_DIR" \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  -quiet build
echo "==> App gerado: $APP"

$BUILD_ONLY && exit 0

echo "==> Instalando"
xcrun devicectl device install app --device "$DEVICE_ID" "$APP"

echo "==> Abrindo o app"
xcrun devicectl device process launch --device "$DEVICE_ID" "$BUNDLE_ID" \
  || echo "Não abriu: no iPhone, vá em Ajustes > Geral > VPN e Gerenciamento de Dispositivo e confie no seu Apple ID."
