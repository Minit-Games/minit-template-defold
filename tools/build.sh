#!/usr/bin/env bash
# Headless HTML5 build. bob lives inside the Defold editor install; it needs the
# JDK that ships with it (the class files are newer than a system JDK 17).
#
#   tools/build.sh            # bundle to build/web
#   tools/build.sh resolve    # re-fetch library dependencies first
set -euo pipefail
cd "$(dirname "$0")/.."

# release strips print() and error logging, which is what ships. Set
# VARIANT=debug to get Lua errors and prints in the browser console while
# testing -- they are invisible otherwise, and a script that dies at init just
# looks like a black screen.
VARIANT="${VARIANT:-release}"
OUT="${OUT:-dist}"

DEFOLD="${DEFOLD:-/Applications/Defold.app/Contents/Resources}"
JAVA="$DEFOLD/packages/jdk-25+36/bin/java"
JAR=$(ls "$DEFOLD"/packages/defold-*.jar 2>/dev/null | head -1)

if [ ! -x "$JAVA" ] || [ -z "$JAR" ]; then
  echo "Defold not found under $DEFOLD - set DEFOLD=/path/to/Defold.app/Contents/Resources" >&2
  exit 1
fi

# The Minit SDK is a Defold library dependency (declared in game.project), so it
# has to be fetched before the first build -- the editor does this with
# Project > Fetch Libraries.
if [ ! -d .internal/lib ] || [ -z "$(ls -A .internal/lib 2>/dev/null)" ]; then
  echo "==> fetching library dependencies"
  "$JAVA" -Dcom.google.protobuf.use_unsafe_pre22_gencode=true -cp "$JAR" com.dynamo.bob.Bob resolve >/dev/null
fi

# --architectures wasm-web pins a single non-pthread wasm. Without it bob also
# emits a *_pthread.wasm that the loader prefers wherever SharedArrayBuffer
# exists -- and SAB needs the page served cross-origin-isolated (COOP+COEP),
# which the Minit host does not do. The pthread build would simply fail to boot.
# bob's bundled protobuf gencode predates 21.7 and prints a long vulnerability
# warning per message type. Nothing here parses untrusted protobuf -- the inputs
# are this repo's own files -- and the noise buries real build errors.
exec "$JAVA" -Dcom.google.protobuf.use_unsafe_pre22_gencode=true \
  -cp "$JAR" com.dynamo.bob.Bob \
  --platform wasm-web --architectures wasm-web \
  --variant "$VARIANT" --archive \
  --bundle-output "$OUT" \
  "$@" build bundle
