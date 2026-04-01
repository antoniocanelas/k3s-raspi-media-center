# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A Kubernetes-based home media center running on k3s, managing a full media automation stack. Uses Kustomize for manifest management with optional Argo CD GitOps integration.

**Active apps**: Sonarr, Radarr, Bazarr, qBittorrent, Prowlarr
**Disabled (commented out in `base/kustomization.yaml`)**: Readarr, Jellyfin, Lidarr, Kavita, Jackett, Transmission, Profilarr
**Infrastructure**: Cloudflared (tunnel), DDNS, Emby (external)

## Common Commands

```bash
# Regenerate install_*.yaml after any base/ or overlays/ changes (REQUIRED)
./update-manifests.sh
# or
make manifests

# Update app image versions in overlays/x86/kustomization.yaml
make upgrade-apps          # runs ./scripts/upgrade-apps.sh

# Validate manifests (YAML syntax + kubeval)
./scripts/validate.sh

# Create a release (requires clean tree + tagged commit)
make release
```

### Deploying to the cluster

```bash
# SSH access
ssh pi-master-00       # k3s master node
ssh synology           # Synology NAS

# Apply manifests
kubectl apply -f install_x86_64.yaml    # x86_64
kubectl apply -f install_armhf.yaml     # Raspberry Pi / ARM
kubectl apply -f install_argocd.yaml    # Full stack with Argo CD
```

## Architecture

### Repository Structure

- `base/` — Core Kubernetes manifests for every app; each app has its own subdirectory with `deployment.yaml`, `service.yaml`, and `kustomization.yaml`
- `overlays/x86/` — x86_64 overlay with pinned image versions
- `overlays/armhf/` — ARM/Raspberry Pi overlay (arm64v8 latest tags)
- `overlays/x86_64-with-argocd/` — Argo CD integration variant
- `argocd/` — Argo CD Application manifests and Traefik routing
- `scripts/` — Maintenance scripts (upgrade-apps, validate, check-movie-download)
- `install_*.yaml` — **Auto-generated** final manifests. **Never edit directly.**

### Key Base Manifests

| File | Purpose |
|---|---|
| `base/kustomization.yaml` | Master list of enabled apps (disabled ones are commented out) |
| `base/namespace.yaml` | `media` namespace definition |
| `base/ingress-route-external.yaml` | IngressRoute rules for externally-exposed services (HTTPS via Traefik) |
| `base/ingress-route-homeassistant-external.yaml` | Home Assistant external routing |
| `base/ingress-route-plex-external.yaml` | Plex external routing |
| `base/middlewares.yaml` | Path stripping and redirect middleware for sub-path routing |
| `base/nas-storage.yaml` | NFS PVCs for media files (Synology NAS at 192.168.0.200) |
| `base/ssd-storage.yaml` | NFS PVCs for app config and downloads (k3s master at 192.168.0.240) |
| `base/external-services.yaml` | ExternalName services for backends outside the cluster (Home Assistant, Jellyfin, Plex) |

### Storage Layout

- **Media**: NFS from Synology NAS (`192.168.0.200:/volume1/media`)
- **App config**: NFS from k3s master SSD (`192.168.0.240:/ssd/config`)
- **Downloads**: NFS from k3s master SSD (`192.168.0.240:/ssd/downloads`)

All pods run on a single node (`nodeSelector: kubernetes.io/hostname: pi-master-00`).

### Deployment Patterns

- All apps deploy to the `media` namespace
- Images are primarily from LinuxServer.io (`lscr.io/linuxserver/`)
- Init containers (busybox) bootstrap default config files on first run
- `Recreate` deployment strategy (not `RollingUpdate`) due to single-node NFS storage
- `fsGroup: 1000` on all pods for NFS permission consistency

### CI/CD

- **PR or push to `master`**: `test.yaml` validates all YAML and kustomizations via `scripts/validate.sh`
- **Push to `main`**: `push-manifests.yaml` publishes OCI artifacts to GHCR via Flux CLI
- **Monthly (1st)**: `upgrade-apps.yaml` fetches latest stable tags and opens a PR
- **Weekly**: Dependabot monitors Docker images in `overlays/` and `argocd/`

> Active development branch is `develop`; `main` is the production/release branch.

## Making Changes

1. Edit manifests in `base/` or overlays in `overlays/`
2. Run `./update-manifests.sh` to regenerate `install_*.yaml`
3. Commit both the source changes and regenerated files

To add a new app: create `base/<app>/` with `deployment.yaml`, `service.yaml`, `kustomization.yaml`, add it to `base/kustomization.yaml`, add an image entry in the appropriate overlay, add routes to `base/ingress-route-external.yaml`.
