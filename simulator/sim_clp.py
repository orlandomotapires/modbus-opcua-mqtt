#!/usr/bin/env python3
"""Simulador do CLP (MasterTool).

- Servidor OPC-UA (escrita vinda do Node-RED): num1, num2 (Int16) e os 4 botões físicos.
- Servidor Modbus TCP (leitura pelo Node-RED): resultado Float32 em HR0-HR1.

Botões em pulso: teclas + - x / no terminal. Cada tecla liga o botão, o cálculo
roda na borda de subida com os valores atuais de num1/num2, e o botão volta a False.
"""

import argparse
import asyncio
import logging
import math
import struct
import sys
import termios
import tty

from asyncua import Server, ua
from pymodbus.datastore import ModbusSequentialDataBlock, ModbusServerContext, ModbusSlaveContext
from pymodbus.server import StartAsyncTcpServer

log = logging.getLogger("sim_clp")

FC_HOLDING_REGISTERS = 3

BOTOES = {
    "+": ("btn_soma", lambda a, b: a + b),
    "-": ("btn_subtracao", lambda a, b: a - b),
    "x": ("btn_multiplicacao", lambda a, b: a * b),
    "/": ("btn_divisao", lambda a, b: a / b if b != 0 else math.nan),
}
OPERACAO_POR_BOTAO = {nome: (tecla, op) for tecla, (nome, op) in BOTOES.items()}


def float32_para_registradores(valor: float) -> list[int]:
    hi, lo = struct.unpack(">HH", struct.pack(">f", valor))
    return [hi, lo]


class SimuladorCLP:
    def __init__(self, opcua_port: int, modbus_port: int, result_addr: int):
        self.opcua_port = opcua_port
        self.modbus_port = modbus_port
        self.result_addr = result_addr
        self.server = Server()
        self.vars = {}
        # API do pymodbus 3.8 (versão fixada em requirements.txt; a 3.9+ mudou o datastore)
        self.modbus_device = ModbusSlaveContext(hr=ModbusSequentialDataBlock(0, [0] * 16))
        self.modbus_ctx = ModbusServerContext(slaves=self.modbus_device, single=True)

    async def iniciar_opcua(self):
        await self.server.init()
        self.server.set_endpoint(f"opc.tcp://0.0.0.0:{self.opcua_port}/")
        self.server.set_server_name("Simulador CLP")
        self.server.set_security_policy([ua.SecurityPolicyType.NoSecurity])

        idx = await self.server.register_namespace("urn:simulador:clp")
        clp = await self.server.nodes.objects.add_object(ua.NodeId("CLP", idx), "CLP")

        async def var(nome, valor, tipo, gravavel=True):
            node = await clp.add_variable(ua.NodeId(nome, idx), nome, ua.Variant(valor, tipo))
            if gravavel:
                await node.set_writable()
            self.vars[nome] = node
            return node

        await var("num1", 0, ua.VariantType.Int16)
        await var("num2", 0, ua.VariantType.Int16)
        for nome, _ in BOTOES.values():
            await var(nome, False, ua.VariantType.Boolean)
        await var("resultado", 0.0, ua.VariantType.Float, gravavel=False)

        await self.server.start()
        log.info("OPC-UA em opc.tcp://0.0.0.0:%d  (NodeIds: ns=%d;s=num1, ns=%d;s=num2)", self.opcua_port, idx, idx)

        sub = await self.server.create_subscription(50, self)
        await sub.subscribe_data_change(list(self.vars.values()))

    # Handler da subscription do asyncua: chamado a cada mudança de valor
    async def datachange_notification(self, node, val, data):
        nome = (await node.read_browse_name()).Name
        if nome in ("num1", "num2"):
            log.info("Recebido via OPC-UA: %s = %s", nome, val)
        elif nome in OPERACAO_POR_BOTAO and val is True:
            await self.executar(nome)

    async def executar(self, botao: str):
        tecla, op = OPERACAO_POR_BOTAO[botao]
        a = await self.vars["num1"].read_value()
        b = await self.vars["num2"].read_value()
        resultado = op(a, b)
        if math.isnan(resultado):
            log.warning("Divisão por zero: %s %s %s -> NaN", a, tecla, b)

        self.modbus_device.setValues(FC_HOLDING_REGISTERS, self.result_addr, float32_para_registradores(resultado))
        await self.vars["resultado"].write_value(ua.Variant(resultado, ua.VariantType.Float))
        log.info("[%s] %s %s %s = %s  -> Modbus HR%d-HR%d", botao, a, tecla, b, resultado,
                 self.result_addr, self.result_addr + 1)

        # Pulso: botão volta a False
        await self.vars[botao].write_value(False)

    async def apertar(self, tecla: str):
        nome, _ = BOTOES[tecla]
        await self.vars[nome].write_value(True)

    async def mostrar_estado(self):
        estado = {nome: await node.read_value() for nome, node in self.vars.items()}
        log.info("Estado: %s", estado)

    async def iniciar_modbus(self):
        log.info("Modbus TCP em 0.0.0.0:%d  (resultado Float32 em HR%d-HR%d)",
                 self.modbus_port, self.result_addr, self.result_addr + 1)
        await StartAsyncTcpServer(context=self.modbus_ctx, address=("0.0.0.0", self.modbus_port))


async def ler_teclado(sim: SimuladorCLP, parar: asyncio.Event):
    loop = asyncio.get_running_loop()
    fila: asyncio.Queue[str] = asyncio.Queue()
    loop.add_reader(sys.stdin, lambda: fila.put_nowait(sys.stdin.read(1)))
    print("Botões: [+] soma  [-] subtração  [x] multiplicação  [/] divisão  |  [s] estado  [q] sair", flush=True)
    try:
        while not parar.is_set():
            tecla = (await fila.get()).lower()
            if tecla in BOTOES:
                await sim.apertar(tecla)
            elif tecla == "s":
                await sim.mostrar_estado()
            elif tecla == "q":
                parar.set()
    finally:
        loop.remove_reader(sys.stdin)


async def main():
    parser = argparse.ArgumentParser(description="Simulador do CLP (OPC-UA + Modbus TCP)")
    parser.add_argument("--opcua-port", type=int, default=4840)
    parser.add_argument("--modbus-port", type=int, default=502)
    parser.add_argument("--result-addr", type=int, default=0)
    args = parser.parse_args()

    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(message)s", datefmt="%H:%M:%S")
    logging.getLogger("asyncua").setLevel(logging.ERROR)
    logging.getLogger("pymodbus").setLevel(logging.ERROR)

    sim = SimuladorCLP(args.opcua_port, args.modbus_port, args.result_addr)
    await sim.iniciar_opcua()
    modbus = asyncio.create_task(sim.iniciar_modbus())

    parar = asyncio.Event()
    if sys.stdin.isatty():
        teclado = asyncio.create_task(ler_teclado(sim, parar))
    else:
        log.info("stdin não é um terminal: botões só via OPC-UA (btn_* = True)")
        teclado = None

    try:
        await parar.wait()
    finally:
        modbus.cancel()
        if teclado:
            teclado.cancel()
        await sim.server.stop()


if __name__ == "__main__":
    tty_attrs = None
    if sys.stdin.isatty():
        tty_attrs = termios.tcgetattr(sys.stdin)
        tty.setcbreak(sys.stdin)  # lê uma tecla por vez, sem Enter
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass
    finally:
        if tty_attrs:
            termios.tcsetattr(sys.stdin, termios.TCSADRAIN, tty_attrs)
