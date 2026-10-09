# Jetson Orin Nano Super no cluster k3s

Este guia cobre o caminho desde o primeiro boot do Jetson Orin Nano 8 GB até sua entrada como worker no cluster k3s existente. A integracao inicial mantem o Jetson isolado para workloads ate que cada aplicacao seja escolhida explicitamente.

Comece pela etapa detalhada de [atualizacao de firmware e primeira instalacao](JETSON_ORIN_NANO_FIRMWARE.md). Este guia geral descreve as etapas posteriores de rede, ingresso como worker e integracao dos workloads.

## Como o cluster esta organizado

- `pi-master-00` (`192.168.0.240`) e o Raspberry Pi que hospeda o control plane k3s e exporta os volumes NFS de configuracao e downloads em `/ssd`.
- O Synology (`192.168.0.200`) exporta o volume NFS de midia.
- O overlay `overlays/armhf` e o manifesto `install_armhf.yaml` sao nomes historicos. O overlay usa imagens ARM64; o Jetson tambem e ARM64 (`aarch64`).
- O Jellyfin atualmente roda no Synology. Os manifests base do cluster configuram Service/EndpointSlice para ele, nao um Deployment no Jetson ou no k3s.
- Alguns pods possuem afinidade ou `nodeSelector` para `pi-master-00`; os demais podem ser agendados em qualquer no compativel se estiver sem taint.

## Papel pretendido do Jetson

O Jetson sera um worker dedicado a IA de video e LLM, com esta ordem de prioridade:

1. **LLM:** servico de inferencia permanentemente disponivel. Perfil inicial conservador: Qwen2.5 1.5B Instruct quantizado em Q4, com contexto moderado, para deixar memoria ao detector.
2. **Video:** deteccao de pessoas como carga best-effort; reconhecimento facial apenas quando houver eventos. Se faltar capacidade, reduzir primeiro FPS, resolucao ou numero de streams processadas.
3. **Plex/Jellyfin:** fase posterior, depois de LLM e video estaveis. O [guia multimidia da NVIDIA para Orin Nano](https://docs.nvidia.com/jetson/archives/r36.4/DeveloperGuide/SD/Multimedia/SoftwareEncodeInOrinNano.html) confirma que o modulo nao tem NVENC; o encode H.264 documentado usa `libx264` por software. Prefira Direct Play e trate transcodificacao como CPU-bound e de menor prioridade.

Comeca com o modelo 1.5B e mede a deteccao com a carga real. Se a deteccao perder fluidez, reduz primeiro o contexto ou troca para um modelo ainda menor; so experimenta Qwen2.5 3B depois de confirmar margem de memoria e desempenho.

Para avaliar modelos, formatos e quantizacoes numa fase posterior, consulta o [Hugging Face](https://huggingface.co). A compatibilidade com JetPack e a memoria disponivel no Orin Nano ainda tera de ser validada para cada modelo e runtime.

O destino final pretendido para Plex e Jellyfin continua a ser exclusivamente o Jetson, mas a migracao fica para uma fase posterior. Durante o rollout inicial de LLM e video, mantem os servicos atuais no Synology. Quando o Jetson estiver validado, migra Plex/Jellyfin um de cada vez, preservando dados e configuracoes do Synology para rollback; troca as rotas apenas depois dos testes. Nunca montes a mesma pasta de configuracao simultaneamente nos dois servidores.

O taint `workload=jetson:NoSchedule` impede que workloads comuns do cluster sejam agendados nele por acidente; os servicos LLM e de video terao de tolerar esse taint e selecionar este no. Os 8 GB sao partilhados pelo sistema, GPU, modelo LLM, detector e reconhecimento facial. A prioridade do LLM precisa tambem de ser respeitada pela aplicacao: Kubernetes nao interrompe automaticamente trabalho ja em execucao na GPU para dar lugar ao LLM. Por isso, sera necessario medir a carga combinada e limitar/adaptar o processamento de video quando o LLM estiver ativo.

### Origem dos streams de video

A Synology continua a gravar o stream principal das cameras. Para analise em tempo real, o Jetson deve ligar-se diretamente as cameras por RTSP e consumir a substream de menor resolucao para deteccao, evitando ler gravacoes com atraso ou processar uma segunda copia do stream principal. Antes de fixar este desenho, confirma que cada camera permite clientes/streams simultaneos e que a substream tem detalhe suficiente para a deteccao pretendida. Se o evento da camera/ONVIF estiver disponivel, usa-o como gatilho; para reconhecimento facial, pode ser necessario obter um snapshot ou frame de maior resolucao apenas nesse evento.

O NVMe nao e partilhado automaticamente com o cluster. O overlay Jetson prepara volumes locais para modelos/estado de IA e dados dos media servers; a biblioteca de filmes e os clips que devam ser preservados continuam no Synology via NFS.

## Esquema da arquitetura pretendida

Este e o desenho alvo; DeepStream, LLM e os media servers ainda nao estao implantados no Jetson.

```mermaid
flowchart LR
  CAM["TP-Link VIGI C340<br/>RTSP main + substream<br/>evento ONVIF: confirmar"]
  NAS["Synology<br/>grava stream principal<br/>NFS: biblioteca de media"]
  HA["Home Assistant<br/>automacao / eventos"]
  PI["pi-master-00<br/>k3s control plane<br/>192.168.0.240"]
  CLIENT["Projetos genericos<br/>clientes LLM"]

  subgraph JETSON["Waveshare JETSON-ORIN-IO-BASE<br/>Orin Nano 8 GB / NVMe 256 GB"]
    subgraph K3S["k3s worker arm64<br/>taint workload=jetson"]
      DS["DeepStream + TensorRT<br/>deteccao / tracking<br/>substream RTSP"]
      FACE["Reconhecimento facial<br/>componente/modelo a validar"]
      LLM["API LLM sempre disponivel<br/>Qwen2.5 1.5B Q4 inicial"]
      MEDIA["Plex / Jellyfin<br/>fase posterior<br/>Direct Play preferido"]
      AI_PV[("PV local ai<br/>modelos / estado")]
      MEDIA_PV[("PV local media<br/>config / transcode temp")]
    end
  end

  PI -. "regista e gere" .-> JETSON
  CAM -- "RTSP main" --> NAS
  CAM -- "RTSP substream" --> DS
  CAM -. "evento humano, se ONVIF expuser" .-> HA
  HA -. "gatilho" .-> FACE
  DS -- "pessoa/tracking" --> FACE
  CLIENT --> LLM
  AI_PV -. "modelos" .-> LLM
  AI_PV -. "TensorRT engines/modelos" .-> DS
  NAS -- "NFS: media" --> MEDIA
  MEDIA_PV -. "config/cache local" .-> MEDIA
```

## 1. Antes de ligar

Separe:

- Kit Waveshare Orin Nano 8 GB com placa-base `JETSON-ORIN-IO-BASE`, modulo Wi-Fi e fonte fornecida.
- Monitor e cabo compativeis com a saida de video existente na placa Waveshare, teclado e mouse.
- Cabo Ethernet para a rede local. Ethernet e preferivel para um worker que acessara volumes NFS.
- Acesso ao roteador para criar uma reserva DHCP para o Jetson.
- Acesso administrativo ao `pi-master-00` e ao Synology.

Confirme a tensao/corrente da fonte no manual da placa antes de ligar. O NVMe incluído é de 256 GB, conforme confirmado; o `128gb` no URL do anúncio parece estar desatualizado. Este kit usa placa-base Waveshare, nao a carrier board do Developer Kit NVIDIA.

Antes de instalar, escolha um nome estavel, por exemplo `jetson-orin-01`, e reserve um endereco DHCP para ele na rede `192.168.0.0/24`. Anote o IP reservado. Nao reutilize `192.168.0.240` nem `192.168.0.200`.

No Raspberry Pi, confirme que o cluster esta saudavel e anote a versao exata do k3s para instalar a mesma versao no worker:

```bash
sudo k3s --version
sudo k3s kubectl get nodes -o wide
```

Confirme tambem que o Synology e o Raspberry Pi estarao ligados e acessiveis pela rede quando o Jetson montar os volumes NFS.

## 2. Firmware e sistema operacional

Siga primeiro [a etapa de firmware para o kit Waveshare](JETSON_ORIN_NANO_FIRMWARE.md). Nao use a ISO nem o alvo de flash do Developer Kit oficial NVIDIA sem confirmacao explicita de compatibilidade com a placa-base `JETSON-ORIN-IO-BASE`. Conclua esta fase e confirme o BSP/JetPack suportado antes de prosseguir com a preparacao do worker k3s.

Depois de instalar o sistema pelo procedimento confirmado da Waveshare, ative o modo **MAXN SUPER** se estiver disponivel no JetPack instalado. Esse modo e de desempenho; nao e uma etapa de atualizacao de firmware.

## 3. Preparar o worker

> **Estado em 2026-10-09:** todos os passos desta secao e das secoes 4-5 foram executados. `jetson-orin-01` esta `Ready` (IP `192.168.0.250`, MAC `4c:bb:47:02:3b:f2`), com JetPack 6.2.1 e k3s `v1.34.5+k3s1`.

### 3.1 Acesso e sudo

No Mac, o acesso e por chave dedicada (`~/.ssh/jetson`) e pelo alias `jetson-orin-01` em `~/.ssh/config`:

```bash
ssh-keygen -t ed25519 -N "" -C jetson-orin-01 -f ~/.ssh/jetson
ssh-copy-id -i ~/.ssh/jetson.pub jetson@192.168.0.250
```

Para automatizar a instalacao por SSH, o utilizador `jetson` tem sudo sem password (como o `admin` dos Pis):

```bash
ssh -t jetson-orin-01 'echo "jetson ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/90-jetson-nopasswd && sudo chmod 440 /etc/sudoers.d/90-jetson-nopasswd'
```

### 3.2 Stack NVIDIA (antes do k3s)

O flash Waveshare usa o *sample rootfs* do BSP, que traz so o L4T: sem CUDA, TensorRT nem `nvidia-container-toolkit`. Instala o JetPack **antes** do agente k3s, porque o k3s so deteta o `nvidia-container-runtime` (e cria o runtime `nvidia` no containerd) quando arranca:

```bash
sudo apt update
sudo apt install -y nvidia-jetpack nfs-common curl
```

Resultado esperado: `nvidia-jetpack 6.2.1`, CUDA 12.6 (`/usr/local/cuda/bin/nvcc --version`), TensorRT 10.3, `nvidia-container-toolkit 1.16.2`. Ver a decisao 6.2.1 vs 7.x em [JETSON_ORIN_NANO_FIRMWARE.md](JETSON_ORIN_NANO_FIRMWARE.md#decisão-jetpack-621-vs-7x).

### 3.3 Modo headless

O Jetson e gerido por SSH; o desktop GNOME so consome RAM partilhada com a GPU. Desliga-o e remove os snaps que so serviam o browser:

```bash
sudo systemctl set-default multi-user.target
sudo snap remove --purge chromium cups
sudo snap remove --purge gnome-46-2404 mesa-2404 gtk-common-themes
sudo snap remove --purge core24 core26 bare
sudo reboot
```

Medido: RAM usada em repouso passou de 1,5 GiB para 374 MiB. Para voltar a ter desktop: `sudo systemctl start gdm` (uma vez) ou `sudo systemctl set-default graphical.target`.

Mensagens de kernel no `tty1` como `overlayfs: idmapped layers are currently not supported` e `tmpfs: Unknown parameter 'noswap'` sao inofensivas (containerd/kubelet a testar funcionalidades de kernels mais recentes que o 5.15).

### 3.4 Diretorios dos PVs locais

Os PVs `local:` nao criam diretorios; cria-os antes de qualquer pod os usar:

```bash
sudo mkdir -p /var/lib/jetson-data/ai \
  /var/lib/jetson-data/media-config \
  /var/lib/jetson-data/transcode
```

### 3.5 Agente k3s

No `pi-master-00`, leia o token de registro do k3s. Trate-o como uma senha: nao o publique, nao o coloque no Git e nao o envie em mensagens.

```bash
sudo cat /var/lib/rancher/k3s/server/node-token
```

Alternativa sem expor o token no ecra (foi o metodo usado): ler no Pi e escrever no Jetson por pipe a partir do Mac:

```bash
TOKEN=$(ssh pi-master-00 'sudo -n cat /var/lib/rancher/k3s/server/node-token')
printf 'server: https://192.168.0.240:6443\ntoken: "%s"\nnode-name: jetson-orin-01\nnode-label:\n  - hardware.platform=nvidia-jetson\nnode-taint:\n  - workload=jetson:NoSchedule\n' "$TOKEN" \
  | ssh jetson-orin-01 'sudo tee /etc/rancher/k3s/config.yaml >/dev/null && sudo chmod 600 /etc/rancher/k3s/config.yaml'
unset TOKEN
```

**Nota sobre o IP do control plane:** o `pi-master-00` tem `eth0` = `192.168.0.18` (InternalIP anunciado pelo k3s) e `wlan0` = `192.168.0.240` (IP reservado, usado no kubeconfig e no NFS). O `server:` so serve a API; o trafego entre pods usa os InternalIPs, por isso manter `.240` e aceitavel. Mudar para `.18` so depois de o reservar no router.

Manualmente, no Jetson, crie a configuracao do agente. Cole o token diretamente no terminal local, substituindo o texto de exemplo:

```bash
sudo install -d -m 0755 /etc/rancher/k3s
sudoedit /etc/rancher/k3s/config.yaml
```

Conteudo de `/etc/rancher/k3s/config.yaml`:

```yaml
server: https://192.168.0.240:6443
token: "COLE_AQUI_O_CONTEUDO_DE_node-token"
node-name: jetson-orin-01
node-label:
  - hardware.platform=nvidia-jetson
node-taint:
  - workload=jetson:NoSchedule
```

Proteja o arquivo e instale o agente na mesma versao do servidor. Substitua `vX.Y.Z+k3sN` pelo valor de versao reportado por `sudo k3s --version` no Pi:

```bash
sudo chmod 600 /etc/rancher/k3s/config.yaml
curl -sfL https://get.k3s.io | sudo env INSTALL_K3S_VERSION="vX.Y.Z+k3sN" sh -s - agent
```

O agente deve iniciar automaticamente. Confira no Jetson, incluindo o runtime NVIDIA no containerd:

```bash
sudo systemctl status k3s-agent --no-pager
sudo grep -A3 "runtimes.'nvidia'" /var/lib/rancher/k3s/agent/etc/containerd/config.toml
```

Se houver falha, consulte o log com `sudo journalctl -u k3s-agent -b --no-pager` antes de tentar reinstalar.

## 4. Registrar e isolar o no

No `pi-master-00`, espere o Jetson aparecer e confirme a arquitetura:

```bash
sudo k3s kubectl get nodes -o wide
sudo k3s kubectl get node jetson-orin-01 -o jsonpath='{.status.nodeInfo.architecture}{"\n"}'
```

O estado deve ser `Ready` e a arquitetura deve ser `arm64`. Em seguida, identifique o hardware e evite que os workloads existentes sejam agendados no Jetson sem uma alteracao planejada:

```bash
sudo k3s kubectl describe node jetson-orin-01
```

O label e o taint sao definidos no primeiro registro do agente. O taint e intencional: os pods atuais nao possuem toleration para ele. Para permitir um workload no futuro, altere o Deployment correspondente para selecionar `kubernetes.io/hostname: jetson-orin-01` e adicionar toleration para `workload=jetson`. Remova o taint somente se quiser permitir que qualquer workload compativel seja agendado no Jetson:

```bash
sudo k3s kubectl taint node jetson-orin-01 workload=jetson:NoSchedule-
```

### Dividir o NVMe para os servicos

Nao cries particoes fisicas. Mantem o filesystem instalado pelo JetPack e usa diretorios/PVs locais separados, todos presos ao no `jetson-orin-01`:

| PVC | Namespace | Diretorio no Jetson | Capacidade anunciada | Uso |
|---|---|---|---:|---|
| `jetson-ai-pvc` | `ai` | `/var/lib/jetson-data/ai` | 50 GiB | Pesos dos modelos e estado/cache de IA |
| `jetson-media-config-pvc` | `media` | `/var/lib/jetson-data/media-config` | 20 GiB | Configuracao e metadata de Plex/Jellyfin |
| `jetson-transcode-pvc` | `media` | `/var/lib/jetson-data/transcode` | 30 GiB | Ficheiros temporarios de transcodificacao |

O NVMe anunciado como 256 GB tera cerca de 238 GiB utilizaveis antes do sistema. Ubuntu/JetPack, imagens de containers e logs tambem usam esse filesystem; procura manter pelo menos 20% livre. As capacidades dos PVs sao valores anunciados ao Kubernetes, nao quotas fisicas: os tres diretorios continuam a partilhar o espaco livre do mesmo SSD.

A biblioteca de filmes nao deve ser copiada para o NVMe; usa o NFS do Synology. O diretorio de transcode e apenas temporario e nao acelera o encode: o Orin Nano nao tem NVENC, portanto a codificacao H.264 usa CPU. Prioriza Direct Play e valida transcodes reais antes de os deixar competir com o LLM.

Os diretorios sao criados no passo 3.4. Os recursos do Jetson (`base/jetson/`) estao incluidos no overlay `overlays/armhf`, por isso sao aplicados pelo **Flux** como o resto do cluster: edita `base/jetson/`, corre `./update-manifests.sh`, faz push para `main`; o CI publica o artefacto OCI `armhf-latest` e o Flux aplica. Nao uses `kubectl apply -f install_jetson.yaml` (ficaria fora do GitOps); esse ficheiro e o overlay `overlays/jetson` servem apenas para inspecionar o subconjunto do Jetson.

Para forcar o Flux depois do CI terminar (no Mac, contexto `raspi`):

```bash
kubectl --context raspi -n flux-system annotate ocirepository/k3s-raspi-media-center \
  kustomization/k3s-raspi-media-center reconcile.fluxcd.io/requestedAt="$(date +%s)" --overwrite
kubectl --context raspi get pv | grep jetson
kubectl --context raspi get pvc -A | grep jetson
```

Os tres PVCs devem ficar `Bound`. O `base/jetson` declara a namespace `ai`; a namespace `media` ja e criada pelo stack atual.

Nota: no Pi usa `sudo k3s kubectl ...`; no Mac usa `kubectl --context raspi ...`. Os comandos deste guia sao equivalentes nas duas formas.

## 5. Fazer um teste controlado

Crie temporariamente `jetson-smoke.yaml` com este pod. Ele seleciona o Jetson explicitamente e tolera o taint apenas para o teste:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: jetson-smoke
spec:
  nodeSelector:
    kubernetes.io/hostname: jetson-orin-01
  tolerations:
    - key: workload
      operator: Equal
      value: jetson
      effect: NoSchedule
  restartPolicy: Never
  containers:
    - name: check
      image: busybox:1.36
      command: ["sh", "-c", "uname -m && sleep 3600"]
```

No computador com acesso ao cluster:

```bash
sudo k3s kubectl apply -f jetson-smoke.yaml
sudo k3s kubectl get pod jetson-smoke -o wide
sudo k3s kubectl exec jetson-smoke -- uname -m
sudo k3s kubectl delete -f jetson-smoke.yaml
```

O pod deve ficar `Running`, aparecer no no `jetson-orin-01` e imprimir `aarch64`. Apague o arquivo temporario depois do teste.

### Teste de GPU

Compila e corre um kernel CUDA num pod com `runtimeClassName: nvidia` (a RuntimeClass `nvidia` ja existe no k3s). A imagem `l4t-jetpack` tem cerca de 10 GB; o primeiro pull demora.

```bash
kubectl --context raspi -n default run jetson-cuda-test --restart=Never \
  --image=nvcr.io/nvidia/l4t-jetpack:r36.4.0 \
  --overrides='{"spec":{"runtimeClassName":"nvidia","nodeSelector":{"kubernetes.io/hostname":"jetson-orin-01"},"tolerations":[{"key":"workload","operator":"Equal","value":"jetson","effect":"NoSchedule"}]}}' \
  --command -- sh -c 'printf "#include <cstdio>\nint main(){cudaDeviceProp p;cudaGetDeviceProperties(&p,0);printf(\"GPU: %%s SMs=%%d CC=%%d.%%d\\\\n\",p.name,p.multiProcessorCount,p.major,p.minor);}\n" > /tmp/t.cu && /usr/local/cuda/bin/nvcc -o /tmp/t /tmp/t.cu && /tmp/t'
kubectl --context raspi -n default logs jetson-cuda-test
kubectl --context raspi -n default delete pod jetson-cuda-test
```

Resultado obtido em 2026-10-09: `GPU: Orin, SMs=8, CC=8.7`, com um kernel de teste a executar sem erro.

## 6. Integrar workloads do repositorio

O registro do no nao exige editar `install_armhf.yaml` nem aplicar novamente o stack. Esse arquivo e gerado; as alteracoes de manifests devem ser feitas em `base/` ou `overlays/` e regeneradas com `./update-manifests.sh`, conforme `AGENTS.md`.

Antes de direcionar um Deployment ao Jetson:

- Confirme que a imagem do container publica suporte a `linux/arm64`. Uma imagem marcada `arm64v8` ou um manifesto multi-arquitetura pode ser adequada; confirme a imagem/tag concreta.
- Adicione o `nodeSelector` e a toleration ao Deployment de forma deliberada. Comece com um workload de baixo risco e acompanhe `kubectl get pods -A -o wide`.
- Verifique o acesso aos PVCs. `nas-media-pvc` vem do Synology (`192.168.0.200`); `ssd-config-pvc` e `ssd-downloads-pvc` sao NFS exportados pelo Pi (`192.168.0.240`). O NVMe do Jetson nao substitui esses volumes.
- Observe CPU, memoria, temperatura e espaco do NVMe antes de mover mais servicos. O Jetson tem 8 GB de RAM compartilhada com a GPU.

O Jellyfin atualmente e um servico externo apontando para o Synology, nao um Deployment gerenciado pelo overlay. Portanto, o join do Jetson nao migra o Jellyfin. Para usar o Jetson como servidor de transcodificacao, primeiro seria necessario planejar essa migracao.

### GPU em pods

Um pod usa a GPU do Orin com tres campos: `runtimeClassName: nvidia`, toleration `workload=jetson:NoSchedule` e `nodeSelector` `kubernetes.io/hostname: jetson-orin-01`. Nao e necessario device plugin nem pedidos `nvidia.com/gpu` (a GPU integrada e exposta pelo runtime em modo CSV, montando as bibliotecas L4T do host). Usa imagens construidas para L4T r36.x / CUDA 12.6 (ex.: `nvcr.io/nvidia/l4t-jetpack:r36.4.0`, `dustynv/*:r36.4.0`, `nvcr.io/nvidia/deepstream:7.1-*-multiarch`); evita tags `cu128` ou superiores, que exigem um CUDA mais recente que o driver do JetPack 6.2.

### LLM (implantado)

`base/jetson/llm.yaml` define o servidor `llama.cpp` (`dustynv/llama_cpp:r36.4.0`) em `ai`, com Qwen2.5 1.5B Instruct Q4_K_M. Um init container descarrega o GGUF uma vez para `jetson-ai-pvc` (`/var/lib/jetson-data/ai/models`). API compativel com OpenAI no Service `llm.ai:8080` e na LAN via Traefik em `http://llm.telheira`:

```bash
curl http://llm.telheira/v1/chat/completions -H 'Content-Type: application/json' \
  -d '{"model":"qwen2.5-1.5b-instruct","messages":[{"role":"user","content":"Ola"}]}'
```

Se `llm.telheira` nao resolver no cliente, testa com `curl -H "Host: llm.telheira" http://192.168.0.240/...`. A API nao tem autenticacao: nao a exponhas no IngressRoute externo.

Medido em 2026-10-09 (MAXN SUPER, contexto 4096): 29/29 camadas na GPU, ~1,3 GiB de memoria (modelo 935 MiB + KV 112 MiB + compute 300 MiB), 22-31 tokens/s de geracao e 170-290 tokens/s de prompt, ~53 °C. RAM total usada no Jetson com o LLM: 2,3 GiB (4,9 GiB disponiveis).

Para trocar de modelo, altera `MODEL_URL`/`MODEL_FILE`, `--model` e `--alias` no `llm.yaml`. Antes de passar a Qwen2.5 3B, mede a margem com o pipeline de video ativo.

### Video: detecao de pessoas

**Cameras encontradas na LAN** (2026-10-09): `192.168.0.60`, `192.168.0.62`, `192.168.0.63`, todas TP-Link (`realm="TP-LINK IP-Camera"`), RTSP na porta 554 com autenticacao e ONVIF na porta 2020. O Synology (`192.168.0.200`) tambem expoe RTSP (Surveillance Station). URLs TP-Link: `rtsp://USER:PASS@IP:554/stream1` (principal) e `/stream2` (substream, usada pelo Jetson).

**Pipeline:** `base/jetson/people-detector.yaml` corre `deepstream-app` (`nvcr.io/nvidia/deepstream:7.1-samples-multiarch`) com o **NVIDIA PeopleNet** (ResNet34 INT8, modelo publico do NGC `nvidia/tao/peoplenet:deployable_quantized_onnx_v2.6.3`, classes `person`/`bag`/`face`; ficam ativas `person` e `face`), inferencia a cada 3 frames (`interval=2`), tracker IOU e streammux a 640x480 (resolucao nativa das substreams). O modelo e descarregado uma vez e o motor TensorRT e construido na primeira execucao (10+ min) e guardados em `/var/lib/jetson-data/ai/models/deepstream/peoplenet`. Os URLs vem do Secret `ai/camera-rtsp`; sem ele o pod fica inativo (`sleep`) e nao usa a GPU. O TrafficCamNet (amostra do DeepStream, usado no piloto) foi substituido porque falhava pessoas vistas de cima (camera `.60`).

**Supervisor (`supervisor.py` no ConfigMap):** envolve o `deepstream-app` e
- reinicia o container quando uma camera fica a 0 fps durante 3 min (`STALL_SEC`): com `uridecodebin`, uma sessao RTSP bloqueada nunca recupera sozinha;
- para o `deepstream-app` com SIGINT (no SIGTERM do pod e antes de cada reinicio, `terminationGracePeriodSeconds: 40`), para o pipeline enviar RTSP TEARDOWN; sessoes mortas ficam penduradas nas cameras TP-Link e esgotam o limite de streams;
- testa o login MQTT antes de ativar o envio (`--check-mqtt`); se o broker recusar, corre so a detecao e tenta de novo a cada 15 min (antes, uma falha MQTT deixava o pod em CrashLoop e sem detecao).

**Cameras e vistas** (snapshots de 2026-10-09): `cam60` patio visto quase na vertical (pergola ao centro); `cam62` passagem lateral entre a casa e o muro; `cam63` patio/estacionamento com sebe ao fundo e um caminho fora da propriedade no canto superior direito.

Criar o Secret (no Mac, zsh; as credenciais nao passam pelo Git nem pelo historico da shell). Utilizador e password sao codificados para URL, porque caracteres como `@ : / #` na password partem o URL e as cameras respondem `Unauthorized`:

```bash
read "CAMUSER?Utilizador RTSP: " && read -s "CAMPASS?Password RTSP: " && echo && \
U=$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=""))' "$CAMUSER") && \
P=$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=""))' "$CAMPASS") && \
kubectl --context raspi -n ai create secret generic camera-rtsp \
  --from-literal=CAM1_URL="rtsp://$U:$P@192.168.0.60:554/stream2" \
  --from-literal=CAM2_URL="rtsp://$U:$P@192.168.0.62:554/stream2" \
  --from-literal=CAM3_URL="rtsp://$U:$P@192.168.0.63:554/stream2" && \
unset CAMUSER CAMPASS U P
kubectl --context raspi -n ai delete pod -l app=people-detector
kubectl --context raspi -n ai logs -f deploy/people-detector | grep -E "Starting|PERF|ERROR"
```

Para reiniciar o detetor usa `delete pod`, nao `rollout restart`: o Flux reverte a anotacao `restartedAt` e substitui o pod uma segunda vez (o mesmo acontece com o `tailscale`).

Para testar credenciais RTSP no Mac (o `curl` do macOS nao suporta RTSP), envia um `DESCRIBE` com autenticacao Basic/Digest por socket (script Python simples) e espera `RTSP/1.0 200 OK`. As credenciais que funcionam sao as da propria camera (utilizador `admin`), nao as da conta TP-Link.

**Estado em 2026-10-09:** as tres cameras (`.60`, `.62`, `.63`) processadas a ~25 fps cada (substream H.264). **Limite de sessoes:** as cameras TP-Link aceitam poucos streams simultaneos. Com o Synology a gravar e uma stream aberta manualmente (browser/VLC/app pelo IP), o detetor consegue abrir a sessao RTSP mas nao recebe frames, sem erro (0 fps). Fecha as streams manuais e reinicia o pod (`delete pod`). As cameras `.62` e `.63` enviam tambem audio PCMA; com `type=4` (rtspsrc) uma fonte com audio pode ficar a 0 fps sem erro, por isso o pipeline usa `type=3` (uridecodebin), que ignora o audio, com `rtspt://` para forcar RTP sobre TCP (o UDP das cameras nao chega ao pod por causa do NAT da rede de pods). Com `type=3` nao ha reconexao RTSP integrada: um erro numa fonte termina o `deepstream-app` e o Kubernetes reinicia o pod.

Teste rapido de uma camera a partir do pod (deve terminar em ~2 s com `Execution ended`):

```bash
kubectl --context raspi -n ai exec deploy/people-detector -c deepstream -- bash -c \
  'timeout 20 gst-launch-1.0 rtspsrc location="$CAM2_URL" protocols=tcp ! rtph264depay ! h264parse ! nvv4l2decoder ! fakesink num-buffers=50 2>&1 | grep -E "Execution ended|ERROR"'
```

**Medicoes com o video de exemplo (720p, H.264) em 2026-10-09:**

| Cenario | Detecao | LLM | RAM total | Temperatura |
|---|---|---|---|---|
| So detecao (batch 1, todos os frames) | ~62 fps | - | - | - |
| Detecao + LLM a gerar em simultaneo | ~34 fps | 14-19 tok/s (vs ~30 sozinho) | 4,6 GiB | ~63 °C |

Tres substreams a 10-15 fps com `interval=2` ficam bem abaixo destes limites. O descodificador de hardware (`nvv4l2decoder`) processa o video de exemplo a ~490 fps, por isso nao e o gargalo.

**Armadilha conhecida:** no Jetson, o CUDA conta a page cache como memoria ocupada. Uma construcao de motor TensorRT pode falhar com `Device memory is insufficient` / `Could not find any implementation for node` mesmo com RAM "disponivel". O init container `drop-caches` (privilegiado) limpa a cache so enquanto nao existe motor. Manualmente: `sync; echo 3 | sudo tee /proc/sys/vm/drop_caches`.

**Eventos para o Home Assistant (MQTT):** com o Secret `ai/mqtt` (`MQTT_USER`, `MQTT_PASS`; opcional `MQTT_HOST`, por omissao `192.168.0.100`), o detetor publica no Mosquitto do HA, topico `jetson/people`, uma mensagem por camera por segundo (`msg-conv-frame-interval=25`), mesmo sem pessoas:

```json
{"version": "4.0", "sensorId": "cam60", "objects": ["<trackId>|left|top|right|bottom|person"]}
```

`sensorId` vem do ultimo octeto do IP da camera. No repositorio `telheira-ha`, `includes/mqtt.yaml` cria `sensor.jetson_pessoas_camNN` (contagem; indisponivel apos 30 s sem mensagens) e `includes/templates/people_detection.yaml` cria `binary_sensor.pessoa_camNN` (ocupacao, `delay_off` 10 s).

Criar o Secret (utilizador dedicado no HA, ex. `jetson`, em Definicoes > Pessoas > Utilizadores; o Mosquitto aceita utilizadores do HA):

```bash
read "MQUSER?Utilizador MQTT: " && read -s "MQPASS?Password MQTT: " && echo && \
kubectl --context raspi -n ai create secret generic mqtt \
  --from-literal=MQTT_USER="$MQUSER" --from-literal=MQTT_PASS="$MQPASS" && \
unset MQUSER MQPASS && kubectl --context raspi -n ai delete pod -l app=people-detector
```

No arranque, o log mostra `mqtt connection success; ready to send data`. Para ver as mensagens: `mosquitto_sub -h 192.168.0.100 -u USER -P PASS -t 'jetson/#' -v`.

**Home Assistant (repositorio `telheira-ha`):**
- `includes/mqtt.yaml`: `sensor.jetson_pessoas_cam60/62/63` contam so objetos `person` (as caras tambem chegam no payload); na `cam63` ignora pessoas com centro da caixa em `x > 470 e y < 70` (caminho alem da sebe). Indisponiveis apos 30 s sem mensagens.
- `includes/templates/people_detection.yaml`: `binary_sensor.pessoa_cam60/62/63` (ocupacao, `delay_off` 10 s). Nomes descritivos; os entity_ids mantem o sufixo `camNN`.
- `automations/people_detection.yaml`: notifica `notify.antonio` quando uma camera ve uma pessoa, `binary_sensor.someone_home` esta `off` e o horario da empregada nao esta ativo; no maximo um alerta a cada 5 min. Ainda sem fotografia: falta mapear cada camera Jetson para a entidade `camera.*` do HA.
- `dashboards/video.yaml`: cartao "Detecao de pessoas (Jetson)".

**Proximos passos (por ordem):**
1. **Ler as cameras atraves do Synology Surveillance Station** (RTSP em `192.168.0.200:554`) em vez de diretamente, para o Jetson deixar de contar para o limite de streams das cameras. Precisa de confirmar a partilha RTSP no Surveillance Station e de um utilizador para o Jetson.
2. **Fotografia nas notificacoes:** mapear `cam60/62/63` para `camera.entrada_*`/`camera.jardim_*` e usar `camera.snapshot` como em `automations/security.yaml`.
3. **Afinar limiares** (`pre-cluster-threshold` de `person`) e zonas com dados reais de alguns dias (falsos positivos/negativos).
4. **Reconhecimento facial:** as caras ja sao detetadas pelo PeopleNet. Falta um SGIE de embeddings (ArcFace/InsightFace em TensorRT), uma galeria local com fotografias das pessoas da casa (com o conhecimento delas) e a publicacao `pessoa conhecida/desconhecida` por MQTT. Medir memoria junto com o LLM.
5. **LLM no HA Assist (opcional):** o `llama.cpp` expoe API compativel com OpenAI, que a integracao "OpenAI Conversation" do HA nao deixa apontar para outro URL. Opcoes: integracao customizada (ex. Extended OpenAI Conversation, via HACS) ou trocar o servidor por Ollama (integracao nativa do HA; imagem `dustynv/ollama:r36.4.0`).

## 7. Verificacao final

No control plane:

```bash
sudo k3s kubectl get nodes -o wide
sudo k3s kubectl get pods -A -o wide
sudo k3s kubectl describe node jetson-orin-01
```

Considere a integracao inicial concluida quando:

- `jetson-orin-01` estiver `Ready` e com arquitetura `arm64`.
- O teste controlado executar no Jetson e retornar `aarch64`.
- Os workloads existentes continuarem nos nos esperados; nenhum pod deve passar para o Jetson sem toleration enquanto ele estiver taintado.
- O acesso aos endpoints NFS necessarios estiver disponivel antes de agendar apps que usam esses PVCs.

## Solucao de problemas

- **No ausente ou `NotReady`:** confira IP/DNS, versao do agente, token e `sudo journalctl -u k3s-agent -b --no-pager` no Jetson. Confirme que o Jetson alcanca `192.168.0.240:6443`.
- **`ImagePullBackOff` no teste ou em um app:** confirme que a tag da imagem inclui `linux/arm64`; imagens apenas `amd64` nao iniciarao no Jetson.
- **Pod preso em `ContainerCreating` ou erro de mount:** confira `nfs-common`, conectividade com `192.168.0.200` e `192.168.0.240`, exports e eventos com `kubectl describe pod`.
- **Aplicacao nao agenda no Jetson:** isso e esperado enquanto o taint estiver ativo. Adicione a toleration e o seletor ao Deployment escolhido, ou remova o taint conscientemente.

## Remover o worker

Se workloads estiverem rodando no Jetson, primeiro revise quais pods serao interrompidos e se ha replicas/PDBs. Depois, no control plane, marque o no como indisponivel e drene os workloads:

```bash
sudo k3s kubectl cordon jetson-orin-01
sudo k3s kubectl drain jetson-orin-01 --ignore-daemonsets
```

O drain pode bloquear por causa de um PodDisruptionBudget. Nao force a remocao sem entender o impacto. Se o Jetson ainda estiver isolado e sem pods de aplicacao, esta etapa nao e necessaria. Em seguida, no Jetson, pare o agente:

```bash
sudo systemctl disable --now k3s-agent
```

No `pi-master-00`:

```bash
sudo k3s kubectl delete node jetson-orin-01
```
