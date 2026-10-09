# Tarefas a ponderar

Ideias e melhorias em aberto para o Jetson, o video e o Home Assistant. Nao sao compromissos: cada uma tem o contexto necessario para decidir mais tarde. Estado de referencia: 2026-10-09 (ver [JETSON_ORIN_NANO_K3S.md](JETSON_ORIN_NANO_K3S.md)).

## Video

### Analise de video ligada so por evento da camara

**Ideia:** ter a detecao do Jetson desligada por omissao e so a ativar quando a propria camera assinala um evento (pessoa/movimento), analisando a stream apenas nesses momentos.

**Faz sentido?** Sim, como arquitetura de *confirmacao*: as cameras ja enviam eventos para o HA por ONVIF (`binary_sensor.entrada_geral_person_detection`, `binary_sensor.entrada_porta_person_detection`, `binary_sensor.entrada_portao_person_detection`). O Jetson deixaria de vigiar continuamente e passaria a confirmar esses eventos (e, mais tarde, a reconhecer rostos).

| A favor | Contra |
|---|---|
| GPU livre quase sempre: o LLM ganha ~20-30% de velocidade (medido: com a detecao a `interval=2` o LLM caia de ~10 para ~7 tok/s) | **Latencia de arranque**: ligar o pipeline + sessao RTSP leva 5-15 s; a pessoa pode ja ter passado |
| Menos consumo e temperatura (hoje ~65 °C com tudo ligado) | Depende da detecao da camera: o que ela falhar, o Jetson nunca ve |
| Menos sessoes RTSP abertas nas cameras (limite apertado nas TP-Link) | Eventos de movimento da camera geram muitos falsos positivos (mas e precisamente o que o Jetson filtraria) |

**Como fazer bem:** em vez de arrancar o `deepstream-app` a cada evento, manter um pipeline DeepStream sempre carregado mas sem fontes e adicionar/remover cameras em tempo real (DeepStream 7 tem `nvmultiurisrcbin` com API REST para *add/remove stream*). O HA publicaria por MQTT "analisa a camNN durante 60 s" quando o `binary_sensor` da camera liga. Alternativa intermedia: deixar a detecao sempre ligada mas muito espacada (ex.: 1 inferencia/s por camera) e aumentar a cadencia so durante eventos.

**Esforco:** medio-alto (pipeline proprio em vez do `deepstream-app`).

### Ir buscar o trecho de video do evento a Synology

**Ideia:** quando ha um evento, obter o clip gravado pelo Surveillance Station e analisa-lo no Jetson.

**Faz sentido?** Nao para alertas em tempo real: o clip so fica disponivel depois de o evento terminar (dezenas de segundos). **Faz sentido para:**
- **reconhecimento facial**: o clip e da stream principal (HD), muito melhor para rostos do que a substream 640x480 usada na detecao;
- **resumos e pesquisa**: "quem passou no portao hoje?", descricao do evento pelo LLM, galeria de eventos no HA.

**Como:** API do Surveillance Station (`SYNO.SurveillanceStation.Recording` / eventos) com um utilizador so de leitura; um servico no Jetson que, ao receber o evento, espera pelo fim da gravacao, descarrega o clip, extrai frames com rosto e publica o resultado por MQTT.

**Esforco:** medio.

**Combinacao sugerida:** detecao em tempo real (continua ou por evento) para o alerta imediato + clip HD da Synology para reconhecimento facial e resumo, com alguns segundos de atraso.

### Frigate: avaliar o YOLOv7 e decidir o modelo (em curso desde 2026-10-09)

O Frigate 0.18 substituiu o `people-detector` em 2026-10-09 com o YOLOv7-320 (TensorRT, gerado automaticamente; ~20 ms por inferencia; 3 cameras a 5 fps). Deixar a recolher dados alguns dias e avaliar no Frigate (*Review*, *Explore*, *System > Metrics*) e no HA:
- **pessoas falhadas** (passagens conhecidas sem alerta) e **falsos alarmes** (sombras, plantas, animais) por camera;
- **tempo de inferencia** e **deteccoes saltadas** (*skipped*);
- **memoria do Jetson** com LLM + Frigate + voz (hoje ~350 MB livres; alerta no HA abaixo de 300 MB).

Opcoes de modelo se o YOLOv7 nao chegar:
- **YOLOv9-s 320** (`model_type: yolo-generic`, detetor ONNX que usa TensorRT na imagem `-jp6`): **oficial e recomendado** pela documentacao do Frigate; exportar o ONNX uma vez com a receita da documentacao.
- **YOLO26-s 320** (Ultralytics): **nao oficial**, via `yolo-generic`; so funciona se o ONNX exportado tiver saida estilo YOLOv8 `[1, 84, N]` (a saida nativa `[1, 300, 6]` sem NMS nao e lida pelo Frigate). Licenca AGPL-3.0: sem problema para uso domestico. Exportar e verificar a forma da saida antes de mudar o Frigate.
- Em ambos os casos, confirmar o consumo de memoria antes de deixar ativo.

### Avaliar o Frigate em vez do pipeline proprio (feito: Frigate adotado em 2026-10-09)

O [Frigate](https://frigate.video) e o NVR open source mais usado com o Home Assistant e faz por omissao o "so analisar quando ha evento": detecao de movimento continua e barata no CPU sobre a substream, e detecao de objetos (TensorRT) so nas zonas com movimento. Nao depende do evento da camera.

Traz de serie o que hoje esta feito a mao ou por fazer: go2rtc incluido, integracao oficial no HA (entidades, eventos, snapshots e clips), snapshot com a pessoa marcada, zonas/mascaras com editor grafico, reconhecimento facial com interface de treino, e descricao de eventos por LLM ("GenAI") que pode usar o Ollama do Jetson.

No Jetson: imagem oficial `ghcr.io/blakeblackshear/frigate:stable-tensorrt-jp6` (JetPack 6, runtime NVIDIA). O Orin Nano nao tem codificador de video, mas descodificacao e TensorRT sao por hardware e as gravacoes copiam a stream sem recodificar; a gravacao pode ficar desligada (o Synology ja grava).

**Proposta de piloto:** Frigate so com detecao nas 3 cameras, a ler do go2rtc atual, em paralelo com o `people-detector`; comparar falsos alarmes, uso de GPU/memoria (ao lado do LLM) e qualidade das notificacoes. Se ganhar, substitui o `people-detector` e resolve de uma vez a afinacao (#5), a pessoa marcada (#6), o reconhecimento facial (#7) e a analise por evento. A confirmar no piloto: se o reconhecimento facial usa a GPU no Jetson.

Alternativas: Scrypted NVR (mais focado em HomeKit), Viseron (semelhante, comunidade menor), DeepStream com app servidor (controlo total, muito mais trabalho).

### Outras
- **Abrandar a detecao quando ha pessoas em casa** (controlado pelo HA por MQTT): mais GPU para o LLM nas horas em que e usado. Adiado a pedido; a ideia acima pode substitui-la.
- **Afinar limiares e zonas** com dados reais de alguns dias (falsos positivos/negativos por camera).
- **Notificacao com a pessoa marcada** (caixa/recorte a partir da detecao do Jetson): exige que o detetor guarde/publique o frame com a caixa (ex.: imagem por MQTT para uma entidade `image` do HA); hoje a notificacao usa o snapshot ONVIF da camera inteira.
- **Reconhecimento facial** (fase 4): so cameras porta (`cam62`) e portao (`cam63`); falta decidir quem entra na galeria (com fotos e conhecimento das pessoas) e o que fazer com desconhecidos.

## Assistente (LLM / voz)
- **Reconhecimento de voz** (avaliar com voz real): hoje o Whisper `small-int8` corre no add-on do HA, sem vocabulario da casa e a ~7 s por frase. Opcoes se falhar muito: (1) Whisper com `--initial-prompt` no `pi-master-00` (Pi 5 do cluster, parado; mesma velocidade, melhores palavras), mantendo o Piper no add-on; (2) modelo `medium` no add-on (o Pi do HA tem ~6,5 GB livres; mais preciso, ~12-15 s por frase); (3) Whisper na GPU do Jetson (~1 s e preciso, mas volta a apertar a memoria do Jetson).
- **Satelite de voz** (ex.: ESP32-S3 / Voice PE) a usar o pipeline "Jetson" com STT/TTS locais.
- **Controlo da casa pelo LLM**: rever com o uso real se as instrucoes e aliases chegam, ou se e preciso restringir mais a lista exposta.
- **Modelos**: reavaliar quando houver modelos 3-4B melhores em pt-PT com tool calling; um 7-8B so cabe sem o video ligado.

## Infraestrutura
- **Certificados**: Tailscale HTTPS ativo (`https://homeassistant.tailed34f9.ts.net`); publico `telheira.tplinkdns.com` passou para ZeroSSL em 2026-10-09 (primeira emissao por confirmar). Se o ZeroSSL tambem falhar pelo DNS da TP-Link: DuckDNS + Let's Encrypt, ou Tailscale `funnel`. Detalhes em [TLS_CERTIFICATES.md](TLS_CERTIFICATES.md).
- **Reserva DHCP** para o IP `eth0` do `pi-master-00` (`192.168.0.18`), que e o InternalIP do k3s.
- **JetPack 7.2** quando a Waveshare publicar receita para a `JETSON-ORIN-IO-BASE` (ver [JETSON_ORIN_NANO_FIRMWARE.md](JETSON_ORIN_NANO_FIRMWARE.md)).
