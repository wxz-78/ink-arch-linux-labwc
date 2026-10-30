#!/usr/bin/env bash
# 07-diagnostico.sh — comprueba (solo lectura, no cambia nada) que lo instalado por 03-06 está en su sitio.
# Uso:  ./07-diagnostico.sh        (con sudo ve también el firewall)
# Código de salida: 0 si no hay fallos (✘); los avisos (~) no cuentan.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib/artix.sh"
F=0; W=0
pass() { printf '  \033[32m✔\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✘\033[0m %s\n' "$*"; F=$((F+1)); }
skip() { printf '  \033[33m~\033[0m %s\n' "$*"; W=$((W+1)); }
chk()  { local d=$1; shift; if "$@" >/dev/null 2>&1; then pass "$d"; else fail "$d"; fi; }
sec()  { printf '\n\033[1m%s\033[0m\n' "$*"; }

# svc NOMBRE [opcional]: debe existir, estar activado en boot.d y en marcha. Los opcionales solo avisan si faltan.
svc() {
  local s=$1 opt=${2:-}
  if ! svc_exists "$s"; then
    if [[ $opt ]]; then skip "$s: no instalado ($opt)"; else fail "$s: el servicio no existe"; fi
    return
  fi
  [[ -e $BOOT_D/$s ]] || skip "$s: existe pero no está activado en $BOOT_D"
  if svc_active "$s"; then pass "$s en marcha"; else fail "$s no está en marcha (dinitctl status $s)"; fi
}

sec "Sistema"
chk "Artix Linux"                     test -f /etc/artix-release
chk "dinit es el init (PID 1)"        grep -qx dinit /proc/1/comm
chk "no queda systemd instalado"      bash -c '! pacman -Q systemd &>/dev/null'
chk "pam_elogind en la pila PAM"      grep -rqs pam_elogind /etc/pam.d

sec "Servicios base"
svc dbus; svc elogind; svc "$(nm_svc)"; svc greetd
svc chronyd "05"; svc acpid "02"; svc cronie "05"
if [[ -d /sys/class/bluetooth && -n $(ls -A /sys/class/bluetooth 2>/dev/null) ]]; then
  bt=bluetoothd; svc_exists bluetooth && bt=bluetooth   # el nombre depende del paquete bluez-dinit
  svc "$bt" "03"
fi
for b in /sys/class/power_supply/BAT*; do [[ -e $b ]] && { svc tlp "05"; break; }; done

sec "Sesión y login"
if grep -qE '^vt *= *[2-9]' /etc/greetd/config.toml 2>/dev/null; then pass "greetd fuera de la VT 1 ($(grep -E '^vt' /etc/greetd/config.toml))"
else fail "greetd debe usar vt = 7 en /etc/greetd/config.toml (la VT 1 choca con el getty)"; fi
chk "usuario greeter existe"          getent passwd greeter
if [[ -n ${XDG_RUNTIME_DIR:-} && -d $XDG_RUNTIME_DIR ]]; then pass "XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR"
else skip "XDG_RUNTIME_DIR vacío (normal si ejecutas esto por SSH o desde un TTY sin sesión elogind)"; fi
if pgrep -x labwc >/dev/null; then
  for p in pipewire wireplumber pipewire-pulse waybar mako swayidle; do
    if pgrep -u "$(id -u)" -x "$p" >/dev/null; then pass "$p corriendo"; else fail "$p no está corriendo"; fi
  done
  [[ -n ${LANG:-} ]] && pass "LANG=$LANG" || skip "LANG vacío en la sesión (fechas e idioma saldrán en inglés)"
else skip "labwc no está corriendo: se omiten las comprobaciones de la sesión gráfica"; fi

sec "Memoria y disco"
svc ink-zram "05"; svc ink-sysctl "05"; svc ink-earlyoom "05"
if swapon --show=NAME --noheadings 2>/dev/null | grep -q zram; then pass "zram activo como swap"; else skip "zram no está activo (05)"; fi
if swapon --show=NAME --noheadings 2>/dev/null | grep -qv zram; then
  grep -q 'resume=' /proc/cmdline && pass "swap en disco con resume= (hibernar posible)" || skip "hay swap en disco pero el kernel no tiene resume= (no se podrá hibernar)"
fi
[[ $(sysctl -n vm.swappiness 2>/dev/null) == 180 ]] && pass "vm.swappiness=180" || skip "vm.swappiness no es 180 (05)"
[[ $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null) == bbr ]] && pass "TCP BBR" || skip "TCP BBR no activo (¿kernel sin tcp_bbr?)"
[[ -f /etc/cron.d/ink-maintenance ]] && pass "tareas de mantenimiento en cron" || skip "falta /etc/cron.d/ink-maintenance (05)"
if [[ -f /boot/EFI/limine/BOOTX64.EFI ]]; then
  [[ -f /etc/pacman.d/hooks/90-limine-esp.hook ]] && pass "hook de pacman para Limine" || fail "falta el hook de Limine (05)"
fi

sec "Red y privacidad"
if grep -q '^nameserver 127\.0\.0\.1' /etc/resolv.conf 2>/dev/null; then
  svc ink-stubby; chk "el DNS cifrado resuelve" timeout 10 getent hosts archlinux.org
else
  chk "el DNS resuelve (cifrado no configurado: 06)" timeout 10 getent hosts archlinux.org
fi
if [[ $EUID -eq 0 ]]; then
  if command -v ufw >/dev/null; then LC_ALL=C ufw status | grep -q "Status: active" && pass "ufw activo" || skip "ufw instalado pero inactivo (06)"
  else skip "ufw no instalado (06)"; fi
else skip "ufw: ejecuta con sudo para comprobarlo"; fi

sec "Escritorio"
for b in labwc waybar fuzzel foot mako swaylock swayidle swaybg grim slurp wl-copy cliphist brightnessctl wpctl tuigreet; do
  command -v "$b" >/dev/null || fail "falta el programa: $b"
done
for b in osd shot lock dnd power-menu idle-suspend; do [[ -x /usr/local/bin/$b ]] || fail "falta /usr/local/bin/$b (03)"; done
for b in wlopm swappy; do command -v "$b" >/dev/null || skip "$b no instalado (opcional)"; done
for f in labwc/rc.xml labwc/autostart waybar/config.jsonc foot/foot.ini; do [[ -f $HOME/.config/$f ]] || fail "falta ~/.config/$f (04)"; done

printf '\n'
if (( F )); then printf '\033[31m%d fallo(s)\033[0m y %d aviso(s).\n' "$F" "$W"; exit 1
else printf '\033[32mSin fallos\033[0m (%d aviso(s) opcionales).\n' "$W"; fi
