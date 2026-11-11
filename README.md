# render-farm-jcb
Granja de renders Remotion en GitHub Actions para el motor de `marca-personal-jcb` (`_estilos-ia-2026-10/motor`).
Parte el video en N tramos que se renderizan en paralelo (cada uno en su máquina), renderiza el audio entero aparte,
une y masteriza (-14 LUFS / -1.5 dBTP, H.264 High bt709) igual que `render.sh` local. Paquetes y artifacts se borran solos.

    bash remoto.sh <entry> <comp> <public-dir> <salida.mp4> ['<props>'] [tramos]
