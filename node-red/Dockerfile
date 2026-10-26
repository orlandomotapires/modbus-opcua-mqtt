FROM nodered/node-red:4.0

# Palettes de OPC-UA e Modbus instaladas na imagem
RUN npm install --unsafe-perm --no-update-notifier --no-fund --omit=dev \
    node-red-contrib-opcua \
    node-red-contrib-modbus

# Fluxo inicial. Como /data é um volume nomeado, ele só é copiado na primeira subida;
# para recarregar este arquivo: docker compose down -v && docker compose up -d --build
COPY --chown=node-red:node-red flows.json /data/flows.json
