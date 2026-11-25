#!/bin/zsh
# Saves pictures of the New Year theme (Theme=4) to look at before installing: the whole scene, the clock at
# several steps, a volley of rockets, the street sweeper, the last ten seconds and midnight itself.
#
#   tools/nytaar-snapshots.sh [OUTDIR]        (default: ../build-test/nytaar, which is outside git)
#   tools/nytaar-snapshots.sh "" NAME SECONDS OFRENDASECONDS [VAR=VALUE ...] [-- ARGUMENTS]    one picture
#
# SANTA=1 switches the rockets on in the settings (midnight needs them).
#
# Build first (./build.sh) and quit the installed app: only one JuleHygge runs at a time. Each picture is the
# primary screen's overlay on a dark background at 2 pixels per point (screen0.png in the run's folder), and
# beside it close-ups: NAME-ur.png (round the clock), NAME-top.png (the string along the top) and NAME-bund.png
# (the bottom of the screen at full width).
set -u
cd "${0:A:h}/.."
OUT="${1:-$PWD/../build-test/nytaar}"
[[ -z "$OUT" ]] && OUT="$PWD/../build-test/nytaar"
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
Theme=4
OfrendaSeconds=$built
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
shot ur-trin01 4 0
shot ur-trin04 4 10800
shot ur-trin08 4 25200
shot scene 6 43200
shot raketter 5 43200 -- --julemand
shot fejemaskine 9 43200 -- --sneplov=1
shot nedtaelling 44.5 43200 JULE_NYTAAR_OM=50
SANTA=1 shot midnat 13.5 43200 JULE_NYTAAR_OM=10
