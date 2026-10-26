# Mobile ⇄ MQTT ⇄ Node-RED ⇄ CLP (OPC-UA + Modbus TCP)

```
 Hotspot do celular
 ┌──────────────────────── MAC ───────────────────────────┐
 │ docker compose                                         │
 │  [mosquitto :1883] <──MQTT──> [nodered :1880]          │
 │        ▲                        │ (1) OPC-UA write  ▲ (2) Modbus read FC03 (Float32)
 │        │                        ▼                   │
 │        │              simulator/sim_clp.py   ou   CLP real 192.168.15.1
 └────────┼───────────────────────────────────────────────┘
          │ (3) MQTT/TCP 1883
     [App iOS / Android]
```

| Sentido | Caminho | Detalhe |
|---|---|---|
| Ida | App → `mobile/numero1`, `mobile/numero2` → Node-RED → **OPC-UA Write** | `num1`, `num2` como Int16 (INT no CLP), gravados juntos numa única escrita; se faltar um, nada é escrito |
| Volta | CLP → **Modbus FC03** (HR0–HR1) → Node-RED → `mobile/resposta` | Float32 (REAL), retain; `"NaN"` na divisão por zero |

O CLP tem 4 botões físicos (+ − × ÷). Ao apertar um, ele calcula `num1 op num2` com os valores atuais e grava o resultado.

## Subir

```bash
cp .env.example .env
docker compose up -d --build        # mosquitto + nodered
open http://localhost:1880          # fluxo e palettes já carregados
```

Para recarregar o `node-red/flows.json` depois de editá-lo no repositório: `docker compose down -v && docker compose up -d --build`
(o `-v` apaga o volume `/data` do Node-RED). Depois de editar o `.env`: `docker compose up -d --force-recreate nodered`.

## Simulador do CLP

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r simulator/requirements.txt
python simulator/sim_clp.py         # OPC-UA :4840, Modbus :502
```

Teclas: `+` `-` `x` `/` apertam os botões (pulso), `s` mostra o estado e `q` sai.

| OPC-UA (ns=2) | Tipo | |
|---|---|---|
| `num1`, `num2` | Int16 | escritos pelo Node-RED |
| `btn_soma`, `btn_subtracao`, `btn_multiplicacao`, `btn_divisao` | Boolean | botões; também podem ser postos em `true` via OPC-UA |
| `resultado` | Float | só leitura (também em Modbus HR0–HR1) |

Opções: `--opcua-port`, `--modbus-port`, `--result-addr`.

## Testar sem o celular

```bash
brew install mosquitto              # só para ter mosquitto_pub/sub
mosquitto_sub -h localhost -t mobile/resposta &
mosquitto_pub -h localhost -t mobile/numero1 -m 7
mosquitto_pub -h localhost -t mobile/numero2 -m 2
# no terminal do simulador, aperte "/"  -> mobile/resposta: 3.5
```

## Rede (hotspot)

A rede da universidade costuma bloquear conexões entre dispositivos, então usamos o hotspot de um celular:

1. Ligue o hotspot no celular e conecte o Mac nele.
2. Descubra o IP do Mac: `ipconfig getifaddr en0` (ex.: `172.20.10.2` no hotspot do iPhone). Ele muda a cada sessão.
3. No app, coloque esse IP como host do broker, porta `1883`.
4. macOS: Ajustes > Rede > Firewall. Permita conexões de entrada para o Docker, ou desligue o firewall durante o teste.
5. Teste cedo: de um app MQTT genérico no celular, assine `mobile/resposta` e publique em `mobile/numero1`.

**CLP real:** ele não está na rede do hotspot. Ligue o CLP ao Mac por cabo (adaptador USB-Ethernet), configure nessa
interface um IP fixo na faixa `192.168.15.x` (ex.: `192.168.15.10/24`, sem gateway) e deixe o Wi-Fi no hotspot.

## Trocar simulador ↔ CLP real

No `.env`, comente o bloco do simulador e descomente o do CLP real. Os valores marcados com `_placeholder` ainda
precisam ser confirmados no MasterTool:

- NodeIds de `num1`/`num2` (Symbol Configuration, com acesso de escrita), normalmente
  `ns=4;s=|var|<Dispositivo>.Application.<POU/GVL>.<variável>`. Confirme com o UaExpert.
- Endereço do REAL de resultado no Modbus Server (`RESULT_ADDR`) e a ordem das palavras (`RESULT_WORD_SWAP`).
- Unit-id e porta OPC-UA.

## Apps mobile

iOS (Swift) e Android (Kotlin) em `mobile/`. Veja [mobile/README.md](mobile/README.md).

## Estrutura

```
docker-compose.yml              mosquitto + nodered
.env.example                    endereços do CLP/simulador
mosquitto/config/mosquitto.conf
node-red/Dockerfile             Node-RED 4 + node-red-contrib-opcua + node-red-contrib-modbus
node-red/flows.json             fluxo (ida OPC-UA, volta Modbus)
simulator/sim_clp.py            simulador do CLP
mobile/ios/                     app iOS (SwiftUI + CocoaMQTT, projeto gerado por XcodeGen)
mobile/android/                 app Android (Jetpack Compose + HiveMQ MQTT Client)
```
