#!/usr/bin/env zsh
emulate -L zsh
setopt errexit nounset pipefail

LIST_ID="${1:-ls024863935}"
OUT_FILE="${2:-$HOME/Downloads/${LIST_ID}.csv}"
URL="https://www.imdb.com/list/${LIST_ID}/export"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

echo "Downloading: $URL"
curl -sSL \
  -A "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36" \
  -H "Accept: text/csv,text/plain,*/*" \
  -H "Referer: https://www.imdb.com/list/${LIST_ID}/" \
  "$URL" -o "$tmp"

if [[ ! -s "$tmp" ]]; then
  echo "Download failed (empty response)."
  echo "IMDb is likely blocking non-browser requests."
  exit 1
fi

# Validate expected CSV header
if ! head -n 1 "$tmp" | grep -q "Const"; then
  echo "Downloaded content is not IMDb CSV (likely WAF challenge page)."
  echo "Open this in browser and save manually:"
  echo "  $URL"
  exit 1
fi

mv "$tmp" "$OUT_FILE"
trap - EXIT
echo "Saved CSV: $OUT_FILE"
