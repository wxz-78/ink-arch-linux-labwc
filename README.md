# artix-dinit-dotfiles

Escritorio Wayland **minimalista en blanco y negro** (labwc + waybar + fuzzel + foot + mako) para **Artix Linux con dinit + elogind**.
Sin systemd en ningún sitio: los servicios son de dinit y la sesión de usuario arranca desde `labwc/autostart`.

Está pensado para ir **después** de `01-install-base` y `02-configuracion` (Artix, dinit, Btrfs, Limine, linux-zen).

## Instalación

Tras el primer arranque, entra como tu usuario (el del script 02) y, desde este directorio:

```bash
./03-escritorio.sh     # paquetes según tu hardware, greetd + tuigreet, scripts de apoyo (OFFICE=1 añade LibreOffice)
./04-dotfiles.sh       # copia .config y .local a ~ con respaldo (--dry-run para simular)
sudo reboot            # arrancan elogind y greetd; entra por la pantalla de login
./05-optimizacion.sh   # zram, sysctl, earlyoom, cron (paccache, fstrim, scrub Btrfs), TLP si es portátil, hook de Limine
./06-privacidad.sh     # DNS cifrado (stubby, con comprobación y vuelta atrás automática), MAC por red, ufw, hardening   (--revert para deshacer)
./07-diagnostico.sh    # cuando quieras: comprueba servicios, sesión, swap, DNS y escritorio (solo lee; con sudo revisa también ufw)
```

`03` **no arranca ningún servicio**: solo los activa. Empiezan en el siguiente reinicio, así nada se inicia a mitad de la instalación.

## Estructura

```
lib/artix.sh   funciones comunes (servicios dinit, repos, avisos)
07-diagnostico.sh  informe ✔/✘ del estado del sistema
.config/       → ~/.config       labwc, waybar, foot, fuzzel, mako, swaylock, fish, gtk, zathura, mpv, imv…
.local/share/  → ~/.local/share  tema de ventanas «Ink»
bin/           → /usr/local/bin  osd, shot, lock, dnd, power-menu, idle-suspend
tools/         generador del fondo (gen-wallpaper.py)
```

## Cómo encaja con dinit

| Necesidad | Solución |
|---|---|
| Activar un servicio | enlace en `/etc/dinit.d/boot.d` (`svc_enable`); `dinitctl list` para ver el estado |
| dbus, elogind, NetworkManager, bluez, greetd, cronie, chrony, ufw, tlp | paquetes `*-dinit` de Artix; si falta alguno, el script crea un servicio propio |
| Sesión y `XDG_RUNTIME_DIR` | elogind + PAM; greetd lanza `dbus-run-session labwc` |
| Audio | `pipewire-launcher` (o pipewire + wireplumber + pipewire-pulse) desde `labwc/autostart` |
| Apagar, reiniciar, suspender | `loginctl` (elogind) |
| zram | servicio `ink-zram` (`zramctl`) |
| sysctl al arrancar | servicio `ink-sysctl` |
| DNS cifrado | `stubby` + Quad9; NetworkManager con `dns=none` |
| Timers (fstrim, paccache, scrub) | `cronie` → `/etc/cron.d/ink-maintenance` |
| Coredumps | `kernel.core_pattern=|/bin/false` y límite `core 0` |

Detalles que se adaptan solos: sin `fstrim` si montas con `discard=async`; scrub mensual solo en Btrfs; hook de pacman que recopia Limine a la ESP al actualizarlo; chrony no se duplica si ya lo activó `02`.

## Repos de Artix y de Arch

Si `labwc`, `waybar`, `greetd-tuigreet`, `wiremix` o `yazi` no están en los repos de Artix, `03` ofrece activar `[extra]` de Arch con `artix-archlinux-support`. Lo que siga faltando (`helium-browser-bin`, `wlopm`…) se instala del AUR con `paru`, que se compila desde el AUR si no tienes un ayudante.

## Atajos

| | |
|---|---|
| `W-Enter` terminal · `W-d` buscar apps · `W-b` Helium · `W-S-b` incógnito · `W-e` yazi | `W-v` historial del portapapeles |
| `W-q` cerrar · `W-f` maximizar · `W-m` minimizar · `W-h/j/k/l` acomodar · `W-1..4` escritorios | `W-Esc` menú de apagado · `W-S-l` bloquear |
| `Print` captura · `S-Print` área · `C-Print` al portapapeles · `W-Print` anotar con swappy | `W-n` No molestar · `W-S-n` descartar notificaciones |
| `W-Tab` / `A-Tab` cambiar ventana · `C-S-Esc` btop | `W-S-r` recargar labwc · clic derecho en el fondo: menú |

Inactividad: 5 min bloquea · 5:30 apaga pantalla (`wlopm`) · 15 min suspende **solo con batería**.
Monitores: `wlr-randr` lista las salidas; hay ejemplos comentados en `labwc/autostart`.
Teclado: revisa `labwc/environment` (`latam`; tu consola usa `la-latin1`).

## Si algo falla

- **Login desordenado o teclas repartidas:** greetd debe estar en la VT 7 (`vt = 7` en `/etc/greetd/config.toml`); los getty de tty1-6 se quedan como consola de rescate. `dinitctl status greetd`.
- **labwc dice que no hay `XDG_RUNTIME_DIR`:** `dinitctl status elogind`; revisa que `/etc/pam.d/system-login` cargue `pam_elogind`.
- **Sin audio:** `pgrep -a 'pipewire|wireplumber'`; ejecuta `pipewire-launcher` a mano.
- **Sin DNS / sin internet tras 06:** `dinitctl status ink-stubby`; `./06-privacidad.sh --revert`. El script prueba una consulta real y deshace el cambio si falla.
- **Usuarios de sistema que faltan** (`greeter`, `rtkit`, `polkitd`, `chrony`): sin `systemd-sysusers` algún paquete puede no crearlos; `03` crea `greeter` y `05` crea `chrony`; revisa el resto con `getent passwd`.
- **Dentro de un servicio dinit no pongas `$` en `command`:** usa un script envoltorio (como `ink-earlyoom`).

## Estado

Escrito sin acceso a un Artix real: la sintaxis de los scripts está comprobada y `04-dotfiles.sh` se probó con un HOME falso, pero los nombres de paquetes y servicios `*-dinit` se verifican al ejecutar. Si algo falla, pega la salida de `dinitctl list` y la línea de error.

El fondo de pantalla no va incluido: copia tus imágenes a `~/.local/share/backgrounds/` (`3.jpeg` o `4.jpeg`) o genéralo con `tools/gen-wallpaper.py`.
