ssh pi-master-00 '
sudo mkdir -p \
/ssd/downloads/incomplete \
/ssd/downloads/complete \
/ssd/databases/postgres \
/ssd/databases/grafana \
/ssd/databases/prometheus \
/ssd/config/bazarr \
/ssd/config/emby \
/ssd/config/jackett \
/ssd/config/jellyfin \
/ssd/config/kavita \
/ssd/config/lidarr \
/ssd/config/profilarr \
/ssd/config/prowlarr \
/ssd/config/qbittorrent \
/ssd/config/radarr \
/ssd/config/readarr \
/ssd/config/sonarr \
/ssd/config/transmission

sudo chown -R 1000:1000 /ssd
sudo chmod -R 775 /ssd
'

ssh pi-master-00 'ls -R /ssd'