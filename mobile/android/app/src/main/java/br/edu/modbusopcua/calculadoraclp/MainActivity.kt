package br.edu.modbusopcua.calculadoraclp

import android.content.Context
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            MaterialTheme(colorScheme = if (isSystemInDarkTheme()) darkColorScheme() else lightColorScheme()) {
                CalculadoraScreen()
            }
        }
    }
}

private const val PREFS = "broker"

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CalculadoraScreen(vm: MqttViewModel = viewModel()) {
    val ui by vm.ui.collectAsStateWithLifecycle()
    val prefs = LocalContext.current.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    var host by rememberSaveable { mutableStateOf(prefs.getString("host", "172.20.10.2")!!) }
    var porta by rememberSaveable { mutableStateOf(prefs.getString("porta", "1883")!!) }
    var numero1 by rememberSaveable { mutableStateOf("") }
    var numero2 by rememberSaveable { mutableStateOf("") }

    val valor1 = numero1.trim().toShortOrNull()
    val valor2 = numero2.trim().toShortOrNull()
    val conectado = ui.estado == EstadoConexao.Conectado

    Scaffold(topBar = { TopAppBar(title = { Text("Calculadora CLP") }) }) { padding ->
        Column(
            modifier = Modifier
                .padding(padding)
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Secao("Broker MQTT") {
                OutlinedTextField(
                    value = host,
                    onValueChange = { host = it.trim() },
                    label = { Text("IP do Mac (ex.: 172.20.10.2)") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri),
                    modifier = Modifier.fillMaxWidth(),
                )
                OutlinedTextField(
                    value = porta,
                    onValueChange = { porta = it.filter(Char::isDigit) },
                    label = { Text("Porta") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    modifier = Modifier.fillMaxWidth(),
                )
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(
                        Modifier
                            .size(10.dp)
                            .background(corEstado(ui.estado), CircleShape)
                    )
                    Text(
                        ui.estado.descricao,
                        style = MaterialTheme.typography.bodySmall,
                        modifier = Modifier
                            .padding(start = 8.dp)
                            .weight(1f),
                    )
                    TextButton(
                        enabled = host.isNotEmpty(),
                        onClick = {
                            if (conectado) {
                                vm.desconectar()
                            } else {
                                prefs.edit().putString("host", host).putString("porta", porta).apply()
                                vm.conectar(host, porta.toIntOrNull() ?: 1883)
                            }
                        },
                    ) { Text(if (conectado) "Desconectar" else "Conectar") }
                }
            }

            Secao("Entradas") {
                CampoNumero("Número 1", numero1, numero1.isEmpty() || valor1 != null) { numero1 = it }
                CampoNumero("Número 2", numero2, numero2.isEmpty() || valor2 != null) { numero2 = it }
                Button(
                    enabled = conectado && valor1 != null && valor2 != null,
                    onClick = { if (valor1 != null && valor2 != null) vm.enviar(valor1, valor2) },
                    modifier = Modifier.fillMaxWidth(),
                ) { Text("Enviar ao CLP") }
                Text(
                    "Inteiros de -32768 a 32767. Depois de enviar, aperte um botão no CLP (+ − × ÷).",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            Secao("Resultado do CLP") {
                Text(ui.resultado, fontSize = 44.sp, fontWeight = FontWeight.SemiBold)
                ui.ultimaAtualizacao?.let {
                    Text(
                        "Atualizado às $it",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }
}

@Composable
private fun Secao(titulo: String, conteudo: @Composable () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(titulo, style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.primary)
        Card(modifier = Modifier.fillMaxWidth()) {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                conteudo()
            }
        }
    }
}

@Composable
private fun CampoNumero(titulo: String, valor: String, valido: Boolean, onChange: (String) -> Unit) {
    OutlinedTextField(
        value = valor,
        onValueChange = { novo -> onChange(novo.filter { it.isDigit() || it == '-' }) },
        label = { Text(titulo) },
        isError = !valido,
        supportingText = if (!valido) {
            { Text("Fora do intervalo Int16") }
        } else null,
        singleLine = true,
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
        modifier = Modifier.fillMaxWidth(),
    )
}

private fun corEstado(estado: EstadoConexao): Color = when (estado) {
    EstadoConexao.Conectado -> Color(0xFF2E7D32)
    EstadoConexao.Conectando -> Color(0xFFF57C00)
    is EstadoConexao.Erro -> Color(0xFFC62828)
    EstadoConexao.Desconectado -> Color.Gray
}
