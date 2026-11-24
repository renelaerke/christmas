#!/bin/zsh
# Saves a close-up of the children's snowman at each point of its story (SnowmanBuild.swift), to look at before
# installing: the balls being rolled and lifted, the dressing, the cheering, the snowball fight and the plow.
#
#   tools/snemand-snapshots.sh [OUTDIR]        (default: ../build-test/snemand, which is outside git)
#   tools/snemand-snapshots.sh "" NAME T[,X] SECONDS [ARGUMENTS]    one picture: start T seconds into the build (X units
#       from the left edge), save after SECONDS; e.g. "" plov 898,700 17 --sneplov=1 for the plow at the snowman
#   WIDE=420 widens the close-up (points), SPEED=30 runs the story faster, THEME=1 is autumn, DEEPSNOW=1 a full pile.
#
# Build first (./build.sh) and quit the installed app: only one JuleHygge runs at a time. Each picture is the
# primary screen's overlay on a dark background at 3 pixels per point, cropped round the place the children
# build. The app is started once per picture, JULE_SNOWMAN_START seconds into the build.
set -u
cd "${0:A:h}/.."
OUT="${1:-$PWD/../build-test/snemand}"
BIN="$PWD/build/JuleHygge.app/Contents/MacOS/JuleHygge"
K=3
mkdir -p "$OUT"
# snow on the ground, twelve nisser (so some meet the play zone), no Santa, and no plow of its own accord
cat > "$OUT/settings.ini" <<INI
FirstRun=2026-12-01
SnowmanSeenStage=12
Theme=${THEME:-0}
Santa=0
NisseCount=12
SnowLevel=1
INI

# shot NAME START SECONDS [extra arguments]: one run, one close-up
shot() {
  local name=$1 start=$2 secs=$3; shift 3
  local dir="$OUT/run-$name"
  rm -rf "$dir"; mkdir -p "$dir"
  JULE_SETTINGS="$OUT/settings.ini" JULE_LOG="$dir/log.txt" JULE_DEBUG=1 JULE_DATE=2026-12-13 JULE_DEEPSNOW=${DEEPSNOW:-0} \
    JULE_SNOWMAN_START=$start JULE_SNOWMAN_SPEED=${SPEED:-1} JULE_SNAPSHOT_SCALE=$K \
    "$BIN" --snapshot="$dir",$secs "$@" >/dev/null 2>&1 &
  local pid=$!
  local n=0
  while [[ ! -f "$dir/screen0.png" && $n -lt $(( (secs + 15) * 5 )) ]]; do sleep 0.2; n=$((n + 1)); done
  sleep 0.3
  kill $pid 2>/dev/null; wait $pid 2>/dev/null
  if [[ ! -f "$dir/screen0.png" ]]; then echo "$name: intet billede (kører den installerede app?)"; return; fi
  # where they build, from the log: logical units from the screen's left edge; the picture is K pixels per point
  local x=$(grep -o 'snowman: building at x=[0-9]*' "$dir/log.txt" | head -1 | grep -o '[0-9]*$')
  local w=$(sips -g pixelWidth "$dir/screen0.png" | awk '/pixelWidth/ {print $2}')
  local h=$(sips -g pixelHeight "$dir/screen0.png" | awk '/pixelHeight/ {print $2}')
  # S = max(0.6, screen height in points / 1080), as in ScreenOverlay
  local cx=$(awk -v x=$x -v h=$h -v k=$K 'BEGIN { s = h / k / 1080; if (s < 0.6) s = 0.6; printf "%d", x * s * k }')
  local cw=$(( ${WIDE:-330} * K )) ch=$(( 150 * K ))
  local ox=$(( cx - cw / 2 )); (( ox < 0 )) && ox=0; (( ox > w - cw )) && ox=$(( w - cw ))
  sips -c $ch $cw --cropOffset $(( h - ch )) $ox "$dir/screen0.png" --out "$OUT/$name.png" >/dev/null
  echo "$name: x=$x  $(grep -c 'nisse magic' "$dir/log.txt") magic  ->  $OUT/$name.png"
}

if (( $# > 1 )); then [[ -z "$1" ]] && OUT="$PWD/../build-test/snemand"; shift; shot "$@"; exit; fi
shot 01-bund-rulles 60 3
shot 02-to-kugler 250 3
shot 03-midten-loeftes 556 3
shot 04-hovedet-rulles 650 3
shot 05-hovedet-loeftes 750 3
shot 06-oejne-naese 805 3
shot 07-naesten-faerdig 880 3
shot 08-jubel 898 4
shot 09-sneboldkamp 898 14
