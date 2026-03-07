curl -sfL https://get.k3s.io | K3S_URL=https://192.168.0.240:6443 K3S_TOKEN=K10efea1008ef746b0628c829b6811db7c9ea76dd7f01b74b60c9059e8047b6f839::server:2e67050958726fd62a9a3e955aaca477 sh -


scp pi@192.168.0.22:/etc/rancher/k3s/k3s.yaml

cat admin@192.168.0.240:/etc/rancher/k3s/k3s.yaml




# Master & workers 
## Teste se funciona e removevr
sudo mkdir -p /mnt/arr-data
sudo mount -t nfs -o nfsvers=3 192.168.0.200:/volume1/arr-data /mnt/arr-data
sudo umount /mnt/arr-data

kubectl kustomize /Users/ctw00293/other-projects/htk8s/overlays/armhf > /Users/ctw00293/other-projects/htk8s/install_armhf.yaml
kubectl apply -f /Users/ctw00293/other-projects/htk8s/install_armhf.yaml


# Main apps via Traefik
http://192.168.0.240/radarr
http://192.168.0.240/sonarr
http://192.168.0.240/jellyfin
http://192.168.0.240/prowlarr
http://192.168.0.240/argocd/


radarr sonarr prowlarr and transmission