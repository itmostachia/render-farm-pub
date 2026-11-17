#!/bin/bash
# Trabajos de ffmpeg + Python en la granja (runner Windows, mismas rutas que la PC). No usa CPU/RAM local.
# Todo viaja cifrado con la clave de ~/.config/render-farm/key (la misma del secreto FARM_KEY). Nunca subir esa clave.
#
#   bash nube.sh base   <tag> <lista.txt>                 sube una BASE (archivos grandes que no cambian). Se sube una vez.
#   bash nube.sh correr "<tags de bases>" <tandas> <run.sh> <destino> [overlay.txt]
#                                                         empaqueta el trabajo, lo dispara, espera y baja «rev» a <destino>
#   bash nube.sh bajar  <run-id> <rev|full> <destino>     baja y descifra los resultados de una corrida
#
# lista.txt / overlay.txt: rutas RELATIVAS A C:/ (una por línea, archivos o carpetas). Allá se extraen en C:/,
# así los scripts corren sin cambios. run.sh corre en el runner; recibe FARM_SHARD y FARM_SHARDS, y deja lo liviano
# (hojas, proxies, registros) en /c/farm-out/rev y los videos finales en /c/farm-out/full.
set -euo pipefail
REPO=${FARM_REPO:-itmostachia/render-farm-pub}
KEY=${FARM_KEY_FILE:-$HOME/.config/render-farm/key}
ENC="-aes-256-cbc -pbkdf2 -iter 200000"
TMP=${NUBE_TMP:-$(mktemp -d)}
mkdir -p "$TMP"
[ -s "$KEY" ] || { echo "[nube] falta la clave"; exit 1; }
# la cuenta activa de gh puede no ser la dueña del repo: usar su token solo para estos comandos
export GH_TOKEN=${GH_TOKEN:-$(gh auth token --user "${REPO%%/*}" 2>/dev/null || gh auth token)}
w(){ cygpath -m "$1" 2>/dev/null || echo "$1"; }
cifrar(){ openssl enc $ENC -salt -pass file:"$(w "$KEY")" -out "$(w "$1")"; }

bajar(){ # <run-id> <rev|full> <destino>
  local id=$1 cual=$2 dest=$3 d="$TMP/art-$1-$2"
  rm -rf "$d"; mkdir -p "$d" "$dest"
  gh run download "$id" -R "$REPO" -p "$cual-*" -D "$d"
  find "$d" -name '*.enc' | while read -r f; do
    openssl enc -d $ENC -pass file:"$(w "$KEY")" -in "$(w "$f")" | tar -x -C "$dest" --strip-components=1
    rm "$f"
  done
  rm -rf "$d"
  echo "[nube] $cual en $dest"
}

case "${1:-}" in
base)
  TAG=$2; LISTA=$3
  tar -cf - -C /c --files-from "$LISTA" | cifrar "$TMP/$TAG.enc"
  echo "[nube] base $TAG cifrada $(du -h "$TMP/$TAG.enc" | cut -f1)"
  gh release delete "$TAG" -R "$REPO" -y --cleanup-tag >/dev/null 2>&1 || true
  gh release create "$TAG" -R "$REPO" --notes "" --title "$TAG" "$TMP/$TAG.enc" >/dev/null
  rm -f "$TMP/$TAG.enc"
  echo "[nube] base $TAG subida"
  ;;
correr)
  BASES=$2; N=$3; RUNSH=$4; DEST=$5; OVER=${6:-}
  JOB=v$(date +%Y%m%d-%H%M%S)-$RANDOM
  W="$TMP/$JOB"; mkdir -p "$W/farm-job"
  cp "$RUNSH" "$W/farm-job/run.sh"
  tar -cf "$W/job.tar" -C "$W" farm-job
  [ -n "$OVER" ] && tar -rf "$W/job.tar" -C /c --files-from "$OVER"
  cifrar "$W/job.enc" < "$W/job.tar"; rm "$W/job.tar"
  echo "[nube] $JOB trabajo cifrado $(du -h "$W/job.enc" | cut -f1)"
  gh release create "$JOB" -R "$REPO" --notes "" --title "$JOB" "$W/job.enc" >/dev/null
  rm -rf "$W"
  gh workflow run var.yml -R "$REPO" -f job="$JOB" -f bases="$BASES" -f shards="$N"
  ID=""
  for _ in $(seq 1 30); do
    sleep 8
    ID=$(gh run list -R "$REPO" -w var.yml -L 20 --json databaseId,displayTitle -q ".[] | select(.displayTitle==\"var $JOB\") | .databaseId" | head -1)
    [ -n "$ID" ] && break
  done
  [ -n "$ID" ] || { echo "[nube] no aparece la corrida"; exit 1; }
  echo "[nube] corrida $ID"
  # una consulta por minuto: la cuota de la API es compartida con otras sesiones
  while :; do
    sleep 60
    ST=$(gh run view "$ID" -R "$REPO" --json status,conclusion -q '.status+" "+.conclusion' 2>/dev/null || echo "? ")
    case "$ST" in completed*) break;; esac
  done
  echo "[nube] $ST"
  bajar "$ID" rev "$DEST" || true
  gh release delete "$JOB" -R "$REPO" -y --cleanup-tag >/dev/null 2>&1 || true
  echo "[nube] corrida $ID terminada: $ST (videos: bash nube.sh bajar $ID full <destino>)"
  case "$ST" in "completed success") ;; *) exit 1;; esac
  ;;
bajar)
  bajar "$2" "$3" "$4"
  ;;
*)
  sed -n '2,13p' "$0"; exit 1;;
esac
