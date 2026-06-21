#!/usr/bin/env bash
#
# compress-coach-videos.sh — normalize a theme's coach clips to the shipped spec.
#
# Raw exports (often H.264, ~4.5 Mbps, ~2.8 MB each) are ~15x heavier than they
# need to be. This re-encodes every .mp4 in a theme's videos/ folder to the
# compact spec the bundled themes use:
#
#   HEVC (H.265) · 664x540 · yuv420p · 24 fps · no audio · hvc1-tagged
#   ~150-205 KB per clip (a full coach set is ~9 MB)
#
# It edits files IN PLACE (encoding to a temp file, then replacing on success),
# and is safe to re-run: clips already at the target codec+size are skipped
# unless you pass FORCE=1.
#
# Usage:
#   scripts/compress-coach-videos.sh <theme-or-videos-dir> [more dirs...]
#
#   # A theme folder (its videos/ subfolder is found automatically):
#   scripts/compress-coach-videos.sh app/KochiApp/Resources/Themes/bricks
#
#   # ...or a videos folder directly, and/or several at once:
#   scripts/compress-coach-videos.sh app/KochiApp/Resources/Themes/*/videos
#
# Tunables (environment variables):
#   CRF=34     quality dial — lower = better quality + bigger file (try 33-36)
#   WIDTH=664  HEIGHT=540   target frame size
#   FORCE=1    re-encode even clips already at the target codec+size
#
# Requires ffmpeg + ffprobe:  brew install ffmpeg
#
set -euo pipefail

CRF="${CRF:-34}"
WIDTH="${WIDTH:-664}"
HEIGHT="${HEIGHT:-540}"
FORCE="${FORCE:-0}"

die() { printf 'error: %s\n' "$1" >&2; exit 1; }

command -v ffmpeg  >/dev/null 2>&1 || die "ffmpeg not found — install with: brew install ffmpeg"
command -v ffprobe >/dev/null 2>&1 || die "ffprobe not found — install with: brew install ffmpeg"

[ "$#" -ge 1 ] || die "usage: $(basename "$0") <theme-or-videos-dir> [more dirs...]"

# Resolve an argument to the videos/ folder that holds the .mp4 clips.
resolve_videos_dir() {
  local p="$1"
  if [ -d "$p/videos" ]; then
    printf '%s\n' "$p/videos"
  elif [ -d "$p" ]; then
    printf '%s\n' "$p"
  else
    die "not a directory: $p"
  fi
}

# True if the clip is already HEVC at the exact target size (nothing to gain).
already_compressed() {
  local f="$1" line
  line="$(ffprobe -v error -select_streams v:0 \
            -show_entries stream=codec_name,width,height \
            -of csv=p=0 "$f" 2>/dev/null || true)"
  [ "$line" = "hevc,${WIDTH},${HEIGHT}" ]
}

human() { # bytes -> human readable
  awk -v b="$1" 'BEGIN{ split("B KB MB GB",u); i=1; while(b>=1024&&i<4){b/=1024;i++}; printf (i==1?"%d %s":"%.1f %s"), b, u[i] }'
}

total_before=0
total_after=0
encoded=0
skipped=0

for arg in "$@"; do
  dir="$(resolve_videos_dir "$arg")"
  shopt -s nullglob
  clips=("$dir"/*.mp4)
  shopt -u nullglob
  [ "${#clips[@]}" -gt 0 ] || { printf 'no .mp4 files in %s — skipping\n' "$dir"; continue; }

  printf '\n=== %s (%d clips) ===\n' "$dir" "${#clips[@]}"
  for f in "${clips[@]}"; do
    before=$(stat -f%z "$f")
    total_before=$((total_before + before))

    if [ "$FORCE" != "1" ] && already_compressed "$f"; then
      printf '  skip  %-16s %s (already HEVC %sx%s)\n' "$(basename "$f")" "$(human "$before")" "$WIDTH" "$HEIGHT"
      total_after=$((total_after + before))
      skipped=$((skipped + 1))
      continue
    fi

    tmp="$dir/.tmp-$(basename "$f")"
    ffmpeg -y -loglevel error -i "$f" \
      -an -vf "scale=${WIDTH}:${HEIGHT}" \
      -c:v libx265 -crf "$CRF" -pix_fmt yuv420p -tag:v hvc1 \
      "$tmp"
    mv "$tmp" "$f"

    after=$(stat -f%z "$f")
    total_after=$((total_after + after))
    encoded=$((encoded + 1))
    printf '  ok    %-16s %8s -> %8s\n' "$(basename "$f")" "$(human "$before")" "$(human "$after")"
  done
done

printf '\nencoded %d, skipped %d  |  %s -> %s\n' \
  "$encoded" "$skipped" "$(human "$total_before")" "$(human "$total_after")"
