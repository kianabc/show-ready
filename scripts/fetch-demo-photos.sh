#!/bin/bash
# Downloads a few freely licensed house photos from Wikimedia Commons for the CI demo run.
# Usage: scripts/fetch-demo-photos.sh <dest-dir>
set -uo pipefail
DEST="${1:?destination folder}"
mkdir -p "$DEST"
UA="Showready-CI/0.1 (https://github.com/kianabc/show-ready; demo images)"
CREDITS="$DEST/../photo-credits.txt"
: > "$CREDITS"

fetch() {
  local query="$1" prefix="$2" want="$3"
  local json
  json=$(curl -sS -G "https://commons.wikimedia.org/w/api.php" -H "User-Agent: $UA" \
    --data-urlencode action=query --data-urlencode format=json \
    --data-urlencode generator=search --data-urlencode gsrnamespace=6 \
    --data-urlencode "gsrsearch=$query filetype:bitmap" --data-urlencode gsrlimit=12 \
    --data-urlencode prop=imageinfo --data-urlencode "iiprop=url|size|mime|extmetadata" \
    --data-urlencode iiurlwidth=2400) || return
  echo "$json" | jq -e . >/dev/null 2>&1 || { echo "Search failed for '$query': ${json:0:120}"; return; }
  local n=0
  while IFS=$'\t' read -r title url license artist; do
    [ "$n" -ge "$want" ] && break
    n=$((n + 1))
    local file="$DEST/${prefix}-${n}.jpg"
    if curl -sSfL -H "User-Agent: $UA" "$url" -o "$file"; then
      printf '%s: %s, %s, %s\n' "$(basename "$file")" "$title" "$license" "$artist" >> "$CREDITS"
      echo "Downloaded $(basename "$file") from $title"
    else
      rm -f "$file"; n=$((n - 1))
    fi
    sleep 1
  done < <(echo "$json" | jq -r '.query.pages // {} | to_entries[] | .value
      | select(.imageinfo[0].mime == "image/jpeg" and .imageinfo[0].width >= 1600 and .imageinfo[0].width > .imageinfo[0].height)
      | select(.title | test("drawing|design|plan|sketch|book|illustration|\\(1[0-9]{3}\\)"; "i") | not)
      | [.title, .imageinfo[0].thumburl, (.imageinfo[0].extmetadata.LicenseShortName.value // "?"),
         ((.imageinfo[0].extmetadata.Artist.value // "?") | gsub("<[^>]*>"; ""))] | @tsv')
}

fetch "living room interior house" "interior-living" 1
fetch "modern kitchen interior" "interior-kitchen" 1
fetch "single-family house front yard photograph" "exterior-front" 1
fetch "ranch style house exterior" "exterior-ranch" 1
ls -la "$DEST"
