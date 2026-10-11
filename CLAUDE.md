# CLAUDE.md — k3s-raspi-media-center

Start here when opening a new session. This repo is the infrastructure of the
"Telheira" home: a k3s cluster (Raspberry Pis + a Jetson Orin Nano) deployed by
GitOps. The Home Assistant configuration lives in the sibling repo
`../telheira-ha` (see its `CLAUDE.md`). Both repos are **public**.

@AGENTS.md

## Rules (always)

- **Never print or commit secrets** (tokens, passwords, RTSP URLs with
  credentials). `service_config_backup/` and `.claude/` are gitignored. Pass
  secrets through env/Keychain, never echo them; avoid heredocs that can leak.
- **No `Co-Authored-By` / Claude attribution trailers** in commits or PRs.
- Pushing straight to `main` is fine in this repo.
- Never edit `install_*.yaml`: edit `base/`/`overlays/`, then `./update-manifests.sh`.
- Long operations the user wants to watch: open a visible macOS Terminal
  (`osascript -e 'tell application "Terminal" to do script "… | tee log"'`).
- The user writes in Portuguese (pt-PT); docs here are a mix of PT and EN.

## Hosts (LAN 192.168.0.0/24)

| Host | IP | Role / access |
|---|---|---|
| pi-master-00 (Pi 5) | 192.168.0.240 (wlan), **192.168.0.18** (eth0 = k3s InternalIP) | k3s control plane, NFS `/ssd`, Traefik (pinned here). SSH alias `pi-master-00` |
| pi-worker-01 / -02 | .241 / .242 | k3s workers |
| jetson-orin-01 | 192.168.0.250 | Orin Nano 8 GB, JetPack 6.2.1, taint `workload=jetson:NoSchedule`. SSH alias `jetson-orin-01` (passwordless sudo) |
| Home Assistant (Pi 5 8 GB, HA OS) | 192.168.0.100:8123 | **not** in the cluster. SSH alias `homeassistant` |
| Synology NAS | 192.168.0.200 | media NFS, Surveillance Station (continuous recording), backups. SSH alias `synology` |
| Cameras TP-Link VIGI | .60 Geral (`cam60`), .62 Porta (`cam62`), .63 Portão (`cam63`), .61 offline | see `camera.md` |
| Tasmota (22 devices) | see `../telheira-ha/docs/tasmota-devices.md` | |

External access: `https://telheira.duckdns.org:8123` (HA, Let's Encrypt via
`base/duckdns`), `https://telheira.tplinkdns.com` (ZeroSSL), Tailscale
`https://homeassistant.tailed34f9.ts.net`. Details: `TLS_CERTIFICATES.md`.

## Cluster access and deploy

- `kubectl --context raspi …` (API https://192.168.0.240:6443).
- Namespaces: `media` (media apps, *not* `htpc`), `ai` (Jetson workloads), `flux-system`.
- Deploy = **push to `main`** → GH Action `push-manifests` builds an OCI
  artifact → Flux `OCIRepository`/`Kustomization` `k3s-raspi-media-center`.
  Flux does not read git. To apply right away after CI finishes:
  `kubectl --context raspi -n flux-system annotate ocirepository/k3s-raspi-media-center kustomization/k3s-raspi-media-center reconcile.fluxcd.io/requestedAt="$(date +%s)" --overwrite`
- CI failures POST to an HA webhook → phone notification (`../telheira-ha/automations/ci_alerts.yaml`).
- `*.telheira` hosts don't resolve from the Mac; test with `-H "Host: x.telheira" http://192.168.0.240`.
- Traefik (`base/traefik/traefik-config.yaml`) binds 80/443/8123/32443 with
  `hostPort` on `pi-master-00` and its service is `ClusterIP` (no ServiceLB:
  klipper svclb masqueraded client IPs). HA therefore sees real client IPs
  and has `login_attempts_threshold: 5`. Traefik must stay on pi-master-00
  (the router forwards to 192.168.0.18).

## Jetson (namespace `ai`) — current state (2026-10-10)

Full guide: `JETSON_ORIN_NANO_K3S.md` (setup, history, measurements).
GPU pod recipe: `runtimeClassName: nvidia` + toleration + `nodeSelector
kubernetes.io/hostname: jetson-orin-01`; L4T r36.4 / CUDA 12.6 images.

| Workload | File | Notes |
|---|---|---|
| `llm` | `base/jetson/llm.yaml` | Ollama 0.35.1. HA uses model **`assist-jetson`** (= `qwen2.5:3b`, no mmap, ctx 8192, `num_gpu 99`, preloaded). `qwen3-jetson` (qwen3:4b-instruct) kept for a switch back. `OLLAMA_KV_CACHE_TYPE=q8_0`, `LLAMA_ARG_CACHE_RAM=0` |
| `go2rtc` | `base/jetson/go2rtc.yaml` | one RTSP session per camera; `camNN` (sub) and `camNN_hd` (main). Credentials from Secret `ai/camera-rtsp` (user `nvrviewer`) |
| `frigate` | `base/jetson/frigate.yaml` | Frigate 0.18.0 tensorrt-jp6, UI https://192.168.0.250:8971, in-cluster API `frigate.ai.svc:5000` (no auth) |
| `jetson-monitor` | `base/jetson/jetson-monitor.yaml` | MQTT discovery sensors for HA: temp, RAM, GPU, CPU, LLM, fps per camera, inference ms, `sensor.jetson_faces_pending` |
| `frigate-backup` | `base/jetson/frigate-backup.yaml` | CronJob 04:30 → Synology `raspik8sconf/frigate-backup` (14 days): DB, Face Library, config |

**Memory is the main constraint** (7.6 GB shared CPU/GPU). Budget with
everything on: ~1.1 GB free with qwen2.5 3B. With qwen3 4B + face `large` it
dropped to ~115 MB and Frigate stalled (skipped_fps ≈ camera fps). Watch
`sensor.jetson_ram_available` (HA alert < 300 MB). Benchmarks of big prompts
on the LLM can OOM the node: don't run them while Frigate is live without
checking memory first. CUDA counts page cache as used (drop caches before
TensorRT engine builds).

### Frigate facts

- Detector YOLOv7-320 TensorRT (~19 ms). YOLOv9/ONNX tried and **discarded**
  (slower, +280 MB). Don't propose it again.
- `cam62`/`cam63` detect at **1280x720 from `camNN_hd`** (roles detect+record);
  `cam60` detects on the 640x480 sub stream (`person max_area 30000`).
  Camera-level masks must be in **pixels** of the detect frame (0.18 rejects
  relative coordinates and enters safe mode).
- Zones `porta`/`portao` with `loitering_time: 20`. Records alerts/detections
  30 days with AAC audio; continuous recording stays on the Synology.
- `config.yml` is copied from the ConfigMap on each start: **UI edits are lost**
  (except Face Library and runtime toggles). A camera disabled at runtime in
  the UI stays off until `camera.turn_on` in HA or re-enabled.
- MQTT `client_id: frigate-jetson` (HA camera cards need it).

### Face recognition

- On for `cam62`/`cam63`, off for `cam60`. `model_size: large`,
  `min_area: 1600` (40x40; was 2500 until 2026-10-10 and blocked almost all
  faces), `recognition_threshold: 0.95`, `min_faces: 2`.
- Library names: `Tó`, `Du` (Dulce), `Miguel`, `André`, `Maria_José` (neighbour),
  `Augusto`, `Paula`. **No spaces** in names (use `_`). Family for automations:
  Tó, Miguel, André, Du.
- The Porta/Portão cameras are high and point down: a face is only visible
  while the person is still far, walking towards the camera; up close they
  look down. Train **only with clear, frontal faces**: tiny/angled crops in the
  library caused a neighbour to be recognized as "Du" with score 1.0.
- Training workflow: Frigate saves every attempt in Faces → Recent
  recognitions; HA reminds daily at 21:00 when `sensor.jetson_faces_pending > 0`.
  API (via `kubectl -n ai port-forward deploy/frigate 5000:5000`):
  `GET /api/faces`, `POST /api/faces/{name}/create`,
  `POST /api/faces/train/{name}/classify` (`{"training_file": …}`),
  `POST /api/faces/{name}/register` (multipart `file`; small crops fail with
  "No face was detected" → upscale).
- Mining old recordings: `../telheira-ha/tools/face_extract.py` (YuNet crops,
  data in `~/face-mining/`, never in git) + `tools/face_upload.py`.
  YuNet gives false positives on foliage/hoses: always look at crops.

## Cameras (summary; details in `camera.md`)

VIGI profile: main H264 (not H264+, which hides GOP), sub stream 10 fps, audio
on, VIGI Cloud off, names Geral/Porta/Portão, RTSP user `nvrviewer`. ONVIF on
port 2020 (WS-Security digest). Surveillance Station recordings:
`/volume1/surveillance/{Entrada,Porta,Portão}/<YYYYMMDD>AM|PM/` (ffmpeg at
`/volume1/@appstore/ffmpeg7/bin/ffmpeg7`; PCMA audio → transcode to AAC for mp4).

## Where things are documented

- `TAREFAS_A_PONDERAR.md` — backlog / open decisions (check before proposing work).
- `JETSON_ORIN_NANO_K3S.md`, `JETSON_ORIN_NANO_FIRMWARE.md` — Jetson.
- `camera.md` — camera profile and status. `TLS_CERTIFICATES.md` — certificates.
- `../telheira-ha/CLAUDE.md` — Home Assistant, notifications, Tasmota.
