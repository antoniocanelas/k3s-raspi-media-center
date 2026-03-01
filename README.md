# HTK8s - Home Theater PC Stack on Kubernetes

A complete, production-ready Kubernetes deployment for a home media center stack running on Raspberry Pi and x86 systems. Includes Jellyfin, Sonarr, Radarr, Prowlarr, Bazarr, Transmission, Kavita, Lidarr, Readarr, and Jackett.

## ✨ Features

✅ **Multi-Architecture Support** - ARM64 (Raspberry Pi 4+), x86/x86_64  
✅ **GitOps Ready** - Argo CD integration with auto-sync  
✅ **NAS/NFS Integration** - 400Gi shared media storage  
✅ **Modern Kubernetes** - Traefik ingress, zero deprecation warnings  
✅ **Fully Automated** - Auto-healing, health checks, production-ready  

## 🚀 Quick Start

### Prerequisites
- Kubernetes cluster (k3s recommended for RPi)
- `kubectl` CLI
- NAS/NFS share (optional)

### Installation

**For ARM64 (Raspberry Pi):**
```bash
kubectl apply -f install_armhf.yaml
```

**For x86/x86_64:**
```bash
kubectl apply -f install_x86_64.yaml
```

**With Argo CD (GitOps):**
```bash
kubectl apply -f install_argocd.yaml
# Then update your Git repo URL in argocd/htpc-stack-application.yaml
```

**Verify deployment:**
```bash
kubectl -n htpc get pods
kubectl -n htpc get pvc

```bash
k3s kubectl get all -n htpc
```

You should get something similar to:

```bash
NAME                                READY   STATUS    RESTARTS   AGE
pod/bazarr-795f88c5c9-w75l7         1/1     Running   0          24h
pod/emby-6f457df664-fqbmc           1/1     Running   0          24h
pod/jackett-6bcf6cd8d6-lrh6j        1/1     Running   0          24h
pod/radarr-5c965c7678-zt8sq         1/1     Running   0          24h
pod/sonarr-b65c8956-mxng4           1/1     Running   0          24h
pod/transmission-5f7fdc6cb5-nrtbb   1/1     Running   0          24h

NAME                   TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
service/bazarr         ClusterIP   10.43.43.224    <none>        6767/TCP   24h
service/emby           ClusterIP   10.43.212.198   <none>        8096/TCP   24h
service/jackett        ClusterIP   10.43.104.233   <none>        9117/TCP   24h
service/radarr         ClusterIP   10.43.141.101   <none>        7878/TCP   24h
service/sonarr         ClusterIP   10.43.35.98     <none>        8989/TCP   24h
service/transmission   ClusterIP   10.43.184.198   <none>        9091/TCP   24h

NAME                           READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/bazarr         1/1     1            1           24h
deployment.apps/emby           1/1     1            1           24h
deployment.apps/jackett        1/1     1            1           24h
deployment.apps/radarr         1/1     1            1           24h
deployment.apps/sonarr         1/1     1            1           24h
deployment.apps/transmission   1/1     1            1           24h

NAME                                      DESIRED   CURRENT   READY   AGE
replicaset.apps/bazarr-795f88c5c9         1         1         1       24h
replicaset.apps/emby-6f457df664           1         1         1       24h
replicaset.apps/jackett-6bcf6cd8d6        1         1         1       24h
replicaset.apps/radarr-5c965c7678         1         1         1       24h
replicaset.apps/sonarr-b65c8956           1         1         1       24h
replicaset.apps/transmission-5f7fdc6cb5   1         1         1       24h
```

You should also be able to reach each component's UI using the links below. Don't forget to replace `localhost` with the IP or the server name running k3s.

|App|URI
|---|---
|radarr|http://localhost/radarr
|sonarr|http://localhost/sonarr
|bazarr|http://localhost/bazarr
|jacket|http://localhost/jackett
|prowlarr|http://localhost/prowlarr
|readarr|http://localhost/readarr
|transmission|http://localhost/transmission
|jellyfin|http://localhost/

Check the [ingress-route.yaml](base/ingress-route.yaml) for more details.

Each module except for Jellyfin is configured to respond on a custom basepath (check the init containers logic for more details).

## How it works (WIP)

It uses [LinuxServers](https://www.linuxserver.io/our-images/) images.

It uses a `hostPath` volume to store configuration and media files. It defaults to the `/opt/htpc` directory

```bash
/opt/htpc
├── bazarr
├── downloads
├── jellyfin
├── prowlarr
├── readarr
├── media
│   ├── movies
│   ├── books
│   └── tv
├── radarr
├── sonarr
└── transmission
```
