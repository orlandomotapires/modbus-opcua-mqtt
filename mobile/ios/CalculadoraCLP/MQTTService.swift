import CocoaMQTT
import Foundation

/// Tópicos combinados com o Node-RED (node-red/flows.json)
enum Topicos {
    static let numero1 = "mobile/numero1"
    static let numero2 = "mobile/numero2"
    static let resposta = "mobile/resposta"
}

enum EstadoConexao: Equatable {
    case desconectado
    case conectando
    case conectado
    case erro(String)

    var descricao: String {
        switch self {
        case .desconectado: return "Desconectado"
        case .conectando: return "Conectando..."
        case .conectado: return "Conectado"
        case .erro(let motivo): return "Erro: \(motivo)"
        }
    }
}

final class MQTTService: ObservableObject {
    @Published private(set) var estado: EstadoConexao = .desconectado
    @Published private(set) var resultado: String = "—"
    @Published private(set) var ultimaAtualizacao: Date?

    private var cliente: CocoaMQTT?

    func conectar(host: String, porta: UInt16) {
        desconectar()

        let clientID = "ios-calculadora-\(UUID().uuidString.prefix(8))"
        let mqtt = CocoaMQTT(clientID: clientID, host: host, port: porta)
        mqtt.keepAlive = 30
        mqtt.cleanSession = true
        mqtt.autoReconnect = true
        mqtt.autoReconnectTimeInterval = 3

        mqtt.didConnectAck = { [weak self] mqtt, ack in
            guard let self else { return }
            if ack == .accept {
                self.estado = .conectado
                mqtt.subscribe(Topicos.resposta, qos: .qos1)
            } else {
                self.estado = .erro("\(ack)")
            }
        }
        mqtt.didReceiveMessage = { [weak self] _, mensagem, _ in
            guard let self, mensagem.topic == Topicos.resposta else { return }
            self.resultado = mensagem.string ?? "—"
            self.ultimaAtualizacao = Date()
        }
        mqtt.didDisconnect = { [weak self] _, erro in
            guard let self else { return }
            if let erro {
                self.estado = .erro(erro.localizedDescription)
            } else if self.estado != .desconectado {
                self.estado = .desconectado
            }
        }

        cliente = mqtt
        estado = .conectando
        if !mqtt.connect() {
            estado = .erro("não foi possível iniciar a conexão")
        }
    }

    func desconectar() {
        guard let cliente else { return }
        estado = .desconectado
        cliente.autoReconnect = false
        cliente.disconnect()
        self.cliente = nil
    }

    func enviar(numero1: Int16, numero2: Int16) {
        guard let cliente, estado == .conectado else { return }
        cliente.publish(Topicos.numero1, withString: String(numero1), qos: .qos1)
        cliente.publish(Topicos.numero2, withString: String(numero2), qos: .qos1)
    }
}
