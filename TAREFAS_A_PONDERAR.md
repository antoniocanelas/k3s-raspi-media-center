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

Se o YOLOv7-320 nao chegar: **YOLOv7-416** (TensorRT nativo, ~1,5x o tempo). Modelos ONNX (YOLOv9/YOLO26) foram **descartados** em 2026-10-10: testado o YOLOv9, mais lento (28-38 ms) e ~+280 MB de RAM no Jetson.

### Avaliar o Frigate em vez do pipeline proprio (feito: Frigate adotado em 2026-10-09)

O [Frigate](https://frigate.video) e o NVR open source mais usado com o Home Assistant e faz por omissao o "so analisar quando ha evento": detecao de movimento continua e barata no CPU sobre a substream, e detecao de objetos (TensorRT) so nas zonas com movimento. Nao depende do evento da camera.

Traz de serie o que hoje esta feito a mao ou por fazer: go2rtc incluido, integracao oficial no HA (entidades, eventos, snapshots e clips), snapshot com a pessoa marcada, zonas/mascaras com editor grafico, reconhecimento facial com interface de treino, e descricao de eventos por LLM ("GenAI") que pode usar o Ollama do Jetson.

No Jetson: imagem oficial `ghcr.io/blakeblackshear/frigate:stable-tensorrt-jp6` (JetPack 6, runtime NVIDIA). O Orin Nano nao tem codificador de video, mas descodificacao e TensorRT sao por hardware e as gravacoes copiam a stream sem recodificar; a gravacao pode ficar desligada (o Synology ja grava).

**Proposta de piloto:** Frigate so com detecao nas 3 cameras, a ler do go2rtc atual, em paralelo com o `people-detector`; comparar falsos alarmes, uso de GPU/memoria (ao lado do LLM) e qualidade das notificacoes. Se ganhar, substitui o `people-detector` e resolve de uma vez a afinacao (#5), a pessoa marcada (#6), o reconhecimento facial (#7) e a analise por evento. A confirmar no piloto: se o reconhecimento facial usa a GPU no Jetson.

Alternativas: Scrypted NVR (mais focado em HomeKit), Viseron (semelhante, comunidade menor), DeepStream com app servidor (controlo total, muito mais trabalho).

### Rever no Home Assistant as deteccoes de pessoas do dia (feito em 2026-10-09)

Feito com a integracao Frigate v5.15.6 + Advanced Camera Card v8.1.0 (vista "Deteções" no dashboard do HA). Detalhes no guia do Jetson.


**Ideia:** ver no HA (app ou browser) a lista das pessoas detetadas no dia, com snapshot e clip de cada evento, sem ter de abrir o Frigate.

O Frigate ja guarda tudo o que e preciso: snapshot com a caixa e clip HD de cada alerta de pessoa (7 dias). Opcoes, da mais completa a mais simples:
- **Integracao Frigate para o HA** (via HACS, `blakeblackshear/frigate-hass-integration`) + **Advanced Camera Card** (HACS): cartao com linha temporal do dia, miniaturas, clips e snapshots por camera; a integracao tambem acrescenta o Frigate ao *Media* do HA (pasta de clips e snapshots por camera/dia) e entidades/eventos nativos. Pre-requisito: o HA alcancar a API do Frigate (porta 5000 sem autenticacao so dentro do cluster; usar a 8971 com utilizador proprio para o HA, ou expor a 5000 so para o IP do HA).
- **Painel lateral com a interface do Frigate** (*Review* do Frigate dentro do HA, por iframe/painel web): rapido de montar, mas e a interface do Frigate, com o login dele.
- **Sem componentes novos:** guardar o snapshot de cada alerta numa pasta por dia (`/local/frigate/AAAA-MM-DD/`) a partir da automacao atual e mostrar uma galeria simples num dashboard (so imagens, sem clips).

Recomendacao: integracao Frigate + Advanced Camera Card; e a forma padrao na comunidade e cobre imagens e videos com filtro por dia, camera e tipo (pessoa, carro, gato, cao).

### Outras
- **Abrandar a detecao quando ha pessoas em casa** (controlado pelo HA por MQTT): mais GPU para o LLM nas horas em que e usado. Adiado a pedido; a ideia acima pode substitui-la.
- **Afinar limiares e zonas** com dados reais de alguns dias (falsos positivos/negativos por camera).
- **Notificacao com a pessoa marcada** (caixa/recorte a partir da detecao do Jetson): exige que o detetor guarde/publique o frame com a caixa (ex.: imagem por MQTT para uma entidade `image` do HA); hoje a notificacao usa o snapshot ONVIF da camera inteira.
- **Reconhecimento facial** (ativo desde 2026-10-10 na Porta e no Portão): as câmaras estão altas e apontadas para baixo, por isso a cara só se vê com a pessoa ainda longe (~30-45 px no frame de 1280x720); de perto olham para baixo. `min_area` baixou de 2500 para 1600 (40x40) para o Frigate tentar e guardar essas caras. Treino contínuo: o HA lembra às 21:00 quando há caras por classificar (`sensor.jetson_faces_pending`). Se continuar fraco: (1) detetar a 2560x1440 só na Porta (mais CPU/RAM no Jetson); (2) baixar/inclinar a câmara da Porta; (3) mais fotos de frente da Du, do Miguel e do Augusto.

## Assistente (LLM / voz)
- **LLM do Assist em qwen2.5 3B desde 2026-10-10** (modelo `assist-jetson`; antes qwen3 4B via `qwen3-jetson`, ainda disponível): o Jetson ficou sem memória (Frigate parou de detetar) com o reconhecimento facial `large` (~700 MB) + qwen3 4B (3,3 GB). Com o 3B: 2,2 GB e ~1,16 GB livres, mas o Assist ficou mais fraco (falha chamadas às ferramentas, respostas vagas). Decisão do António: manter por agora. Alternativa recomendada para voltar a um Assist bom: qwen3 4B + reconhecimento facial `small` (estimativa ~600-700 MB livres). Nota: a conversa no HA ainda se chama "Jetson (Qwen3 4B)" (só o nome).
- **Reconhecimento de voz** (avaliar com voz real): hoje o Whisper `small-int8` corre no add-on do HA, sem vocabulario da casa e a ~7 s por frase. Opcoes se falhar muito: (1) Whisper com `--initial-prompt` no `pi-master-00` (Pi 5 do cluster, parado; mesma velocidade, melhores palavras), mantendo o Piper no add-on; (2) modelo `medium` no add-on (o Pi do HA tem ~6,5 GB livres; mais preciso, ~12-15 s por frase); (3) Whisper na GPU do Jetson (~1 s e preciso, mas volta a apertar a memoria do Jetson).
- **Satelite de voz** (ex.: ESP32-S3 / Voice PE) a usar o pipeline "Jetson" com STT/TTS locais.
- **Controlo da casa pelo LLM**: rever com o uso real se as instrucoes e aliases chegam, ou se e preciso restringir mais a lista exposta.
- **Cache de prompts do LLM em RAM** (feito em 2026-10-09): o `llama-server` lancado pelo Ollama guardava cada conversa num cache em RAM (~650 MiB por prompt de ~4.6k tokens, limite 8 GB); um teste com dois pedidos esgotou a memoria do Jetson e reiniciou o Frigate. Corrigido com `LLAMA_ARG_CACHE_RAM=0` e `OLLAMA_KV_CACHE_TYPE=q8_0` (KV 612 MiB em vez de ~1.1 GB). Medido com prompt de 6.8k tokens: pedido novo ~12 s de leitura (igual), geracao ~12 tok/s (antes 13.4), seguimento da mesma conversa 3.6 s; voltar a uma conversa anterior deixa de usar cache (~15 s). RAM disponivel ~1.3 GB depois de 4 pedidos (antes ~155 MB e a cair).
- **Modelos**: reavaliar quando houver modelos 3-4B melhores em pt-PT com tool calling; um 7-8B so cabe sem o video ligado.

## Infraestrutura
- **Alerta de câmara desligada ou Frigate sem detetar** (pedido 2026-10-10): hoje não há aviso quando uma câmara fica desligada no Frigate (`enabled: False` em runtime, como a Porta entre ~14:35 e ~15:40) nem quando o detetor para por falta de memória (`skipped_fps` ~ `camera_fps`, `process_fps` ~0, log "Too many unprocessed recording segments"). Ideia: automação no HA sobre `camera.camNN` (state != recording por > 10 min) e sobre `frigate/stats` (skipped_fps alto > 5 min) com notificação para o António.
- **[A FAZER EM CASA] Bloqueio de logins falhados no HA (`login_attempts_threshold`)** — pendente desde 2026-10-10. O HA ve todos os pedidos externos como `10.42.3.x` (o pod svclb do ServiceLB/klipper no pi-master-00 faz SNAT mesmo com `externalTrafficPolicy: Local`, ja aplicado). Ligar o limite agora bloquearia todo o acesso externo. Passos: (1) confirmar na pagina do router que as portas 80/443/8123/32443 vao para `192.168.0.18` (pi-master-00); (2) Traefik com `hostPort` nessas portas no pi-master-00 (ja fixo por `nodeSelector`) e servico sem ServiceLB (ClusterIP), para o IP real chegar via X-Forwarded-For; (3) testar com um pedido com token invalido pela internet (dados moveis) e ver no log do HA o IP publico; (4) so entao `login_attempts_threshold: 5` via `http/config/configure` + `promote` (`ip_ban_enabled` ja esta `true`). Fazer em casa: um erro corta o acesso remoto. Entretanto: 2FA (TOTP) nos utilizadores do HA.
- **Certificados** (resolvido 2026-10-10): `telheira.duckdns.org` com Let's Encrypt (URL externo do HA e dos links das notificações), `telheira.tplinkdns.com` com ZeroSSL válido até 2027-01-07 e Tailscale HTTPS. Ver [TLS_CERTIFICATES.md](TLS_CERTIFICATES.md).
- **Reserva DHCP** para o IP `eth0` do `pi-master-00` (`192.168.0.18`), que e o InternalIP do k3s.
- **JetPack 7.2** quando a Waveshare publicar receita para a `JETSON-ORIN-IO-BASE` (ver [JETSON_ORIN_NANO_FIRMWARE.md](JETSON_ORIN_NANO_FIRMWARE.md)).
