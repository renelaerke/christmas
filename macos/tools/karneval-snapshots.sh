#!/bin/zsh
# Saves pictures of the carnival theme (Theme=5) to look at before installing: the whole scene, the float at
# several steps, the band truck and the street sweepers.
#
#   tools/karneval-snapshots.sh [OUTDIR]        (default: ../build-test/karneval, which is outside git)
#   tools/karneval-snapshots.sh "" NAME SECONDS OFRENDASECONDS [VAR=VALUE ...] [-- ARGUMENTS]    one picture
#
# CARNIVAL=2 shows the Rhineland's carnival instead of Rio's (the setting Carnival).
#
# Build first (./build.sh) and quit the installed app: only one JuleHygge runs at a time. Each picture is the
# primary screen's overlay on a dark background at 2 pixels per point (screen0.png in the run's folder), and
# beside it close-ups: NAME-ur.png (round the float), NAME-top.png (the string along the top) and NAME-bund.png
# (the bottom of the screen at full width).
set -u
cd "${0:A:h}/.."
OUT="${1:-$PWD/../build-test/karneval}"
[[ -z "$OUT" ]] && OUT="$PWD/../build-test/karneval"
BIN="$PWD/build/JuleHygge.app/Contents/MacOS/JuleHygge"
K=2
mkdir -p "$OUT"

# shot NAME SECONDS OFRENDASECONDS [VAR=VALUE ...] [-- arguments]
shot() {
  local name=$1 secs=$2 built=$3; shift 3
  local vars=()
  while (( $# > 0 )) && [[ "$1" != "--" ]]; do vars+=("$1"); shift; done
  (( $# > 0 )) && shift
  local dir="$OUT/run-$name"
  rm -rf "$dir"; mkdir -p "$dir"
  cat > "$dir/settings.ini" <<INI
FirstRun=2026-12-01
SnowmanSeenStage=12
Theme=5
OfrendaSeconds=$built
Carnival=${CARNIVAL:-1}
Santa=${SANTA:-0}
Plow=0
NisseCount=8
SnowLevel=1
INI
  env JULE_SETTINGS="$dir/settings.ini" JULE_LOG="$dir/log.txt" JULE_DEBUG=1 JULE_DEEPSNOW=1 JULE_SNAPSHOT_SCALE=$K \
    JULE_MENU_DUMP="$dir/menu.txt" "${vars[@]}" "$BIN" --snapshot="$dir",$secs "$@" >/dev/null 2>&1 &
  local pid=$!
  local n=0
  while [[ ! -f "$dir/screen0.png" && $n -lt $(( (secs + 20) * 5 )) ]]; do sleep 0.2; n=$((n + 1)); done
  sleep 0.3
  kill $pid 2>/dev/null; wait $pid 2>/dev/null
  if [[ ! -f "$dir/screen0.png" ]]; then echo "$name: intet billede (kører den installerede app?)"; return; fi
  local w=$(sips -g pixelWidth "$dir/screen0.png" | awk '/pixelWidth/ {print $2}')
  local h=$(sips -g pixelHeight "$dir/screen0.png" | awk '/pixelHeight/ {print $2}')
  # the clock stands 78 % of the way across (ScreenOverlay.renderSnowman)
  local cw=$(( 420 * K )) ch=$(( 260 * K ))
  local ox=$(( w * 78 / 100 - cw / 2 )); (( ox > w - cw )) && ox=$(( w - cw ))
  sips -c $ch $cw --cropOffset $(( h - ch )) $ox "$dir/screen0.png" --out "$OUT/$name-ur.png" >/dev/null
  sips -c $(( 110 * K )) $(( 700 * K )) --cropOffset 0 0 "$dir/screen0.png" --out "$OUT/$name-top.png" >/dev/null
  sips -c $(( 130 * K )) $w --cropOffset $(( h - 130 * K )) 0 "$dir/screen0.png" --out "$OUT/$name-bund.png" >/dev/null
  cp "$dir/screen0.png" "$OUT/$name.png"
  echo "$name -> $OUT/$name.png"
}

if (( $# > 1 )); then shift; shot "$@"; exit; fi
shot vogn-trin01 4 0
shot vogn-trin05 4 14400
shot vogn-trin09 4 28800
shot scene 6 43200
shot orkesterbil 16 43200 -- --julemand
shot gadefejere 14 43200 -- --sneplov=1
