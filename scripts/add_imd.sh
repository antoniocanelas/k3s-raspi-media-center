#!/usr/bin/env zsh
emulate -L zsh
setopt errexit nounset pipefail

RADARR_URL="https://telheira.tplinkdns.com/radarr"
RADARR_API_KEY="4dfd60bbbf564d01aae8c0b8c0fa80fc"
CSV_FILE="${1:-$HOME/Downloads/ls024863935.csv}"
IMPORT_COUNT="${2:-30}"

ROOT_FOLDER="/movies"
QUALITY_PROFILE_ID=1
MONITORED=false
SEARCH_ON_ADD=false
MIN_AVAILABILITY="released"

for c in curl jq python3; do
  command -v "$c" >/dev/null || { echo "missing command: $c"; exit 1; }
done
[[ -f "$CSV_FILE" ]] || { echo "CSV not found: $CSV_FILE"; exit 1; }

# Fail fast on slow/unreachable endpoints
CURL_COMMON=(--connect-timeout 5 --max-time 20 -s)
PF_PID=""

cleanup() {
  if [[ -n "$PF_PID" ]]; then
    kill "$PF_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

radarr_check="$(curl "${CURL_COMMON[@]}" -H "X-Api-Key: $RADARR_API_KEY" "$RADARR_URL/api/v3/system/status" || true)"
if [[ -z "$radarr_check" ]]; then
  echo "warning: cannot reach $RADARR_URL, trying kubectl port-forward fallback..."
  if command -v kubectl >/dev/null 2>&1; then
    kubectl port-forward -n media svc/radarr 8787:7878 >/tmp/radarr-port-forward.log 2>&1 &
    PF_PID=$!
    sleep 2
    RADARR_URL="http://127.0.0.1:8787/radarr"
    radarr_check="$(curl "${CURL_COMMON[@]}" -H "X-Api-Key: $RADARR_API_KEY" "$RADARR_URL/api/v3/system/status" || true)"
  fi
fi

[[ -n "$radarr_check" ]] || { echo "error: Radarr API unreachable. Set RADARR_URL to a reachable endpoint or check /tmp/radarr-port-forward.log"; exit 1; }

top_items=("${(@f)$(python3 - "$CSV_FILE" "$IMPORT_COUNT" <<'PY'
import csv, sys
rows=[]
limit = int(sys.argv[2])
with open(sys.argv[1], newline='', encoding='utf-8-sig') as f:
    r=csv.DictReader(f)
    for row in r:
        imdb=(row.get('Const') or '').strip()
        title=(row.get('Title') or '').strip()
        votes=(row.get('Rating Votes') or row.get('Num Votes') or '0').replace(',','').strip()
        if imdb.startswith('tt'):
            try: v=int(votes)
            except: v=0
            rows.append((v, imdb, title))
rows.sort(reverse=True, key=lambda x: x[0])
for _, imdb, title in rows[:limit]:
    print(f"{imdb}\t{title}")
PY
)}")

echo "Top selected: ${#top_items[@]}"

existing="$({
  curl "${CURL_COMMON[@]}" "$RADARR_URL/api/v3/movie" -H "X-Api-Key: $RADARR_API_KEY" || true
} | jq -r '.[].imdbId // empty' | sort -u)"

[[ -n "$existing" ]] || echo "warning: could not fetch existing movies (continuing)"

added=0 skipped=0 failed=0
for item in "${top_items[@]}"; do
  imdb_id="${item%%$'\t'*}"
  movie_title="${item#*$'\t'}"

  if [[ $'\n'"$existing"$'\n' == *$'\n'"$imdb_id"$'\n'* ]]; then
    echo "skip existing: $imdb_id | $movie_title"
    ((skipped+=1))
    continue
  fi

  lookup="$(curl "${CURL_COMMON[@]}" "$RADARR_URL/api/v3/movie/lookup/imdb?imdbId=$imdb_id" -H "X-Api-Key: $RADARR_API_KEY" || true)"
  [[ -z "$lookup" || "$lookup" == "[]" || "$lookup" == "null" ]] && {
    echo "lookup failed: $imdb_id | $movie_title"
    ((failed+=1))
    continue
  }

  movie="$(echo "$lookup" | jq 'if type=="array" then .[0] else . end')"
  payload="$(echo "$movie" | jq \
    --arg root "$ROOT_FOLDER" \
    --argjson qp "$QUALITY_PROFILE_ID" \
    --arg mina "$MIN_AVAILABILITY" \
    --argjson mon "$MONITORED" \
    --argjson sea "$SEARCH_ON_ADD" \
    '{title:.title,qualityProfileId:$qp,titleSlug:.titleSlug,images:(.images//[]),tmdbId:.tmdbId,year:.year,rootFolderPath:$root,monitored:$mon,minimumAvailability:$mina,addOptions:{searchForMovie:$sea}}'
  )"

  code="$(curl "${CURL_COMMON[@]}" -o /tmp/radarr_add.json -w "%{http_code}" \
    -X POST "$RADARR_URL/api/v3/movie" \
    -H "X-Api-Key: $RADARR_API_KEY" \
    -H "Content-Type: application/json" \
    -d "$payload" || true)"

  if [[ "$code" == "201" ]]; then
    echo "added: $imdb_id | $movie_title"
    ((added+=1))
  else
    echo "failed: $imdb_id | $movie_title (http $code)"
    ((failed+=1))
  fi
done

echo "Done. added=$added skipped=$skipped failed=$failed"