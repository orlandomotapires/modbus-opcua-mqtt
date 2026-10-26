import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var mqtt: MQTTService

    @AppStorage("brokerHost") private var host = "172.20.10.2"
    @AppStorage("brokerPorta") private var porta = "1883"
    @State private var numero1 = ""
    @State private var numero2 = ""

    private var valor1: Int16? { Int16(numero1.trimmingCharacters(in: .whitespaces)) }
    private var valor2: Int16? { Int16(numero2.trimmingCharacters(in: .whitespaces)) }
    private var conectado: Bool { mqtt.estado == .conectado }

    var body: some View {
        NavigationStack {
            Form {
                Section("Broker MQTT") {
                    TextField("IP do Mac (ex.: 172.20.10.2)", text: $host)
                        .keyboardType(.numbersAndPunctuation)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Porta", text: $porta)
                        .keyboardType(.numberPad)
                    HStack {
                        Circle()
                            .fill(corEstado)
                            .frame(width: 10, height: 10)
                        Text(mqtt.estado.descricao)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(conectado ? "Desconectar" : "Conectar") {
                            if conectado {
                                mqtt.desconectar()
                            } else {
                                mqtt.conectar(host: host, porta: UInt16(porta) ?? 1883)
                            }
                        }
                        .disabled(host.isEmpty)
                    }
                }

                Section {
                    CampoNumero(titulo: "Número 1", texto: $numero1, valido: numero1.isEmpty || valor1 != nil)
                    CampoNumero(titulo: "Número 2", texto: $numero2, valido: numero2.isEmpty || valor2 != nil)
                    Button {
                        if let valor1, let valor2 {
                            mqtt.enviar(numero1: valor1, numero2: valor2)
                        }
                    } label: {
                        Text("Enviar ao CLP")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!conectado || valor1 == nil || valor2 == nil)
                } header: {
                    Text("Entradas")
                } footer: {
                    Text("Inteiros de -32768 a 32767. Depois de enviar, aperte um botão no CLP (+ − × ÷).")
                }

                Section("Resultado do CLP") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(mqtt.resultado)
                            .font(.system(size: 44, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        if let data = mqtt.ultimaAtualizacao {
                            Text("Atualizado às \(data.formatted(date: .omitted, time: .standard))")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Calculadora CLP")
        }
    }

    private var corEstado: Color {
        switch mqtt.estado {
        case .conectado: return .green
        case .conectando: return .orange
        case .erro: return .red
        case .desconectado: return .gray
        }
    }
}

private struct CampoNumero: View {
    let titulo: String
    @Binding var texto: String
    let valido: Bool

    var body: some View {
        LabeledContent(titulo) {
            TextField("0", text: $texto)
                .keyboardType(.numbersAndPunctuation)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(valido ? Color.primary : Color.red)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(MQTTService())
}
