#!/usr/bin/env bash
# ============================================================
# INK · 1-install.sh — paquetes, login (greetd) y scripts de apoyo.
# Úsalo como usuario normal (pide sudo):  ./1-install.sh
# Es idempotente. paru se compila desde el AUR si no hay ayudante AUR. Opcional: OFFICE=1 ./1-install.sh añade LibreOffice. Detecta tu hardware (CPU, GPU, Bluetooth, portátil) e instala solo lo que hace falta.
# Después copia los dotfiles con ./dotfiles.sh (ver README).
# ============================================================
set -euo pipefail
[ "$EUID" -eq 0 ] && { echo "No lo ejecutes como root."; exit 1; }
cd "$(dirname "$0")"
say()  { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
note() { printf '    \033[2m%s\033[0m\n' "$*"; }
REPO_PKGS=$(pacman -Slq)   # una sola consulta a las bases de datos; in_repo ya no lanza pacman por paquete
in_repo() { grep -qxF -- "$1" <<<"$REPO_PKGS"; }
# Paquete opcional o dudoso: repos oficiales si existe; si no, AUR. Así un nombre que no esté en los repos no aborta toda la instalación.
AUR=(helium-browser-bin)
pkg_or_aur() { if in_repo "$1"; then PKGS+=("$1"); else AUR+=("$1"); fi; }

# ---------- paquetes base (repos oficiales) ----------
PKGS=(
  # escritorio
  labwc waybar fuzzel foot mako swaylock swayidle swaybg wf-recorder
  cliphist wl-clipboard grim slurp brightnessctl libnotify yt-dlp
  xorg-xwayland qt6-wayland dconf polkit-gnome xdg-utils wlr-randr
  xdg-desktop-portal xdg-desktop-portal-wlr xdg-desktop-portal-gtk xdg-user-dirs
  # audio y red (TUIs en vez de apps GTK: wiremix sustituye a pavucontrol)
  pipewire-audio pipewire-alsa pipewire-pulse wireplumber rtkit wiremix
  networkmanager
  # archivos y discos
  thunar gvfs gvfs-mtp udisks2 exfatprogs dosfstools yazi 7zip unzip zip fd ripgrep   # gvfs-mtp: móviles Android · exfat/dosfstools: formatear y reparar USB
  # terminal y herramientas
  fish eza bat fzf zoxide btop fastfetch neovim git
  # visor / medios
  imv zathura zathura-pdf-mupdf mpv
  # login y secretos (gnome-keyring: Helium guarda contraseñas y cookies cifradas con libsecret; sin él usa una clave fija débil)
  greetd greetd-tuigreet gnome-keyring
  # apariencia
  adw-gtk-theme papirus-icon-theme
  ttf-jetbrains-mono-nerd ttf-liberation ttf-dejavu noto-fonts-emoji
  # mantenimiento
  pacman-contrib playerctl
  man-db man-pages            # `man` (fish usa bat como MANPAGER)
)

# ---------- hardware: se instala solo lo que tu equipo usa ----------
pkg_or_aur adwaita-qt6   # tema oscuro para apps Qt
pkg_or_aur swappy        # anotar capturas (W-Print)
pkg_or_aur phinger-cursors #tema cursor

# Ofimática: LibreOffice pesa más de 1 GB y no hace falta para el escritorio. Solo si lo pides:
#   OFFICE=1 ./1-install.sh
[ "${OFFICE:-0}" = 1 ] && PKGS+=(libreoffice-still-es)

# CPU → microcódigo
UCODE=""
if   grep -q GenuineIntel /proc/cpuinfo; then PKGS+=(intel-ucode); UCODE=intel; if in_repo sof-firmware; then PKGS+=(sof-firmware); fi   # audio de portátiles Intel recientes
elif grep -q AuthenticAMD /proc/cpuinfo; then PKGS+=(amd-ucode);   UCODE=amd; fi

# GPU → drivers de Mesa/Vulkan/VA-API (lee el fabricante de /sys: 0x8086 Intel, 0x1002 AMD, 0x10de NVIDIA)
PKGS+=(mesa)
GPUS=$(cat /sys/class/drm/card*/device/vendor 2>/dev/null | sort -u || true)
for v in $GPUS; do
  case "$v" in
    0x8086) PKGS+=(vulkan-intel intel-media-driver) ;;
    0x1002) PKGS+=(vulkan-radeon); in_repo libva-mesa-driver && PKGS+=(libva-mesa-driver) ;;
    0x10de) NVIDIA=1 ;;
  esac
done
[ -z "$GPUS" ] && note "No se detectó GPU en /sys (¿máquina virtual?): solo se instala mesa."

# Bluetooth → solo si hay controlador (en un PC sin bluetooth no se instala ni se activa el servicio)
BT=0
if [ -d /sys/class/bluetooth ] && [ -n "$(ls -A /sys/class/bluetooth 2>/dev/null)" ]; then BT=1; PKGS+=(bluez bluez-utils); pkg_or_aur bluetui; fi

# wlopm apaga la pantalla por inactividad: si no está en los repos, va por el AUR
pkg_or_aur wlopm

say "Instalando paquetes (repos oficiales)"
sudo pacman -S --needed "${PKGS[@]}"
[ "${NVIDIA:-0}" = 1 ] && note "NVIDIA detectada: instala el driver a mano (nvidia-open + nvidia-utils, según tu kernel); no se automatiza a propósito."

# ---------- AUR: navegador (y wlopm/bluetui/etc. si no están en los repos) ----------
# paru se COMPILA desde el AUR (no paru-bin): el binario precompilado se enlaza contra una versión concreta de
# libalpm y deja de arrancar cuando pacman se actualiza («error while loading shared libraries: libalpm.so.N»).
helper_ok() { command -v "$1" >/dev/null 2>&1 && "$1" --version >/dev/null 2>&1; }

build_paru() {
  say "Compilando paru desde el AUR (tarda unos minutos; Rust se instala solo para esto y se quita después)"
  sudo pacman -S --needed base-devel git
  installed_rust=0
  if ! command -v cargo >/dev/null 2>&1; then   # rust a mano: así makepkg no pregunta «rust o rustup»
    sudo pacman -S --needed --asdeps rust && installed_rust=1
  fi
  # paru-bin choca con paru (y es justo el que suele romperse): fuera
  if pacman -Q paru-bin &>/dev/null; then sudo pacman -Rns --noconfirm paru-bin; fi
  tmp=$(mktemp -d)
  if git clone --depth 1 https://aur.archlinux.org/paru.git "$tmp/paru" && (cd "$tmp/paru" && makepkg -si); then
    rm -rf "$tmp"
  else
    rm -rf "$tmp"; echo "AVISO: no se pudo compilar paru."; return 1
  fi
  if [ "$installed_rust" = 1 ]; then sudo pacman -Rns --noconfirm rust || true; fi   # solo hacía falta para compilar
}

HELPER=""
for h in paru yay; do
  if helper_ok "$h"; then HELPER=$h; break; fi
done
if [ -z "$HELPER" ]; then
  if command -v paru >/dev/null 2>&1; then echo "AVISO: paru está instalado pero no arranca (típico de paru-bin tras actualizar pacman)."; fi
  read -rp "No hay un ayudante AUR que funcione. ¿Compilar paru desde el AUR para instalar ${AUR[*]}? [s/N] " r
  if [[ $r =~ ^[sSyY]$ ]]; then
    if build_paru && helper_ok paru; then HELPER=paru; fi
  fi
fi
if [ -n "$HELPER" ]; then
  say "Instalando ${AUR[*]} con $HELPER"
  "$HELPER" -S --needed "${AUR[@]}" || echo "AVISO: falló algún paquete del AUR; reintenta más tarde."
else
  echo "AVISO: sin AUR no hay ${AUR[*]}. Sin navegador, instala chromium o firefox a mano (y cambia W-b en rc.xml); sin wlopm la pantalla no se apaga sola."
fi

# ---------- scripts de apoyo (en /usr/local/bin: labwc, waybar y fuzzel los encuentran sin tocar el PATH) ----------
say "Instalando scripts: osd, shot, lock, dnd, power-menu, idle-suspend"
sudo install -m755 bin/* /usr/local/bin/

# ---------- login: greetd + tuigreet en blanco y negro ----------
say "Configurando greetd"
sudo install -Dm644 /dev/stdin /etc/greetd/config.toml <<'TOML'
[terminal]
vt = 1

[default_session]
command = "tuigreet --time --remember --asterisks --cmd labwc --theme 'border=white;text=white;prompt=white;time=darkgray;action=darkgray;button=white;container=black;input=white;title=white;greet=white'"
user = "greeter"
TOML
sudo install -d -o greeter -g greeter /var/cache/tuigreet 2>/dev/null || true   # --remember guarda aquí el último usuario

# ---------- servicios ----------
say "Activando servicios"
sudo systemctl enable --now NetworkManager.service
[ "$BT" = 1 ] && sudo systemctl enable --now bluetooth.service
sudo systemctl enable --force greetd.service   # --force: sustituye el alias display-manager de sddm/gdm/lightdm si lo había
sudo systemctl --global enable pipewire.socket pipewire-pulse.socket wireplumber.service 2>/dev/null || true

# ---------- usuario ----------
sudo usermod -aG video "$USER"            # brillo sin sudo
xdg-user-dirs-update
[ "$(getent passwd "$USER" | cut -d: -f7)" = /usr/bin/fish ] || chsh -s /usr/bin/fish

# Navegador predeterminado: Helium (el .desktop lo trae el paquete)
for f in /usr/share/applications/[Hh]elium*.desktop; do
  [ -f "$f" ] && { xdg-settings set default-web-browser "${f##*/}" 2>/dev/null || true; break; }
done

cat <<MSG

✔ Listo. Siguiente:
  0. Microcódigo (${UCODE:-ninguno}): si se instaló, regenera tu gestor de arranque:
       GRUB:  sudo grub-mkconfig -o /boot/grub/grub.cfg
       systemd-boot / limine / rEFInd: añade el initrd de ucode (wiki de Arch: Microcode)
  1. Copia los dotfiles:   ./dotfiles.sh
  2. ./2-optimize.sh y ./3-privacy.sh
  3. Reinicia y entra desde greetd. (Antes puedes probar con \`labwc\` desde un TTY.)
MSG
