# Image Tags & Architecture Support

This document explains the image tags used for each application and why they were chosen for different architectures.

## Architecture Support

### ARM64 (Raspberry Pi 4+, ARM64 nodes)
- Uses `arm64v8` tags from LinuxServer
- All images tested and verified working

### x86/x86_64 (Intel/AMD systems)
- Uses standard `latest` or specific version tags
- Full x86_64 compatibility

---

## Application Image Tags

### Media Server

#### Jellyfin
| Architecture | Image Tag | Reason |
|---|---|---|
| ARM64 | `lscr.io/linuxserver/jellyfin:arm64v8-latest` | Official ARM64 support |
| x86_64 | `lscr.io/linuxserver/jellyfin:10.11.5ubu2404-ls14` | Stable x86_64 version |

**Notes:**
- Jellyfin is resource-intensive on RPi; allocate 1GB+ memory
- Hardware encoding not available on ARM64

---

### *arr Applications (Sonarr, Radarr, Lidarr, Readarr)

#### Radarr & Sonarr
| Architecture | Image Tag | Reason |
|---|---|---|
| ARM64 | `linuxserver/radarr:arm64v8-latest` | Official ARM64 build |
| x86_64 | `linuxserver/radarr:6.0.4.10291-ls289` | Stable x86_64 version |

**Startup Probe:** Both have startup delays (90s for liveness, 60s for readiness) to handle slow initialization.

#### Lidarr
| Architecture | Image Tag | Reason |
|---|---|---|
| ARM64 | `lscr.io/linuxserver/lidarr:arm64v8-latest` | Official ARM64 support |
| x86_64 | `lscr.io/linuxserver/lidarr:3.1.0.4875-ls15` | Stable x86_64 version |

#### Readarr
| Architecture | Image Tag | Reason |
|---|---|---|
| ARM64 | `lscr.io/linuxserver/readarr:nightly-0.4.16.2788-ls395` | Known-good nightly build |
| x86_64 | `lscr.io/linuxserver/readarr:nightly-0.4.16.2788-ls395` | Consistent across architectures |

**Note:** Readarr uses nightly because stable releases had compatibility issues.

---

### Indexing & Management

#### Prowlarr
| Architecture | Image Tag | Reason |
|---|---|---|
| ARM64 | `linuxserver/prowlarr:arm64v8-latest` | Official ARM64 build |
| x86_64 | `linuxserver/prowlarr:2.3.0.5236-ls134` | Stable x86_64 version |

#### Bazarr (Subtitles)
| Architecture | Image Tag | Reason |
|---|---|---|
| ARM64 | `linuxserver/bazarr:arm64v8-latest` | Official ARM64 build |
| x86_64 | `linuxserver/bazarr:v1.5.3-ls329` | Stable x86_64 version |

#### Jackett (Indexer Proxy)
| Architecture | Image Tag | Reason |
|---|---|---|
| ARM64 | `linuxserver/jackett:arm64v8-latest` | Official ARM64 build |
| x86_64 | `linuxserver/jackett:v0.24.532-ls259` | Stable x86_64 version |

---

### Utilities

#### Transmission (Torrent Client)
| Architecture | Image Tag | Reason |
|---|---|---|
| ARM64 | `linuxserver/transmission:arm64v8-latest` | Official ARM64 build |
| x86_64 | `linuxserver/transmission:4.0.6-r5-ls322` | Stable x86_64 version |

#### Kavita (Comic Reader)
| Architecture | Image Tag | Reason |
|---|---|---|
| ARM64 | `lscr.io/linuxserver/kavita:arm64v8-latest` | Official ARM64 support |
| x86_64 | `lscr.io/linuxserver/kavita:v0.8.8.3-ls94` | Stable x86_64 version |

---

## Updating Image Tags

### Find New Tags
```bash
# Search LinuxServer hub for new versions
https://hub.docker.com/r/linuxserver/radarr/tags

# Check architecture-specific tags
docker pull linuxserver/radarr:arm64v8-latest --dry-run
```

### Update Kustomize Overlay

Edit `overlays/armhf/kustomization.yaml` or `overlays/x86/kustomization.yaml`:

```yaml
images:
  - name: linuxserver/radarr
    newTag: arm64v8-latest    # Change to new tag
```

### Regenerate & Apply

```bash
kubectl kustomize overlays/armhf > install_armhf.yaml
kubectl apply -f install_armhf.yaml
```

---

## Known Issues & Workarounds

### Readarr - Nightly Only
**Issue:** Stable releases have library compatibility problems  
**Solution:** Using nightly build `0.4.16.2788-ls395`  
**Status:** Working reliably, consider moving to stable in future

### Jellyfin - High Memory Usage
**Issue:** Jellyfin can consume 500MB-1GB on ARM64  
**Solution:** Set memory limits and consider disabling automatic updates  
**Status:** Monitor for crashes, restart manually if needed

### Lidarr - Slow Startup
**Issue:** Slow database initialization on first run  
**Solution:** Extended startup probe (90s)  
**Status:** Normal, subsequent starts are faster

---

## Architecture-Specific Notes

### Raspberry Pi 4 (ARM64)

**Recommended Settings:**
- Memory: Allocate at least 4GB to cluster
- CPU: Allocate 2 cores minimum per app
- Storage: Use NAS/NFS for media, local for configs

**Performance Tips:**
- Disable Jellyfin hardware encoding
- Run indexing tasks off-peak
- Monitor pod restarts for memory issues

### x86/x86_64 (Intel/AMD)

**Recommended Settings:**
- Memory: 2GB per app tier
- CPU: 1 core minimum, 2+ recommended
- Storage: Local NVMe or SSD recommended

**Performance Tips:**
- Enable hardware encoding in Jellyfin
- Use local storage for configs (faster than NFS)
- Can run multiple instances per app

---

## Future Upgrades

When upgrading images:

1. **Test in staging first** (if available)
2. **Update Kustomize overlay** with new tag
3. **Regenerate manifest**: `kubectl kustomize overlays/armhf > install_armhf.yaml`
4. **Apply changes**: `kubectl apply -f install_armhf.yaml`
5. **Monitor pods**: `kubectl -n htpc get pods -w`
6. **Check logs** if issues: `kubectl -n htpc logs deploy/radarr`

---

## Version Pinning Strategy

- **ARM64**: Use `arm64v8-latest` for auto-updates
- **x86_64**: Pin specific versions for stability
- **Readarr**: Pin nightly build (0.4.16.2788-ls395)

This provides a balance between stability and getting fixes/features.

