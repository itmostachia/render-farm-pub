#!/bin/bash
# Render Remotion en la granja de GitHub Actions (no usa CPU/RAM de la PC).
# uso: bash remoto.sh <entry> <comp> <public-dir> <salida.mp4> ['<props json>'] [tramos=4]
#   MASTER=no → devuelve crudo (video + audio AAC sin loudnorm) para piezas que mezclan aparte. EXTRA='--timeout=120000' flags extra.
#   ej: bash remoto.sh src/e5-fable/index.ts Reel public-e5-fable ../out/x.mp4 '{"audio":true}' 4
# El repo es PÚBLICO (minutos gratis sin límite): paquete, tramos y final viajan cifrados con la clave
# de ~/.config/render-farm/key (la misma está como secreto FARM_KEY del repo). Nunca subir esa clave.
set -euo pipefail
REPO=itmostachia/render-farm-pub
MOTOR=${MOTOR:-C:/Projects/marca-personal-jcb/_estilos-ia-2026-10/motor}
KEY=${FARM_KEY_FILE:-$HOME/.config/render-farm/key}
ENC="-aes-256-cbc -pbkdf2 -iter 200000"
ENTRY=$1; COMP=$2; PUB=$3; OUT=$4; PROPS=${5:-'{}'}; N=${6:-4}
[ -s "$KEY" ] || { echo "[remoto] falta la clave $KEY"; exit 1; }
JOB=r$(date +%Y%m%d-%H%M%S)-$RANDOM
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
OUT=$(realpath -m "$OUT")
mkdir "$TMP/meta"
printf '%s' "$PROPS" > "$TMP/meta/props.json"
E="$ENTRY" C="$COMP" P="$PUB" X="${EXTRA:-}" F="$(cygpath -w "$TMP/meta/job.json")" python -c "import json,os;json.dump({'entry':os.environ['E'],'comp':os.environ['C'],'public':os.environ['P'],'extra':os.environ['X']},open(os.environ['F'],'w'))"
( cd "$MOTOR" && tar -czf - package.json package-lock.json remotion.config.ts tsconfig*.json src "$PUB" -C "$TMP/meta" job.json props.json ) \
  | openssl enc $ENC -salt -pass file:"$KEY" -out "$TMP/pkg.enc"
echo "[remoto] $JOB paquete cifrado $(du -h "$TMP/pkg.enc" | cut -f1)"
gh release create "$JOB" -R "$REPO" --notes "" --title "$JOB" "$TMP/pkg.enc" >/dev/null
gh workflow run render.yml -R "$REPO" -f job="$JOB" -f shards="$N" -f master="${MASTER:-si}"
ID=""
for _ in $(seq 1 30); do
  sleep 8
  ID=$(gh run list -R "$REPO" -w render.yml -L 20 --json databaseId,displayTitle -q ".[] | select(.displayTitle==\"render $JOB\") | .databaseId" | head -1)
  [ -n "$ID" ] && break
done
[ -n "$ID" ] || { echo "[remoto] no aparece el run"; exit 1; }
echo "[remoto] run https://github.com/$REPO/actions/runs/$ID"
# una consulta por minuto (gh run watch gasta varias por vuelta y con varios agentes agota las 5000/h)
while :; do
  sleep 60
  ST=$(gh run view "$ID" -R "$REPO" --json status,conclusion -q '.status+" "+.conclusion' 2>/dev/null || echo "? ")
  case "$ST" in completed\ success) break;; completed*) gh run view "$ID" -R "$REPO" --log-failed | tail -40; exit 1;; esac
done
gh run download "$ID" -R "$REPO" -n final -D "$TMP/res"
mkdir -p "$(dirname "$OUT")"
openssl enc -d $ENC -pass file:"$KEY" -in "$TMP/res/final.enc" -out "$OUT"
echo "[remoto] listo $OUT"
