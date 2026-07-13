#!/bin/bash
set -euo pipefail

echo "=== Sonarr fix apply & verification ==="
ROOT="/home/pi/"
REPO_PATH="/home/pi/k3s-raspi-media-center"  # adjust if you clone elsewhere on the Pi

# Apply base sonarr manifest
echo "1) Applying base Sonarr manifest"
kubectl apply -f ${REPO_PATH}/base/sonarr/ -n media || kubectl apply -f ${REPO_PATH}/base/sonarr/deployment.yaml -n media

# Restart Sonarr deployment
echo "2) Rolling restart Sonarr"
kubectl rollout restart deployment/sonarr -n media
kubectl rollout status deployment/sonarr -n media --timeout=120s

# Show pods and mounts
echo "3) Pod status"
kubectl get pods -n media -l run=sonarr -o wide

echo "4) Volume mounts for Sonarr container"
kubectl get pods -n media -l run=sonarr -o jsonpath='{.items[0].spec.containers[0].volumeMounts}' | jq . || true

# Check internal health endpoint
echo "5) Sonarr internal health"
POD=$(kubectl get pods -n media -l run=sonarr -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n media "$POD" -- curl -s -S -m 5 "http://localhost:8989/sonarr/api/health" || echo "Sonarr health curl failed"

# Check external access (from Pi's network)
echo "6) External checks (compare Radarr & Sonarr)"
curl -vk https://telheira.tplinkdns.com/sonarr -I || true
curl -vk https://telheira.tplinkdns.com/radarr -I || true

# Show Traefik routes for media namespace (external & internal)
echo "7) Traefik IngressRoute (media-external)"
kubectl get ingressroute -n media media-external -o yaml || kubectl get ingressroute -n media -o wide || true

echo "=== Done ==="
