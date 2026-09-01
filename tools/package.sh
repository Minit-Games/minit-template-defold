#!/usr/bin/env bash
# Build the HTML5 bundle and package the Creator Console upload ZIP.
#
#   tools/package.sh
#
# The console wants a self-contained archive whose ROOT is index.html, with
# meta.json beside it. Everything is regenerated first -- art, audio, atlas --
# so a ZIP can never contain sprites or sounds that no longer match their
# source.
set -euo pipefail
cd "$(dirname "$0")/.."

ZIP="dist/defold-minit-template.zip"
OUT="dist/Defold Minit Template"

echo "==> regenerating assets"
node tools/gen-art.mjs   | tail -2
node tools/gen-audio.mjs | tail -2
node tools/gen-music.mjs | tail -1

echo "==> checking meta.json"
node tools/check-meta.mjs

echo "==> building (release)"
rm -f "$ZIP"
./tools/build.sh >/dev/null

# meta.json and the notices must sit at the top level of the ZIP, next to
# index.html; the console reads meta.json from there to pre-fill the draft.
cp meta.json "$OUT/meta.json"
cp THIRD-PARTY-NOTICES.txt "$OUT/THIRD-PARTY-NOTICES.txt"

echo "==> packaging"
( cd "$OUT" && zip -qr "../../$ZIP" . -x '.*' -x '**/.*' )

echo "==> pre-flight"
listing=$(unzip -Z1 "$ZIP")
fail=0
for required in index.html dmloader.js meta.json THIRD-PARTY-NOTICES.txt; do
  grep -qx "$required" <<<"$listing" || { echo "MISSING at ZIP root: $required" >&2; fail=1; }
done
grep -qE '^[^/]+\.wasm$' <<<"$listing" || { echo "MISSING: a .wasm at ZIP root" >&2; fail=1; }
grep -qE '^archive/' <<<"$listing"     || { echo "MISSING: archive/ payload" >&2; fail=1; }

# A pthread build boots only on a cross-origin-isolated page. The Minit host
# sends no COOP/COEP headers, so one appearing here means --architectures was
# dropped from the build and the game would fail to start in the app.
if grep -q 'pthread' <<<"$listing"; then
  echo "FORBIDDEN: a pthread wasm is present - the host is not cross-origin isolated." >&2
  fail=1
fi

# Project sources must never ride along.
forbidden=$(grep -E '(^|/)(main|modules|render|tools|assets|web|input)/|\.lua$|\.script$|\.go$|\.atlas$|\.ttf$|\.wav$|game\.project$' <<<"$listing" || true)
if [ -n "$forbidden" ]; then
  echo "FORBIDDEN entries in ZIP:" >&2; echo "$forbidden" >&2; fail=1
fi

# The shell is ours, not Defold's default: the default one paints loader chrome
# and a "Made with Defold" link over the host's own splash.
unzip -p "$ZIP" index.html | grep -q 'Minit host shell' \
  || { echo "index.html is not our shell." >&2; fail=1; }

# The audio recovery is the reason this template exists. Losing it means a game
# that is silent in the app and fine everywhere else -- the hardest bug here to
# notice, because every local check still passes.
unzip -p "$ZIP" index.html | grep -q 'DROP-8164' \
  || { echo "index.html has lost the postMessage origin repair (DROP-8164)." >&2; fail=1; }
unzip -p "$ZIP" index.html | grep -q 'minit-audio' \
  || { echo "index.html has lost the audio recovery shim." >&2; fail=1; }

# The music is by far the largest single asset; if the conversion silently
# produced a stub, the bundle would still build and just be quiet.
music_bytes=$(stat -f%z assets/sound/music.wav)
if [ "$music_bytes" -lt 200000 ]; then
  echo "assets/sound/music.wav is only $music_bytes bytes - the conversion looks wrong." >&2
  fail=1
fi

# Platform rules forbid web storage. Defold only touches IndexedDB if the game
# calls sys.save/sys.load, which it does not - this catches a regression.
if unzip -p "$ZIP" index.html | grep -qE 'localStorage|sessionStorage'; then
  echo "index.html touches web storage, which the platform forbids." >&2
  fail=1
fi

size_bytes=$(stat -f%z "$ZIP")
if [ "$size_bytes" -gt 52428800 ]; then
  echo "ZIP is $(( size_bytes / 1048576 )) MB - over Minit's 50 MB hard limit." >&2
  fail=1
elif [ "$size_bytes" -gt 5242880 ]; then
  echo "note: ZIP is $(( size_bytes / 1048576 )) MB - over the 5 MB recommendation." >&2
fi

[ "$fail" -eq 0 ] || { echo "pre-flight failed - not shipping this" >&2; exit 1; }

echo
echo "wrote $ZIP ($(du -h "$ZIP" | cut -f1))"
unzip -l "$ZIP" | tail -n +4 | head -20
echo
echo "Upload $ZIP at https://console.minit.games"
