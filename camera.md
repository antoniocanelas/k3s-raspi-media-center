# Cameras (TP-Link VIGI)

Notes on the VIGI cameras feeding Frigate on the Jetson, their current
settings (read from the web UI of 192.168.0.60 on 2026-10-09) and the changes
we want, so they can be applied to every camera with UI automation.

## Inventory

| IP | Frigate | Name (camera) | Model | Firmware (2026-10-09) |
|---|---|---|---|---|
| 192.168.0.60 | `cam60` Geral | Geral | VIGI C340I (hw 1.0) | 2.2.1 Build 260605 |
| 192.168.0.61 | (offline, not in Frigate) | ? | ? | ? |
| 192.168.0.62 | `cam62` Entrada Porta | ? | VIGI C340 (hw V2.20) | 2.0.1 Build 231227, update in progress |
| 192.168.0.63 | `cam63` Portão | Portão | VIGI C340 (hw V2.20) | 2.2.3 Build 260624 |

- Web UI: `https://<ip>` (self-signed certificate, old TLS: curl works, Python's
  default TLS context does not).
- Video for Frigate/HA goes **RTSP** camera → go2rtc (`ai/go2rtc`, `rtsp://…:8554/camNN`
  and `camNN_hd`) → Frigate. Credentials only in the Secret `ai/camera-rtsp` (never in Git).
- ONVIF on port **2020** (WS-Security digest) works for: device info, video encoder
  settings (resolution, fps, bitrate, GovLength), OSD. It **cannot** switch H264+ off.

## Standard profile for all cameras (target)

Apply the same on .60, .62, .63 (and .61 if it comes back). Details and the
reasons are in the sections below. Items marked *(Claude)* are done over ONVIF
or in the cluster after the UI changes.

**Video** — *Camera → Stream → Video*

| # | Stream | Setting | Value |
|---|---|---|---|
| V1 | Main | Video Encoding | **H264** (not H264+, not H265) |
| V2 | Main | Resolution / Frame Rate | **2560*1440 / 15** (.62 and .63 are at 1280*720 today) |
| V3 | Main | Bit Rate Type / Image Quality / Max Bit Rate | **VBR / High / 4096** |
| V4 | Sub | Video Encoding | **H264** |
| V5 | Sub | Resolution / Frame Rate | **640*480 / 10** (today 25; Frigate uses 5) |
| V6 | Main / Sub | Keyframe interval (GovLength) | **no change needed**: with H264 the cameras send a keyframe every ~1.6 s (GovLength 25-30), measured 2026-10-10 on .60 and .63 |
| V7 | Main (and Sub) | Audio | **On on every camera** (decided 2026-10-10; today .62/.63 send audio, .60 does not). Frigate records it as AAC (`preset-record-generic-audio-aac`) and go2rtc converts it for live view. Note: CNPD guidance is restrictive on recording sound where the camera covers the street or third parties (Geral) |

**Security**

| # | Where | Setting | Value |
|---|---|---|---|
| S1 | System Settings → User Management | Dedicated stream user | add **`nvrviewer`** (Operator) for RTSP, with its own strong password; then *(Claude)* switch Secret `ai/camera-rtsp` to it and stop using `admin` for streaming. `admin` only for occasional ONVIF changes, with António's OK |
| S2 | System Settings → User Management | `admin` password | strong and unique per camera (stored outside Git) |
| S3 | Network Settings | Port Forwarding, DDNS, Openapi, SNMP, RTMP, FTP, Email, Multicast, 802.1x, Log Server | **Off** |
| S4 | Camera → Stream → Advance Settings | SRTP | **Off** |
| S5 | Network Settings → Network Service → ONVIF | ONVIF / Time Verification | **On / Off** |
| S6 | Network Settings → Platform Access | VIGI Cloud | **Off** (decided 2026-10-10): less internet exposure; no VIGI app access from outside, Home Assistant covers it |

**Camera events**

| # | Where | Setting | Value |
|---|---|---|---|
| E1 | Event → Smart Event (Human, Line Crossing, Intrusion) | Push notifications | **unchecked** (alerts come from Frigate/HA; avoids duplicates) |
| E2 | Event → Smart Event (all rules) | Send to Alarm Server | **unchecked** (no alarm server configured) |

**Consistency**

| # | Where | Setting | Value |
|---|---|---|---|
| C1 | System Settings → Firmware Update | Firmware | latest, same on all cameras |
| C2 | Information → Device Information | Device Name | **Geral** (.60) and **Portão** (.63) done 2026-10-10; **Porta** (.62) pending |
| C3 | Camera → Display → OSD | Date, Day of Week, Channel Name, Custom 1-2 | **all Off** (re-check after firmware updates) |
| C4 | System Settings → Date | Time zone / time | Lisbon (UTC±0 with DST Auto), NTP Auto, 24 h |
| C5 | Network Settings → Internet Connection | IP | Static 192.168.0.6x /24, gateway/DNS 192.168.0.1 |

**Status 2026-10-10** (verified by Claude): .60 and .63 done for V1-V5 and V7
(H264, keyframes ~1.6 s, 1440p main, sub 640x480 at 10 fps, audio on, Frigate
clips have AAC). S1 done on .60 and .63: Secret `ai/camera-rtsp` uses `nvrviewer`
(RTSP verified, Frigate at 5 fps); the admin password is no longer in the cluster
(backup Secret deleted 2026-10-10). ONVIF changes that need `admin` are done
with a password António provides at the time. Pending: everything
on .62 (offline since the firmware update; it also needs `nvrviewer` with the
same password, or cam62 stays down).

## Changes wanted

### 1. Main stream: H264+ → H264 (required)

*Settings → Camera → Stream → Video*, **Stream Type = Main Stream**:

| Field | Current (.60) | Wanted |
|---|---|---|
| Video Encoding | **H264+** | **H264** |
| Resolution | 2560*1440 | keep (2560*1440 if offered) |
| Video Frame Rate | 15 | keep 15 |
| Bit Rate Type | VBR | keep VBR |
| Image Quality | High | keep High |
| Max Bit Rate | 4096 kbps | keep 4096 |

Then **Apply** (the stream restarts for a few seconds).

Why: H264+ (smart coding) stretches the keyframe interval to 7–15 s on static
scenes and ignores the configured GOP. The browser/app cannot start live video
before a keyframe, so Porta/Portão took up to ~10 s to show live. Measured on
2026-10-09 with ffprobe: cam60 1 keyframe in 20 s, cam63 keyframes 15 s apart.
Not H265/H265+: Chrome and the HA app often cannot play H.265 live, and the
Frigate config decodes H.264 (`preset-jetson-h264`).

After the change, ONVIF `GovLength` = **30** (one keyframe every 2 s at 15 fps).
There is no GOP field in the web UI; it is set over ONVIF (done on .60, to do
on .62/.63 — ask Claude).

### 2. Sub stream: check, H264 not H264+ (required)

Same page, **Stream Type = Sub Stream**: Video Encoding **H264** (not H264+),
640*480. Frigate detects on this stream (5 fps), so the same keyframe issue
delays detection after restarts.

Optional: sub stream frame rate 25 → **10**. Frigate only uses 5 fps but the
Jetson decodes every frame it receives; 10 fps cuts that decode work by more than half.

### 3. Keep as they are (do not change)

| Where | Setting | Value | Why |
|---|---|---|---|
| Camera → Display → OSD | Display Date / Day of Week / Channel Name / Custom 1-2 | **all off** | Frigate adds its own timestamp to snapshots; an OSD date would appear twice (removed over ONVIF earlier; firmware updates may turn it back on — re-check) |
| Camera → Display → Image | Rotation / Mirror | Off | masks and zones in Frigate assume this orientation |
| Camera → Display → Image | Power Line Frequency | 50Hz | Portugal |
| Camera → Display → Image | Night Vision Mode | Custom | as set |
| Camera → Display → Privacy Mask | Privacy Mask | Off | would black out areas for Frigate too |
| Camera → Stream → ROI | ROI | Off | |
| Camera → Stream → Advance Settings | SRTP | **Off** | On encrypts RTSP and go2rtc/Frigate stop receiving video |
| Camera → Stream → Advance Settings | Video/Audio DSCP | 0 | |
| Camera → Remote Registration | Remote Registration | Off | |
| Network Settings → Internet Connection | IPv4 Mode / Address | **Static IP**, 192.168.0.6x /24, gateway and DNS 192.168.0.1 | go2rtc and the Secret use these IPs |
| Network Settings → Internet Connection | MTU | 1480 | |
| Network Settings → Port → HTTP(S) | HTTPS 443, Local Stream 8443, Video Service 8800, Digest MD5 | as is | |
| Network Settings → Port → RTSP | RTSP Port **554**, Digest **MD5** | as is | go2rtc connects with digest auth on 554 |
| System Settings | ONVIF (toggle added in fw 2.0.5) | **On** | ONVIF port 2020 is used to read/set encoder and OSD settings |
| Event → Exception Event → Access Exception | Login Error Detection On, Max Login Attempts 10 | as is | note for UI automation: 10 wrong logins lock the account for a while |

### 4. Camera's own detection: decision pending

The camera runs its own AI and sends **push notifications to the VIGI app**,
in parallel with Frigate → Home Assistant notifications.

| Event (Event → Smart Event) | State on .60 |
|---|---|
| Human Detection | **On** (area drawn over the courtyard), sensitivity 50, all-day schedule, Push notifications + Send to Alarm Server checked |
| Vehicle Detection | Off |
| Line Crossing Detection | **On** (Boundary1 around the courtyard, A<->B, human + vehicle, confidence Medium, object filter on) |
| Intrusion Detection | **On** (Area1 = courtyard, sensitivity 50, 2 %, 1 s, human only, confidence Medium) |
| Region Entering / Exiting, Object Abandoned/Removal | Off |
| Basic Event → Motion Detection | Off |
| Smart Frame (all) | Off |
| Alarm Server | none configured ("Send to Alarm Server" has no effect) |

To decide: if Frigate/HA notifications are enough, uncheck **Push notifications**
in the Smart Event rules (or turn the rules off) to avoid double alerts from the
VIGI app. Leaving them on costs nothing on the Jetson (it runs in the camera).

### 5. Other settings seen on .60 (keep, unless noted)

| Where | Setting | Value on .60 | Wanted |
|---|---|---|---|
| Network Settings → Platform Access | Platform Access Mode | VIGI Cloud VMS, *Access to VIGI Cloud Personal* On, bound to António's TP-Link ID, Connected (2026-10-09) | **Off** since 2026-10-10 (see S6) |
| Network Settings → Platform Access | Join User Experience Improvement Program | Off | keep Off |
| Network Settings → Network Service → ONVIF | Open Network Video Interface | **On** | keep On |
| Network Settings → Network Service → ONVIF | Automatically switch to static IP | On | keep |
| Network Settings → Network Service → ONVIF | Onvif Port (greyed) | 80 | keep; ONVIF also answers on **2020** (used by Claude) |
| Network Settings → Network Service → ONVIF | Time Verification | Off | keep **Off** (On rejects ONVIF requests whose timestamp drifts) |
| Network Settings → Network Service | SNMP v1/v2c/v3, RTMP, DDNS (NO-IP), 802.1x | all Off | keep Off (DDNS is done by the cluster, `telheira.duckdns.org`) |
| Network Settings → Email | Sender/SMTP | empty | keep empty |
| Network Settings → Port Forwarding | Port Forwarding (UPnP) | Off, all ports Disabled | keep **Off**: cameras must not be exposed to the internet |
| Network Settings → IP/MAC Restriction | IP/MAC Restriction | Off | keep Off (an allow list would have to include go2rtc's node and the Jetson) |
| Network Settings → Multicast | Enable Multicast | Off | keep Off |
| Network Settings → FTP Settings | Server / Upload | Off | keep Off |
| Network Settings → Openapi | Openapi | Off | **option**: TP-Link's official local API. If turned on, Claude could change these settings by API instead of the web UI — check the docs/security first |
| Network Settings → Log Server | Log Server | Off | keep Off |
| System Settings → Date | Time Zone | (UTC-00:00) Dublin, Edinburgh, Lisbon, London; DST Auto | keep (Portugal; device time matched local time) |
| System Settings → Date | Format / time source | YYYY-MM-DD, 24 hour, NTP Auto every 60 min | keep |
| System Settings → User Management | Users | `admin` (Administrator) + the TP-Link ID (Operator) + `nvrviewer` (Operator) | keep; RTSP in `ai/camera-rtsp` uses `nvrviewer`, `admin` only for ONVIF changes |
| System Settings → Certificate Management | HTTPS certificates | self-signed RSA + ECC, 2026-06-05 → 2036-06-05 | keep |

## Verification after changes (Claude)

- Keyframe interval per HD stream (should be ~2 s):
  `ffprobe -show_entries packet=pts_time,flags` on `rtsp://127.0.0.1:8554/camNN_hd`
  inside the Frigate pod.
- Frigate stats: each camera 5 fps (`/api/stats`).
- ONVIF `GetVideoEncoderConfigurations`: H264, GovLength 30, expected resolution.
- OSD: no date on the image (Frigate snapshot).
- HA dashboard *Vídeo*: live view of all three starts in ~2 s.
