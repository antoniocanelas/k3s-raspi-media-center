#!/usr/bin/env bash
#
# check-movie-download.sh
# Search for a movie in Radarr and verify it is downloaded to the correct path in qBittorrent.
#
# Usage:
#   ./scripts/check-movie-download.sh "Movie Title"
#
# Environment variables (all optional, sensible defaults provided):
#   RADARR_URL      - Radarr base URL        (default: http://qbittorrent.telheira/radarr)
#   RADARR_API_KEY  - Radarr API key         (auto-detected from pod if empty)
#   QB_URL          - qBittorrent base URL   (default: http://qbittorrent.telheira)
#   QB_USER         - qBittorrent username   (default: admin)
#   QB_PASS         - qBittorrent password   (default: adminadmin)
#   EXPECTED_PATH   - Expected save path     (default: /downloads/completed/radarr)
#   K8S_NAMESPACE   - Kubernetes namespace   (default: media)

set -euo pipefail

# ── Colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
ok()      { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
header()  { echo -e "\n${BOLD}$*${RESET}"; }

# ── Defaults ─────────────────────────────────────────────────────────────────
RADARR_URL="${RADARR_URL:-http://qbittorrent.telheira/radarr}"
RADARR_API_KEY="${RADARR_API_KEY:-}"
QB_URL="${QB_URL:-http://qbittorrent.telheira}"
QB_USER="${QB_USER:-admin}"
QB_PASS="${QB_PASS:-adminadmin}"
EXPECTED_PATH="${EXPECTED_PATH:-/downloads/completed/radarr}"
K8S_NAMESPACE="${K8S_NAMESPACE:-media}"

# ── Argument check ────────────────────────────────────────────────────────────
if [[ $# -lt 1 ]]; then
  echo "Usage: $0 \"Movie Title\""
  echo ""
  echo "Environment variables:"
  echo "  RADARR_URL     Radarr base URL       (default: http://qbittorrent.telheira/radarr)"
  echo "  RADARR_API_KEY Radarr API key        (auto-detected from pod if empty)"
  echo "  QB_URL         qBittorrent base URL  (default: http://qbittorrent.telheira)"
  echo "  QB_USER        qBittorrent username  (default: admin)"
  echo "  QB_PASS        qBittorrent password  (default: adminadmin)"
  echo "  EXPECTED_PATH  Expected save path    (default: /downloads/completed/radarr)"
  echo "  K8S_NAMESPACE  Kubernetes namespace  (default: media)"
  exit 1
fi

MOVIE_TITLE="$1"

# ── Dependency check ──────────────────────────────────────────────────────────
for cmd in curl jq; do
  if ! command -v "$cmd" &>/dev/null; then
    error "Required command not found: $cmd"
    exit 1
  fi
done

# ── Auto-detect Radarr API key via kubectl if not supplied ────────────────────
if [[ -z "$RADARR_API_KEY" ]]; then
  if command -v kubectl &>/dev/null; then
    info "RADARR_API_KEY not set – attempting to read from Radarr pod config..."
    RADARR_API_KEY=$(kubectl exec -n "$K8S_NAMESPACE" deploy/radarr -- \
      sh -c "sed -ne '/ApiKey/{s/.*<ApiKey>\(.*\)<\/ApiKey>.*/\1/p;q;}' /config/config.xml" 2>/dev/null || true)
  fi
  if [[ -z "$RADARR_API_KEY" ]]; then
    error "RADARR_API_KEY is not set and could not be auto-detected."
    error "Export it before running:  export RADARR_API_KEY=<your-key>"
    exit 1
  fi
  ok "Radarr API key retrieved from pod."
fi

# ── Helper: Radarr API call ───────────────────────────────────────────────────
radarr_get() {
  local path="$1"; shift
  curl -sf --max-time 10 \
    -H "X-Api-Key: ${RADARR_API_KEY}" \
    "${RADARR_URL}/api/v3${path}" "$@"
}

# ── Helper: qBittorrent API call (with session cookie) ───────────────────────
QB_COOKIE_JAR=$(mktemp)
trap 'rm -f "$QB_COOKIE_JAR"' EXIT

qb_login() {
  local resp
  resp=$(curl -sf --max-time 10 \
    -c "$QB_COOKIE_JAR" \
    --data-urlencode "username=${QB_USER}" \
    --data-urlencode "password=${QB_PASS}" \
    "${QB_URL}/api/v2/auth/login" 2>/dev/null || true)
  if [[ "$resp" != "Ok." ]]; then
    warn "qBittorrent login failed (response: '${resp}'). Torrent path check will be skipped."
    return 1
  fi
  return 0
}

qb_get() {
  local path="$1"; shift
  curl -sf --max-time 10 \
    -b "$QB_COOKIE_JAR" \
    "${QB_URL}/api/v2${path}" "$@"
}

# ═════════════════════════════════════════════════════════════════════════════
# 1. Search Radarr library
# ═════════════════════════════════════════════════════════════════════════════
header "🎬  Searching Radarr library for: \"${MOVIE_TITLE}\""

ALL_MOVIES=$(radarr_get "/movie" || true)
if [[ -z "$ALL_MOVIES" ]]; then
  error "Could not reach Radarr at ${RADARR_URL}. Check the URL and API key."
  exit 1
fi

# Case-insensitive title match
MATCHES=$(echo "$ALL_MOVIES" | jq --arg title "$MOVIE_TITLE" '
  [ .[] | select(.title | ascii_downcase | contains($title | ascii_downcase)) ]
')

MATCH_COUNT=$(echo "$MATCHES" | jq 'length')

if [[ "$MATCH_COUNT" -eq 0 ]]; then
  warn "No movie matching \"${MOVIE_TITLE}\" found in the Radarr library."

  # Offer a lookup (TMDb search) to show what Radarr *could* add
  header "🔍  Radarr TMDb lookup results for: \"${MOVIE_TITLE}\""
  LOOKUP=$(radarr_get "/movie/lookup?term=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$MOVIE_TITLE")" 2>/dev/null || true)
  if [[ -n "$LOOKUP" ]]; then
    echo "$LOOKUP" | jq -r '.[:5][] | "  • \(.title) (\(.year // "N/A"))  tmdbId=\(.tmdbId)"'
  else
    info "Lookup also returned no results."
  fi
  exit 0
fi

info "Found ${MATCH_COUNT} match(es) in library:"
echo "$MATCHES" | jq -r '.[] | "  • [\(.id)] \(.title) (\(.year))  hasFile=\(.hasFile)  monitored=\(.monitored)"'

# ═════════════════════════════════════════════════════════════════════════════
# 2. For each matched movie, show file info and check the download queue
# ═════════════════════════════════════════════════════════════════════════════
QB_AVAILABLE=false
if qb_login 2>/dev/null; then
  QB_AVAILABLE=true
fi

echo "$MATCHES" | jq -c '.[]' | while IFS= read -r MOVIE; do
  MOVIE_ID=$(echo "$MOVIE" | jq -r '.id')
  MOVIE_TITLE_EXACT=$(echo "$MOVIE" | jq -r '.title')
  MOVIE_YEAR=$(echo "$MOVIE" | jq -r '.year')
  HAS_FILE=$(echo "$MOVIE" | jq -r '.hasFile')

  header "━━  ${MOVIE_TITLE_EXACT} (${MOVIE_YEAR})  [Radarr id=${MOVIE_ID}]"

  # ── Movie file info ────────────────────────────────────────────────────────
  if [[ "$HAS_FILE" == "true" ]]; then
    FILE_PATH=$(echo "$MOVIE" | jq -r '.movieFile.path // "N/A"')
    FILE_SIZE=$(echo "$MOVIE" | jq -r '(.movieFile.size // 0) / 1073741824 | . * 100 | round / 100 | tostring + " GiB"')
    ok "File on disk: ${FILE_PATH}"
    info "File size   : ${FILE_SIZE}"
  else
    warn "No file on disk for this movie."
  fi

  # ── Check Radarr download queue ────────────────────────────────────────────
  QUEUE=$(radarr_get "/queue?movieId=${MOVIE_ID}&includeMovie=false" 2>/dev/null || true)
  QUEUE_ITEMS=$(echo "$QUEUE" | jq '[.records[]? | select(.movieId == '"$MOVIE_ID"')]' 2>/dev/null || echo "[]")
  QUEUE_COUNT=$(echo "$QUEUE_ITEMS" | jq 'length')

  if [[ "$QUEUE_COUNT" -eq 0 ]]; then
    info "No active downloads in Radarr queue for this movie."
  else
    info "Active Radarr queue entries: ${QUEUE_COUNT}"
    echo "$QUEUE_ITEMS" | jq -c '.[]' | while IFS= read -r ITEM; do
      DOWNLOAD_ID=$(echo "$ITEM" | jq -r '.downloadId // "N/A"')
      STATUS=$(echo "$ITEM" | jq -r '.status // "N/A"')
      PROTOCOL=$(echo "$ITEM" | jq -r '.protocol // "N/A"')
      TITLE=$(echo "$ITEM" | jq -r '.title // "N/A"')
      SIZE_LEFT=$(echo "$ITEM" | jq -r '(.sizeleft // 0) / 1073741824 | . * 100 | round / 100 | tostring + " GiB"')

      echo ""
      info "  Queue entry ──────────────────────────────────"
      info "  Title      : ${TITLE}"
      info "  Status     : ${STATUS}"
      info "  Protocol   : ${PROTOCOL}"
      info "  DownloadId : ${DOWNLOAD_ID}"
      info "  Size left  : ${SIZE_LEFT}"

      # ── Cross-check with qBittorrent ───────────────────────────────────────
      if [[ "$QB_AVAILABLE" == "true" && "$PROTOCOL" == "torrent" && "$DOWNLOAD_ID" != "N/A" ]]; then
        HASH=$(echo "$DOWNLOAD_ID" | tr '[:upper:]' '[:lower:]')
        TORRENT=$(qb_get "/torrents/info?hashes=${HASH}" 2>/dev/null || echo "[]")
        TORRENT_COUNT=$(echo "$TORRENT" | jq 'length')

        if [[ "$TORRENT_COUNT" -eq 0 ]]; then
          warn "  Torrent hash ${HASH} not found in qBittorrent."
        else
          QB_SAVE_PATH=$(echo "$TORRENT" | jq -r '.[0].save_path')
          QB_STATE=$(echo "$TORRENT" | jq -r '.[0].state')
          QB_PROGRESS=$(echo "$TORRENT" | jq -r '.[0].progress * 100 | . * 10 | round / 10 | tostring + "%"')
          QB_NAME=$(echo "$TORRENT" | jq -r '.[0].name')
          QB_CATEGORY=$(echo "$TORRENT" | jq -r '.[0].category // "(none)"')

          info "  ── qBittorrent ───────────────────────────────"
          info "  Name      : ${QB_NAME}"
          info "  State     : ${QB_STATE}"
          info "  Progress  : ${QB_PROGRESS}"
          info "  Category  : ${QB_CATEGORY}"
          info "  Save path : ${QB_SAVE_PATH}"
          info "  Expected  : ${EXPECTED_PATH}"

          # Normalise trailing slash for comparison
          NORM_ACTUAL="${QB_SAVE_PATH%/}"
          NORM_EXPECTED="${EXPECTED_PATH%/}"

          if [[ "$NORM_ACTUAL" == "$NORM_EXPECTED" ]]; then
            ok "  ✅  Save path is CORRECT."
          else
            error "  ❌  Save path MISMATCH!"
            error "      Got      : ${QB_SAVE_PATH}"
            error "      Expected : ${EXPECTED_PATH}"
          fi
        fi
      elif [[ "$QB_AVAILABLE" == "false" && "$PROTOCOL" == "torrent" ]]; then
        warn "  qBittorrent not reachable – skipping path verification."
      fi
    done
  fi
done




