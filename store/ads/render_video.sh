#!/usr/bin/env bash
# T-102 — cuts the two ad videos from the kit's PNGs, with ONE command:
#
#     bash store/ads/render_video.sh
#
# Input: the images `cd app && fvm flutter test store_ads/` wrote — the three
# angles in Meta's 9:16 and 1:1 sizes (img/<angle>-meta-1080x1920.png and
# img/<angle>-meta-1080x1080.png) and the closing cards (video/frames/).
# Output: video/entrelares-9x16.mp4 and video/entrelares-1x1.mp4 — about 24 s
# each (three angles of 7 s and a closing card of 5 s, 0.6 s crossfades),
# H.264, 30 fps, yuv420p, faststart, and NO audio track at all: no licensed
# music (owner, 04/10/2026), and a silent track would only be weight.
#
# ffmpeg comes from the PATH when there is one, otherwise from Docker (the
# owner's Windows machine has Docker Desktop and no ffmpeg) — the image is
# pinned so two runs cut the same file.
set -euo pipefail
cd "$(dirname "$0")"

FFMPEG_IMAGE="jrottenberg/ffmpeg:6.1-alpine"

run_ffmpeg() {
  if command -v ffmpeg >/dev/null 2>&1; then
    ffmpeg "$@"
  else
    # MSYS_NO_PATHCONV: Git Bash would rewrite /w into a Windows path.
    MSYS_NO_PATHCONV=1 docker run --rm -v "$(pwd -W 2>/dev/null || pwd)":/w -w /w "$FFMPEG_IMAGE" "$@"
  fi
}

ANGLE_SECONDS=7
CLOSING_SECONDS=5
FADE=0.6

render() {
  local size=$1 out=$2
  local o1 o2 o3
  o1=$(awk "BEGIN{print $ANGLE_SECONDS - $FADE}")
  o2=$(awk "BEGIN{print 2 * ($ANGLE_SECONDS - $FADE)}")
  o3=$(awk "BEGIN{print 3 * ($ANGLE_SECONDS - $FADE)}")
  for f in "img/hoje-meta-$size.png" "img/troca-meta-$size.png" "img/festas-meta-$size.png" "video/frames/fim-$size.png"; do
    [ -f "$f" ] || { echo "missing $f — run: cd app && fvm flutter test store_ads/" >&2; exit 1; }
  done
  run_ffmpeg -hide_banner -loglevel error -y \
    -loop 1 -framerate 30 -t "$ANGLE_SECONDS" -i "img/hoje-meta-$size.png" \
    -loop 1 -framerate 30 -t "$ANGLE_SECONDS" -i "img/troca-meta-$size.png" \
    -loop 1 -framerate 30 -t "$ANGLE_SECONDS" -i "img/festas-meta-$size.png" \
    -loop 1 -framerate 30 -t "$CLOSING_SECONDS" -i "video/frames/fim-$size.png" \
    -filter_complex "\
[0:v]format=yuv420p,setsar=1[v0];[1:v]format=yuv420p,setsar=1[v1];\
[2:v]format=yuv420p,setsar=1[v2];[3:v]format=yuv420p,setsar=1[v3];\
[v0][v1]xfade=transition=fade:duration=$FADE:offset=$o1[a];\
[a][v2]xfade=transition=fade:duration=$FADE:offset=$o2[b];\
[b][v3]xfade=transition=fade:duration=$FADE:offset=$o3[v]" \
    -map "[v]" -r 30 -c:v libx264 -preset slow -crf 20 -pix_fmt yuv420p \
    -movflags +faststart -an "video/$out"
  echo "video/$out"
}

mkdir -p video
render 1080x1920 entrelares-9x16.mp4
render 1080x1080 entrelares-1x1.mp4
