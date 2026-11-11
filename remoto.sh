#!/bin/bash
# Render Remotion en la granja de GitHub Actions (no usa CPU/RAM de la PC).
# uso: bash remoto.sh <entry> <comp> <public-dir> <salida.mp4> ['<props json>'] [tramos=4]
#   ej: bash remoto.sh src/e5-fable/index.ts Reel public-e5-fable ../out/x.mp4 '{"audio":true}' 4
# Corre desde cualquier lado; empaqueta desde el motor (MOTOR=... para otro). Devuelve el MP4 ya masterizado (-14 LUFS).
set -euo pipefail
REPO=itmostachia/render-farm-jcb
MOTOR=${MOTOR:-C:/Projects/marca-personal-jcb/_estilos-ia-2026-10/motor}
ENTRY=$1; COMP=$2; PUB=$3; OUT=$4; PROPS=${5:-'{}'}; N=${6:-4}
JOB=r$(date +%Y%m%d-%H%M%S)-$RANDOM
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
OUT=$(realpath -m "$OUT")
( cd "$MOTOR" && tar -czf "$TMP/pkg.tar.gz" package.json package-lock.json remotion.config.ts tsconfig*.json src "$PUB" )
echo "[remoto] $JOB paquete $(du -h "$TMP/pkg.tar.gz" | cut -f1)"
gh release create "$JOB" -R "$REPO" --notes "" --title "$JOB" "$TMP/pkg.tar.gz" >/dev/null
gh workflow run render.yml -R "$REPO" -f job="$JOB" -f entry="$ENTRY" -f comp="$COMP" -f public="$PUB" -f props="$PROPS" -f shards="$N"
ID=""
for _ in $(seq 1 30); do
  sleep 4
  ID=$(gh run list -R "$REPO" -w render.yml -L 20 --json databaseId,displayTitle -q ".[] | select(.displayTitle==\"render $JOB\") | .databaseId" | head -1)
  [ -n "$ID" ] && break
done
[ -n "$ID" ] || { echo "[remoto] no aparece el run"; exit 1; }
echo "[remoto] run https://github.com/$REPO/actions/runs/$ID"
gh run watch "$ID" -R "$REPO" --exit-status --interval 20 >/dev/null || { gh run view "$ID" -R "$REPO" --log-failed | tail -40; exit 1; }
gh run download "$ID" -R "$REPO" -n final -D "$TMP/res"
mkdir -p "$(dirname "$OUT")"; mv "$TMP/res/final.mp4" "$OUT"
echo "[remoto] listo $OUT"
