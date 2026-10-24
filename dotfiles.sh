#!/usr/bin/env bash
# INK · dotfiles.sh — copia .config/ y .local/ a ~ con copia de seguridad.
# Uso:  ./dotfiles.sh [--dry-run]   (--dry-run solo muestra qué haría)
# · Lo que ya existía se mueve a ~/.ink-backup-FECHA/ (nada se borra).
# · Si una carpeta de destino era un enlace simbólico (Colloid, nwg-look…), se respalda el enlace
#   y se crea una carpeta real: así nunca se modifica el tema original al que apuntaba.
set -euo pipefail
cd "$(dirname "$0")"
bak="$HOME/.ink-backup-$(date +%Y%m%d-%H%M%S)"
moved=0
DRY=0; [ "${1:-}" = "--dry-run" ] && DRY=1

backup() {   # $1 = ruta relativa a ~ (archivo o enlace)
    moved=$((moved+1))
    if [ "$DRY" = 1 ]; then echo "respaldaría  ~/$1"; return; fi
    mkdir -p "$bak/$(dirname "$1")"
    mv "$HOME/$1" "$bak/$1"
}

while IFS= read -r -d '' f; do
    rel=${f#./}
    # 1) ningún directorio intermedio puede ser un enlace simbólico
    dir=$(dirname "$rel"); acc=""
    IFS=/ read -ra parts <<< "$dir"
    for p in "${parts[@]}"; do
        acc="${acc:+$acc/}$p"
        [ -L "$HOME/$acc" ] && backup "$acc"
    done
    # 2) si ya es idéntico no se toca; si existe y es distinto (o es un enlace), se respalda
    if [ -f "$HOME/$rel" ] && [ ! -L "$HOME/$rel" ] && cmp -s "$f" "$HOME/$rel"; then continue; fi
    { [ -e "$HOME/$rel" ] || [ -L "$HOME/$rel" ]; } && backup "$rel"
    if [ "$DRY" = 1 ]; then echo "copiaría     ~/$rel"; continue; fi
    install -Dm644 "$f" "$HOME/$rel"
done < <(find .config .local -type f -print0)

if [ "$moved" -gt 0 ]; then echo "$([ "$DRY" = 1 ] && echo "Se respaldarían" || echo "Respaldo de") $moved elemento(s) en $bak"; else echo "Nada que respaldar."; fi

# --- Lanzador limpio: oculta entradas que no aportan nada (Acerca de Xfce, avisos de Thunar, etc.) ---
# Thunar arrastra libxfce4ui y con él «Acerca de Xfce». No se puede quitar sin quitar Thunar, pero sí ocultar:
# se copia el .desktop original a ~/.local/share/applications con NoDisplay=true (sigue funcionando como
# manejador de archivos; solo deja de salir en fuzzel). Para recuperar una entrada, borra su copia de ahí.
HIDE=(
    xfce4-about.desktop thunar-settings.desktop thunar-bulk-rename.desktop     # Xfce / Thunar
    foot-server.desktop footclient.desktop fish.desktop imv-dir.desktop        # duplicados de terminal, shell y visor
    avahi-discover.desktop bssh.desktop bvnc.desktop lstopo.desktop            # herramientas de red/hardware que nadie lanza
    org.qt-project.qdbusviewer.desktop org.qt-project.assistant.desktop
    org.qt-project.designer.desktop org.qt-project.linguist.desktop             # Qt Tools, si están
)
hidden=0
for id in "${HIDE[@]}"; do
    src="/usr/share/applications/$id"; dst="$HOME/.local/share/applications/$id"
    [ -f "$src" ] || continue
    [ -e "$dst" ] && continue
    hidden=$((hidden+1))
    if [ "$DRY" = 1 ]; then echo "ocultaría    $id"; continue; fi
    mkdir -p "$HOME/.local/share/applications"
    awk '/^\[Desktop Entry\]/{print; print "NoDisplay=true"; next} !/^NoDisplay=/' "$src" > "$dst"
done
[ "$hidden" -gt 0 ] && echo "$([ "$DRY" = 1 ] && echo "Se ocultarían" || echo "Ocultadas") $hidden entrada(s) del lanzador."

[ "$DRY" = 1 ] && { echo "(simulación: no se ha cambiado nada)"; exit 0; }
# Si labwc está corriendo, recarga la configuración sin cerrar la sesión
if pgrep -x labwc >/dev/null; then labwc --reconfigure && echo "✔ Dotfiles copiados y labwc recargado."
else echo "✔ Dotfiles copiados. Inicia labwc o reinicia la sesión."; fi
