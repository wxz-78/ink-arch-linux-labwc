# Ink — labwc en blanco y negro

Escritorio Wayland **minimalista, ligero y redondeado**: lienzo negro, trazo blanco, cero color.
labwc + waybar + fuzzel + foot + mako. Sin servicios de systemd de usuario: todo arranca desde `labwc/autostart`.

## Estructura

```
.config/            → ~/.config        labwc, waybar, foot, fuzzel, mako, swaylock, fish, gtk, zathura, mpv, imv…
.local/share/       → ~/.local/share   tema de ventanas «Ink» y fondo de pantalla
bin/                → /usr/local/bin   osd, shot, lock, dnd, power-menu, idle-suspend
tools/              generador del fondo (gen-wallpaper.py)
1-install.sh · 2-optimize.sh · 3-privacy.sh · 4-cleanup.sh · dotfiles.sh
```

## Instalación

```bash
./1-install.sh     # paquetes (según tu hardware), greetd y scripts de apoyo (OFFICE=1 ./1-install.sh añade LibreOffice)
./dotfiles.sh      # copia .config y .local a ~ (con respaldo automático) y oculta del lanzador entradas inútiles
./2-optimize.sh    # zram, sysctl, earlyoom, fstrim, paccache (+ TLP si es portátil)
./3-privacy.sh     # DNS cifrado, MAC por red, ufw, hardening
./4-cleanup.sh     # quita wine/winetricks, toolchain huérfano y paquetes huérfanos; limpia la caché
```

`dotfiles.sh` mueve lo que ya tengas a `~/.ink-backup-FECHA/` y no escribe a través de enlaces simbólicos
(Colloid, nwg-look): si `~/.config/gtk-4.0` era un enlace, se respalda y se crea una carpeta real.
Es idempotente: lo que ya es idéntico no se toca.

Reinicia y entra por greetd. Para probar antes: ejecuta `labwc` desde un TTY.
En `labwc/environment` revisa el teclado (`latam`).

## Qué detecta `1-install.sh`

| Hardware | Qué hace |
|---|---|
| CPU Intel / AMD | instala `intel-ucode` / `amd-ucode` |
| GPU Intel / AMD | `vulkan-intel` + `intel-media-driver` / `vulkan-radeon` (+ VA-API de mesa) |
| GPU NVIDIA | no instala drivers (dependen de tu kernel): te avisa |
| Bluetooth | solo si hay controlador: `bluez`, `bluetui` y el servicio |
| Portátil (`2-optimize.sh`) | TLP; en un PC de escritorio se omite |

## Energía y pantallas

- **Inactividad:** 5 min bloquea · 5:30 apaga la pantalla (`wlopm`) · 15 min suspende **solo con batería**
  (`idle-suspend`; un PC sin batería no suspende nunca). El botón 󰅶 de waybar mantiene la pantalla encendida.
- **Monitores:** `wlr-randr` (sin argumentos) lista las salidas; hay ejemplos de escala/posición comentados en `labwc/autostart`.

## Atajos

| | |
|---|---|
| `W-Enter` terminal · `W-d` buscar apps · `W-b` Helium · `W-S-b` Helium incógnito · `W-e` yazi | `W-v` historial del portapapeles (texto e imágenes) |
| `W-q` cerrar · `W-f` maximizar · `W-m` minimizar · `W-h/j/k/l` acomodar · `W-1..4` escritorios | `W-Esc` menú de apagado · `W-S-l` bloquear |
| `Print` captura · `S-Print` área · `C-Print` área al portapapeles · `W-Print` área en swappy (anotar) | `W-n` No molestar · `W-S-n` descartar notificaciones |
| `W-Tab` / `A-Tab` cambiar ventana · `C-S-Esc` btop | `W-S-r` recargar labwc · clic derecho en el fondo: menú |

Volumen y brillo funcionan también con la pantalla bloqueada.

## Paquetes: qué cambió

**Quitado:** `librewolf-bin` (→ `helium-browser-bin`), `tumbler` (miniaturas de Thunar; añádelo si las quieres),
`pavucontrol` (GTK3 + libpulse → `wiremix`, TUI de 2 MB), `bluez` y `intel-*` solo se instalan si tu hardware los usa.
**Se quedan (decisión propia):** `noto-fonts` y `noto-fonts-cjk` (webs en CJK/árabe sin cuadritos), `deadbeef`, `yt-dlp` y `cups` (impresión).
**Añadido:** `wiremix`, `bluetui` (mezclador y Bluetooth en terminal, coherentes con `nmtui`), `pipewire-audio` y `pipewire-alsa`
(sin `pipewire-audio` el audio Bluetooth no funciona), `fd` y `ripgrep` (yazi/fzf mucho más rápidos), `pacman-contrib` (`paccache`).
**Quita `4-cleanup.sh`:** `wine` + `winetricks` (~592 MB), el toolchain que quedó huérfano (`clang`, `llvm`, `rust`, `cmake`,
`intltool`) y Qt5. No toca `cups`, `noto-fonts-cjk`, `yt-dlp` ni `deadbeef`; con `--dry-run` enseña qué haría sin tocar nada.

Helium: el comando es `helium-browser`; las opciones van en `~/.config/helium-browser-flags.conf` (ya incluye Wayland nativo).

## Lógica: mejoras de esta revisión

- **Bug de labwc corregido:** `<layout>close,iconify,max,label:</layout>` usaba `label`, que **no es un valor válido**
  (válidos: `icon menu iconify max close shade desk`). Ahora `close,iconify,max:`; el título sigue centrado.
- `lock`: un solo swaylock aunque lo pidan a la vez el atajo, el menú y swayidle. Un solo `swayidle` con `after-resume`
  y el evento `lock` (`loginctl lock-session`).
- `autostart`: cada programa se lanza solo si existe (un paquete que falte ya no rompe la sesión);
  `gsettings` corre en segundo plano y el escritorio arranca antes.
- `environment`: quitados `LIBVA_DRIVER_NAME`, `SDL_VIDEODRIVER` y `MOZ_ENABLE_WAYLAND` (autodetectados; forzarlos
  rompía juegos o no servía de nada).
- `power-menu` pide confirmación al apagar/reiniciar/cerrar sesión; `osd` no hace nada en un PC sin brillo regulable.
- `2-optimize.sh`: TLP solo en portátiles; earlyoom protege al escritorio; BBR+fq si el kernel lo trae;
  `paccache.timer`; sincronización de hora; sin esperar a `NetworkManager-wait-online` en el arranque.
- `3-privacy.sh`: NetworkManager delega el DNS en systemd-resolved también si solo ejecutas el módulo `dns`;
  ufw se activa y arranca en el orden correcto.
- `1-install.sh`: servicios de usuario con `systemctl --global`; `chsh` solo si hace falta.

## Estética: qué cambió

- **waybar flotante:** tres «islas» translúcidas con esquinas de 18 px (izquierda · reloj · estado) en lugar de una barra pegada al borde;
  nuevos módulos *pantalla siempre encendida*, *No molestar* y *brillo*; los estados activos se invierten (papel sobre tinta).
- **mako, fuzzel, tema de ventanas:** márgenes y rellenos más amplios, bordes más suaves; clic izquierdo invoca, central descarta todo, derecho descarta.
- **zathura, mpv, imv:** ahora también en escala de grises (antes tenían los colores por defecto).
- **fish:** fzf redondeado en grises, `man` coloreado con bat, abreviaturas de git; fastfetch solo en la primera shell.

## Auditoría (revisión 3): errores corregidos

- **`osd`:** el volumen se truncaba (0.29 → 28 %); ahora redondea (29 %).
- **`idle-suspend` y `2-optimize.sh`:** una batería de ratón, teclado o mando (`scope=Device`) hacía creer que un PC de escritorio era portátil
  (suspendía por inactividad e instalaba TLP). Ahora se ignoran. Además, un cargador USB-C cuenta como corriente (antes solo `Mains`).
- **`1-install.sh`:** `systemctl enable greetd` abortaba el script si ya había sddm/gdm/lightdm habilitado; ahora usa `--force`.
- **`mako`:** las notificaciones se dibujaban encima de la isla derecha de waybar; el margen superior ahora la respeta.
- **`3-privacy.sh`:** cambiar `dns=` en NetworkManager requiere reiniciarlo, no recargarlo.
- **`2-optimize.sh`:** `ParallelDownloads` y `Color` se aplican antes de instalar paquetes (antes solo valían para la siguiente vez).

## Mejoras (revisión 4)

- **Qt en oscuro:** `QT_STYLE_OVERRIDE=Adwaita-Dark` + `adwaita-qt6` (repos oficiales o, si no está, AUR).
- **Paquetes que faltaban:** `man-db` y `man-pages` (el `MANPAGER` de fish usa `man`, que no viene en la base de Arch) y `sof-firmware`
  en CPUs Intel (sin él, muchos portátiles recientes no tienen sonido).
- **Instalación robusta:** `wlopm`, `bluetui` y `adwaita-qt6` van a los repos si existen y al AUR si no, en vez de abortar todo `pacman -S`.
- **Teclas multimedia:** play/pausa, siguiente y anterior con `playerctl` (también con la pantalla bloqueada).
- **`dotfiles.sh`:** `--dry-run` muestra qué copiaría y qué respaldaría sin tocar nada; si labwc está abierto, se recarga solo.
  Probado con un HOME falso, incluido el caso de `~/.config` como enlace simbólico.

## Optimización (revisión 5)

- **`osd`:** lee el volumen con una sola llamada a `wpctl` (antes dos por cada pulsación de tecla).
- **Limpieza:** se elimina `tools/__pycache__` del paquete.
- Revisado y sin cambios: waybar no sondea nada costoso (módulos por eventos o cada 60 s), el arranque ya lanza todo en segundo plano y no hay servicios de usuario residentes.

## swappy (revisión 6)

- `W-Print` selecciona un área y la abre en **swappy** para dibujar, poner texto o difuminar; al guardar o copiar se cierra solo (`early_exit`).
- `.config/swappy/config` guarda en Imágenes con el mismo nombre que el resto de capturas (`captura-AAAAMMDD-HHMMSS.png`).
- `1-install.sh` instala `swappy` (repos o AUR). Si falta, `shot edit` avisa con una notificación en vez de fallar en silencio.

Validado: `bash -n`/`sh -n` en todos los scripts, `xmllint` en `rc.xml` y `menu.xml`, JSON de waybar y que ningún color sea distinto de gris.

## Revisión 7 (2026-10-21)

- **BPF sin privilegios:** `kernel.unprivileged_bpf_disabled` pasa de 1 a 0. Con 1, el sandbox de V8 de Helium/Chromium no arranca.
- **`dnd`:** waybar solo atiende SIGUSR1/SIGUSR2/SIGINT, así que `SIGRTMIN+8` se ignoraba y el indicador «No molestar» se quedaba viejo.
  Ahora usa `SIGUSR2`: waybar recarga el panel y vuelve a ejecutar el módulo «once» que lee el estado de mako.
- **swappy:** `save_dir` apuntaba a `$HOME/Pictures`, carpeta aparte de la que usa `shot`. Ahora `shot edit` fija la ruta real de
  Imágenes (`xdg-user-dir PICTURES`) en el config de swappy antes de abrirlo, y el valor del repo es `~/Pictures`.
- **DNS:** `DOT_MODE` pasa a `opportunistic` por defecto (el DoT estricto no deja pasar los portales cautivos de hotel o café)
  y `FallbackDNS` deja de estar vacío. `DOT_MODE`/`MAC_MODE` viajan como argumentos al reinvocar con sudo: sudoers aplica
  `env_reset` y `sudo -E` los perdía sin avisar.
- **earlyoom:** `-m 10 -s 10` (avisa al bajar del 10 %) y `--ignore` para el escritorio: nunca mata labwc, waybar, mako,
  la terminal ni systemd; sacrifica otra aplicación antes.
- **`tcp_rfc1337=0`:** con 1 se congela el socket al recibir un FIN antes de tiempo, lo que rompe proxies y VPN.
- **`4-cleanup.sh`:** wine/winetricks, toolchain huérfano y Qt5; `paccache -rk2` deja 2 versiones de cada paquete en la caché.
- **Fondo:** el autostart usa `4.jpeg` y cae a `ink.png` si no lo encuentra.

## Revisión 8 (2026-10-22)

- **`4-cleanup.sh` protege lo intocable *antes* de quitar nada:** `pacman -Rns` arrastra las dependencias que nadie más necesita; si `cups`
  (o `libcups`) estaba instalado solo como dependencia de `wine`, habría caído con él y el aviso final llegaba tarde. Ahora, si alguno de
  `KEEP` está en la cascada, se marca como explícito (`pacman -D --asexplicit`) y se salva. `--dry-run` lo avisa sin tocar nada.
- **`4-cleanup.sh`, comprobación final:** compara con lo que había instalado al empezar (antes avisaba «ya no están instalados: deadbeef»
  aunque nunca lo hubieras tenido). La lectura de «Required By» ya no depende del idioma del sistema, y `--help` no imprime `set -euo pipefail`.
- **`earlyoom`:** al sobrescribir `/etc/default/earlyoom` se perdía el intervalo de informes (por defecto, uno por segundo en el journal).
  Añadido `-r 3600`.
- **fish:** el último comando de `config.fish` dejaba `$status` en 1 en shells anidadas y el primer prompt salía con ○. Ahora es un `if`.
- **Repo:** eliminadas dos copias `*.bak-2026…` (`labwc/autostart`, `swappy/config`) que `dotfiles.sh` copiaba a tu `~/.config`.

## Revisión 9 (2026-10-24) — limpieza y correcciones

- **Bug de Qt corregido:** `QT_STYLE_OVERRIDE` valía `Phinger-Cursors-Dark` (un nombre de cursor, no de estilo Qt), así que las apps Qt
  nunca salían en oscuro. Ahora es `Adwaita-Dark` (paquete `adwaita-qt6`).
- **Cursor coherente:** el tema se llamaba distinto en `environment` (`Phinger-Cursors-Dark`, que no existe en el AUR), en GTK y en
  `gsettings` (`Adwaita`). Ahora los cuatro sitios usan `phinger-cursors-light` (cursor claro, el que se ve sobre fondo negro).
  Si prefieres el oscuro, cambia a `phinger-cursors` en `environment`, `gtk-3.0`, `gtk-4.0` y `autostart`.
- **Lanzador sin ruido:** `dotfiles.sh` oculta de fuzzel «Acerca de Xfce» (viene con Thunar), «Preferencias de Thunar», «Renombrar en lote»,
  `foot-server`/`footclient`, `fish`, `imv-dir`, herramientas de Avahi/hwloc y las de Qt Tools. No borra nada: copia el `.desktop` a
  `~/.local/share/applications/` con `NoDisplay=true`; para recuperar una entrada, borra su copia ahí.
- **LibreOffice ya no se instala por defecto** (>1 GB); se añade con `OFFICE=1 ./1-install.sh`.
- **`4-cleanup.sh`:** nuevo paso que quita paquetes huérfanos (con confirmación; lo protegido en `KEEP` nunca cae), `pavucontrol`
  (sustituido por `wiremix`) y lectura de dependencias independiente del idioma.
- **`rc.xml` (labwc 0.9.3+):** `<snapping><range>` → `<range inner="10" outer="10"/>` y `<windowSwitcher show=…>` → `<osd show=… style=…>` dentro de `<windowSwitcher>`, y `allWorkspaces` → `workspace="current"` en las acciones `NextWindow`/`PreviousWindow`: desaparecen los avisos de obsoleto.
- **waybar:** quitado `"signal": 8` de `custom/dnd` (waybar ignora RTMIN+n; `dnd` ya usa SIGUSR2).
- **Autostart:** el comentario del fondo decía `4.jpeg`/`ink.png`; el código usa `3.jpeg` y luego `4.jpeg`. Comentario corregido.
- Si quieres quitar también Thunar (y con él todas las librerías Xfce), `yazi` (`W-e`) ya cubre los archivos: `sudo pacman -Rns thunar`
  y cambia «Archivos» en `labwc/menu.xml`.

## Notas

- **No pude probarlo en un labwc real** (sin sistema Arch aquí). Validé XML/JSON/shell, probé `dotfiles.sh` con un HOME
  falso (incluido el caso de enlaces simbólicos) y comprobé la sintaxis contra `labwc-config(5)`. Revisa en tu equipo:
  1. que los botones salgan a la izquierda y el título centrado;
  2. que `cornerRadius` redondee: labwc redondea solo las **esquinas superiores** de la ventana (las de abajo las dibuja la app);
  3. que el módulo `wlr/taskbar` de waybar muestre tus ventanas.
- ANSI en foot es **escala de grises pura**. Si echas de menos distinguir errores en `git diff`, ajusta `regular1/2` en `foot.ini`.
- Si quieres un reproductor de música con interfaz: `paru -S deadbeef`.
- Regenerar el fondo: `python3 tools/gen-wallpaper.py ~/.local/share/backgrounds/ink.png` (python-pillow, numpy, scipy, opencv).
