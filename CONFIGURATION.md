# Media Center Configuration Guide

## Quick Access URLs

Replace `YOUR_IP` with your Raspberry Pi's IP address (e.g., `192.168.0.240`):

| Service | URL | Port |
|---------|-----|------|
| **Jellyfin** (Media Server) | `http://YOUR_IP/` | 8096 |
| **Radarr** (Movies) | `http://YOUR_IP/radarr` | 7878 |
| **Sonarr** (TV Shows) | `http://YOUR_IP/sonarr` | 8989 |
| **Lidarr** (Music) | `http://YOUR_IP/lidarr` | 8686 |
| **Readarr** (Books) | `http://YOUR_IP/readarr` | 8787 |
| **Bazarr** (Subtitles) | `http://YOUR_IP/bazarr` | 6767 |
| **Prowlarr** (Indexers) | `http://YOUR_IP/prowlarr` | 9696 |
| **Jackett** (Indexer Proxy) | `http://YOUR_IP/jackett` | 9117 |
| **Transmission** (Torrents) | `http://YOUR_IP/transmission` | 9091 |
| **Kavita** (Comics/eBooks) | `http://YOUR_IP/kavita` | 5000 |
| **Argo CD** (GitOps) | `http://YOUR_IP/argocd/` | 443 |

---

## 🎬 Step 1: Configure Jellyfin (Media Server)

**Jellyfin** is your central media server where all your media is stored and accessed.

### Initial Setup

1. Visit: `http://YOUR_IP/`
2. You'll see the Jellyfin setup wizard
3. Create your first admin account (or skip if already configured)
4. Add Media Libraries:
   - **Movies**: `/data/media/movies`
   - **TV Shows**: `/data/media/tv`
   - **Music**: `/data/media/music`
   - **Books**: `/data/media/books`
5. Verify media appears in your libraries

### NAS Folder Structure (on your Synology)

Your apps expect this structure at `/volume1/arr-data`:

```
/volume1/arr-data/
├── media/              # Organized media
│   ├── movies/         # Movies (managed by Radarr)
│   ├── tv/            # TV shows (managed by Sonarr)
│   ├── music/         # Music (managed by Lidarr)
│   └── books/         # Books/comics (managed by Readarr)
├── downloads/         # Incomplete downloads
├── radarr/           # Radarr config
├── sonarr/           # Sonarr config
├── lidarr/           # Lidarr config
├── readarr/          # Readarr config
├── bazarr/           # Bazarr config
├── jackett/          # Jackett config
├── transmission/     # Transmission config
├── prowlarr/         # Prowlarr config
├── kavita/           # Kavita config
└── downloads/        # Torrent downloads (incomplete)
```

---

## 📥 Step 2: Configure Transmission (Torrent Client)

**Transmission** is your torrent downloader. This connects to your *arr apps.

### Initial Setup

1. Visit: `http://YOUR_IP/transmission`
2. **Settings → Download Settings:**
   - Download Dir: `/data/downloads`
   - Incomplete Dir: `/data/downloads`
3. **Settings → Authentication:**
   - Set username & password (note these for Radarr/Sonarr)
4. **Default credentials:**
   - Username: `transmission`
   - Password: `transmission`

---

## 🎬 Step 3: Configure Prowlarr (Indexer Manager)

**Prowlarr** manages all your torrent indexers and syncs them to Radarr/Sonarr/Lidarr.

### Initial Setup

1. Visit: `http://YOUR_IP/prowlarr`
2. **Settings → General:**
   - Set API Key (copy this, you'll need it)
3. **Indexers:**
   - Click "Add Indexer"
   - Search for and add popular indexers (e.g., `1337x`, `RARBG`, `ThePirateBay`)
   - Note: Most are free and don't require setup
4. **Apps:**
   - Click "Settings → Apps"
   - Add Radarr, Sonarr, Lidarr connections:
     - Name: `Radarr`
     - Sync Level: `Full Sync`
     - URL: `http://radarr:7878`
     - API Key: (get from Radarr Settings)

---

## 🎥 Step 4: Configure Radarr (Movie Manager)

**Radarr** automatically downloads movies and organizes them.

### Initial Setup

1. Visit: `http://YOUR_IP/radarr`
2. **Settings → General:**
   - API Key: Copy this (needed for Prowlarr/Bazarr)
3. **Settings → Download Clients:**
   - Add Transmission:
     - Name: `Transmission`
     - Host: `transmission`
     - Port: `9091`
     - Username: `transmission`
     - Password: `transmission`
4. **Settings → Indexers:**
   - Click "Add Indexer"
   - Select "Torznab"
   - Use Prowlarr's torznab URL: `http://prowlarr:9696/1/api/v2.2/indexers/torznab/`
5. **Settings → Media Management:**
   - Root Folder: `/data/media`
   - Movie Folder Format: `{Movie Title} ({Release Year})`

### How to Add Movies

1. Click "Add Movie"
2. Search for movie title
3. Select the movie and year
4. Radarr will search indexers and download automatically

---

## 📺 Step 5: Configure Sonarr (TV Show Manager)

**Sonarr** automatically downloads TV shows and organizes them.

### Initial Setup

1. Visit: `http://YOUR_IP/sonarr`
2. **Settings → General:**
   - API Key: Copy this
3. **Settings → Download Clients:**
   - Add Transmission (same as Radarr above)
4. **Settings → Indexers:**
   - Add Prowlarr torznab URL (same as Radarr)
5. **Settings → Media Management:**
   - Root Folder: `/data/media`
   - Series Folder Format: `{Series Title} (S{season:00}E{episode:00})`

### How to Add TV Shows

1. Click "Add Series"
2. Search for show title
3. Select the show
4. Choose monitoring: "Monitor all episodes" or specific seasons
5. Sonarr will search indexers and download automatically

---

## 🎵 Step 6: Configure Lidarr (Music Manager)

Similar to Radarr/Sonarr but for music.

1. Visit: `http://YOUR_IP/lidarr`
2. Follow same setup pattern as Radarr/Sonarr
3. Root Folder: `/data/media/music`

---

## 📖 Step 7: Configure Readarr (Book Manager)

For eBooks and audiobooks.

1. Visit: `http://YOUR_IP/readarr`
2. Root Folder: `/data/media/books`

---

## 🎞️ Step 8: Configure Bazarr (Subtitle Manager)

**Bazarr** automatically downloads subtitles for your movies/TV.

### Initial Setup

1. Visit: `http://YOUR_IP/bazarr`
2. **Settings → Indexers:**
   - Add subtitle providers (e.g., OpenSubtitles, Subscene)
3. **Settings → Providers:**
   - Configure API keys if needed
4. **Settings → Sonarr/Radarr:**
   - Connect Sonarr: 
     - URL: `http://sonarr:8989`
     - API Key: (from Sonarr Settings)
   - Connect Radarr:
     - URL: `http://radarr:7878`
     - API Key: (from Radarr Settings)

### How to Get Subtitles

1. Once TV/Movie is added to Sonarr/Radarr and downloaded
2. Bazarr automatically finds and downloads subtitles
3. Check Bazarr dashboard for subtitle status

---

## 🎭 Step 9: Configure Kavita (Comic/eBook Reader)

**Kavita** reads your eBooks and comics through a web interface.

1. Visit: `http://YOUR_IP/kavita`
2. Create account
3. **Settings → Libraries:**
   - Add Library: `/data/media/books`
4. Scan for media
5. Your eBooks/comics appear in the library

---

## 🌐 Recommended Setup Order

1. **Jellyfin** - Set up your media server first
2. **Transmission** - Configure torrent client
3. **Prowlarr** - Set up indexer management
4. **Radarr** - Configure movie downloads
5. **Sonarr** - Configure TV downloads
6. **Bazarr** - Attach to Radarr/Sonarr
7. **Lidarr** - Configure music (optional)
8. **Readarr** - Configure books (optional)
9. **Kavita** - Set up comic/ebook reader

---

## 🔐 Security Tips

1. **Set strong passwords** for Transmission, Jellyfin
2. **Enable API locks** in each *arr app (Settings → General → API Key)
3. **Consider reverse proxy** with authentication if exposing outside home network
4. **Use VPN** if downloading torrents

---

## 📝 Troubleshooting

### Apps Won't Connect to Each Other
- Check URLs use service names: `http://radarr:7878` (not IP addresses)
- Verify API keys are correct
- Check pods are running: `kubectl -n media get pods`

### Transmission Not Downloading
- Check download dir exists: `/data/downloads`
- Verify Radarr/Sonarr can reach Transmission
- Check Transmission logs: `kubectl -n media logs -f deploy/transmission`

### Jellyfin Not Finding Media
- Verify media exists at correct paths
- Check permissions on NAS share
- Rescan library in Jellyfin UI

### Prowlarr Won't Sync to Radarr
- Verify Prowlarr app URL: `http://radarr:7878`
- Verify Radarr API key is correct
- Check Prowlarr app test connection

---

## 🚀 Next Steps After Configuration

1. **Add your first movie** to Radarr
2. **Add your first TV show** to Sonarr
3. **Let system download** and organize
4. **Add to Jellyfin** and watch!

---

## 📚 Documentation Links

- [Jellyfin Docs](https://jellyfin.org/docs/)
- [Radarr Docs](https://wiki.servarr.com/radarr)
- [Sonarr Docs](https://wiki.servarr.com/sonarr)
- [Transmission Docs](https://transmissionbt.com/)
- [Prowlarr Docs](https://wiki.servarr.com/prowlarr)
- [Bazarr Docs](https://www.bazarr.media/)

---

**Your media center is ready! Start with Jellyfin setup and enjoy your organized media! 🎉**

