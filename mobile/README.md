# Apps mobile — Calculadora CLP

Os dois apps têm o mesmo layout e o mesmo contrato MQTT/TCP:

| Ação | Tópico | Payload |
|---|---|---|
| Enviar | `mobile/numero1`, `mobile/numero2` | inteiro em texto (`"7"`), QoS 1 |
| Receber | `mobile/resposta` (assinado ao conectar, retain) | Float em texto (`"3.5"`) ou `"NaN"` |

Tela: IP e porta do broker (salvos no aparelho), Conectar/Desconectar com indicador de status, dois campos Int16
(-32768..32767), botão **Enviar ao CLP** e o resultado com o horário da última atualização. A operação é escolhida
nos botões físicos do CLP (ou no simulador: `+ - x /`).

## iOS (Swift / SwiftUI + CocoaMQTT)

```bash
cd mobile/ios
open CalculadoraCLP.xcodeproj        # gerado a partir de project.yml (xcodegen generate)
```

- Simulador: use `127.0.0.1` como host (o simulador compartilha a rede do Mac).
- iPhone físico: Signing & Capabilities > selecione seu Team (Apple ID gratuito serve) e rode pelo cabo.
  Na primeira conexão o iOS pede a permissão de **Rede Local**: aceite.

## Android (Kotlin / Jetpack Compose + HiveMQ MQTT Client)

Abra `mobile/android` no Android Studio (JDK 17, ele baixa o Gradle 8.11.1 e o SDK 35).

- Emulador: use `10.0.2.2` como host (endereço do Mac visto pelo emulador).
- Celular físico: ative a Depuração USB e rode pelo Android Studio.
### Build e instalação pelo terminal (sem Android Studio)

```bash
export JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home
export ANDROID_HOME=/opt/homebrew/share/android-commandlinetools
export PATH="$ANDROID_HOME/platform-tools:$PATH"

cd mobile/android
./gradlew assembleDebug          # gera app/build/outputs/apk/debug/app-debug.apk
adb devices                      # o celular deve aparecer como "device"
./gradlew installDebug           # ou: adb install -r app/build/outputs/apk/debug/app-debug.apk
```

Preparar o celular (uma vez): Configurações > Sobre o telefone > toque 7 vezes em "Número da versão" para ativar o
modo desenvolvedor. Depois, Opções do desenvolvedor > ative **Depuração USB**, ligue o cabo e aceite "Permitir depuração".

Sem cabo: envie o `app-debug.apk` para o celular (Google Drive, WhatsApp, e-mail) e abra o arquivo;
o Android pede para permitir "instalar apps desconhecidos" na primeira vez.

## No hotspot

1. Mac conectado ao hotspot do celular. `ipconfig getifaddr en0` mostra o IP do Mac.
2. No app: esse IP e a porta `1883` → **Conectar** (indicador verde).
3. Digite os números → **Enviar ao CLP** → aperte um botão no CLP/simulador → o resultado aparece.
