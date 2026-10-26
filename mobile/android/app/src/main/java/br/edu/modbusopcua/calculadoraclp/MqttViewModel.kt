package br.edu.modbusopcua.calculadoraclp

import androidx.lifecycle.ViewModel
import com.hivemq.client.mqtt.MqttClient
import com.hivemq.client.mqtt.datatypes.MqttQos
import com.hivemq.client.mqtt.mqtt3.Mqtt3AsyncClient
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import java.time.LocalTime
import java.time.format.DateTimeFormatter
import java.util.UUID

/** Tópicos combinados com o Node-RED (node-red/flows.json) */
object Topicos {
    const val NUMERO1 = "mobile/numero1"
    const val NUMERO2 = "mobile/numero2"
    const val RESPOSTA = "mobile/resposta"
}

sealed interface EstadoConexao {
    data object Desconectado : EstadoConexao
    data object Conectando : EstadoConexao
    data object Conectado : EstadoConexao
    data class Erro(val motivo: String) : EstadoConexao

    val descricao: String
        get() = when (this) {
            Desconectado -> "Desconectado"
            Conectando -> "Conectando..."
            Conectado -> "Conectado"
            is Erro -> "Erro: $motivo"
        }
}

data class UiState(
    val estado: EstadoConexao = EstadoConexao.Desconectado,
    val resultado: String = "—",
    val ultimaAtualizacao: String? = null,
)

class MqttViewModel : ViewModel() {
    private val _ui = MutableStateFlow(UiState())
    val ui: StateFlow<UiState> = _ui.asStateFlow()

    private var cliente: Mqtt3AsyncClient? = null

    fun conectar(host: String, porta: Int) {
        desconectar()

        // Os listeners rodam em threads do Netty; StateFlow é thread-safe.
        val mqtt = MqttClient.builder()
            .useMqttVersion3()
            .identifier("android-calculadora-${UUID.randomUUID().toString().take(8)}")
            .serverHost(host)
            .serverPort(porta)
            .automaticReconnectWithDefaultConfig()
            .addConnectedListener {
                _ui.update { it.copy(estado = EstadoConexao.Conectado) }
                assinarResposta()
            }
            .addDisconnectedListener { contexto ->
                if (cliente != null) {
                    val motivo = contexto.cause.message ?: contexto.cause.javaClass.simpleName
                    _ui.update { it.copy(estado = EstadoConexao.Erro(motivo)) }
                }
            }
            .buildAsync()

        cliente = mqtt
        _ui.update { it.copy(estado = EstadoConexao.Conectando) }
        mqtt.connectWith()
            .cleanSession(true)
            .keepAlive(30)
            .send()
    }

    private fun assinarResposta() {
        cliente?.subscribeWith()
            ?.topicFilter(Topicos.RESPOSTA)
            ?.qos(MqttQos.AT_LEAST_ONCE)
            ?.callback { publish ->
                val valor = String(publish.payloadAsBytes, Charsets.UTF_8)
                val hora = LocalTime.now().format(DateTimeFormatter.ofPattern("HH:mm:ss"))
                _ui.update { it.copy(resultado = valor, ultimaAtualizacao = hora) }
            }
            ?.send()
    }

    fun desconectar() {
        val atual = cliente ?: return
        cliente = null
        atual.disconnect()
        _ui.update { it.copy(estado = EstadoConexao.Desconectado) }
    }

    fun enviar(numero1: Short, numero2: Short) {
        val mqtt = cliente ?: return
        if (_ui.value.estado != EstadoConexao.Conectado) return
        publicar(mqtt, Topicos.NUMERO1, numero1.toString())
        publicar(mqtt, Topicos.NUMERO2, numero2.toString())
    }

    private fun publicar(mqtt: Mqtt3AsyncClient, topico: String, valor: String) {
        mqtt.publishWith()
            .topic(topico)
            .qos(MqttQos.AT_LEAST_ONCE)
            .payload(valor.toByteArray(Charsets.UTF_8))
            .send()
    }

    override fun onCleared() {
        desconectar()
    }
}
