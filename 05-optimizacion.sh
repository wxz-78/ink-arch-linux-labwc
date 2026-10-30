#!/usr/bin/env bash
# 05-optimizacion.sh — memoria, disco, arranque y (solo en portátiles) batería. Artix + dinit.
# Ejecútalo con:  ./05-optimizacion.sh   (pide sudo). Es idempotente. Detecta Btrfs, discard=async, Limine y chrony.
set -euo pipefail
[[ $EUID -eq 0 ]] || exec sudo bash "$0" "$@"
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib/artix.sh"
require_artix

# ¿Hay batería? (portátil) → TLP tiene sentido; en un PC de escritorio solo añade ruido
LAPTOP=0
for d in /sys/class/power_supply/*; do   # se ignoran baterías de periféricos (scope=Device)
  [[ -r $d/type && $(<"$d/type") == Battery && $(cat "$d/scope" 2>/dev/null) != Device ]] && LAPTOP=1
done

# --- pacman: descargas en paralelo y color ---
grep -qE '^ParallelDownloads' /etc/pacman.conf || sed -i 's/^#ParallelDownloads.*/ParallelDownloads = 5/' /etc/pacman.conf
grep -qE '^Color'             /etc/pacman.conf || sed -i 's/^#Color$/Color/' /etc/pacman.conf

PKGS=(earlyoom pacman-contrib cronie chrony)
if (( LAPTOP )); then
  # TLP no convive con power-profiles-daemon
  if pacman -Qq power-profiles-daemon &>/dev/null; then
    svc_stop power-profiles-daemon; svc_disable power-profiles-daemon
    pacman -Rns --noconfirm power-profiles-daemon
    ok "power-profiles-daemon eliminado (choca con TLP)"
  fi
  PKGS+=(tlp)
fi
pacman -S --needed --noconfirm "${PKGS[@]}"

# --- TLP (solo portátiles) ---
if (( LAPTOP )); then
  install -Dm644 /dev/stdin /etc/tlp.d/10-ink.conf <<'CONF'
CPU_ENERGY_PERF_POLICY_ON_AC=balance_performance
CPU_ENERGY_PERF_POLICY_ON_BAT=balance_power
PLATFORM_PROFILE_ON_AC=balanced
PLATFORM_PROFILE_ON_BAT=low-power
PCIE_ASPM_ON_BAT=powersupersave
WIFI_PWR_ON_AC=off
WIFI_PWR_ON_BAT=on
USB_AUTOSUSPEND=1
USB_EXCLUDE_BTUSB=1
# Umbrales de carga (solo si tu portátil los soporta: `sudo tlp-stat -b`)
#START_CHARGE_THRESH_BAT0=75
#STOP_CHARGE_THRESH_BAT0=80
CONF
  if ! dinit_pkg tlp now; then
    add_svc tlp now <<'SVC'
type = scripted
command = /usr/bin/tlp init start
stop-command = /usr/bin/tlp init stop
SVC
  fi
  ok "TLP configurado (portátil detectado)"
else
  note "Sin batería: se omite TLP."
fi

# --- zram: swap comprimido en RAM (la mitad de la RAM, máx. 4 GiB). zram-generator es solo de systemd: servicio propio ---
install -Dm755 /dev/stdin /usr/local/lib/ink/zram <<'SH'
#!/bin/sh
# INK — swap comprimido en RAM: mitad de la RAM, máx. 4 GiB, zstd, prioridad 100
case "$1" in
  start)
    swapon --show=NAME --noheadings | grep -q '^/dev/zram' && exit 0
    modprobe zram || exit 1
    kb=$(awk '/^MemTotal:/{print $2}' /proc/meminfo)
    mb=$((kb / 1024 / 2)); [ "$mb" -gt 4096 ] && mb=4096
    dev=$(zramctl --find --algorithm zstd --size "${mb}M" 2>/dev/null || zramctl --find --size "${mb}M") || exit 1
    mkswap "$dev" >/dev/null && swapon --discard --priority 100 "$dev"
    ;;
  stop)
    for d in $(swapon --show=NAME --noheadings | grep '^/dev/zram'); do swapoff "$d"; zramctl --reset "$d"; done
    ;;
esac
SH
add_svc ink-zram now <<'SVC'
type = scripted
command = /usr/local/lib/ink/zram start
stop-command = /usr/local/lib/ink/zram stop
SVC

# --- sysctl: zram + SSD + red ---
install -Dm644 /dev/stdin /etc/sysctl.d/99-ink-performance.conf <<'CONF'
vm.swappiness = 180
vm.page-cluster = 0
vm.watermark_boost_factor = 0
vm.watermark_scale_factor = 125
vm.vfs_cache_pressure = 50
kernel.nmi_watchdog = 0
CONF
if modprobe tcp_bbr 2>/dev/null; then
  install -d /etc/modules-load.d
  echo tcp_bbr > /etc/modules-load.d/ink-bbr.conf
  install -Dm644 /dev/stdin /etc/sysctl.d/99-ink-network.conf <<'CONF'
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
CONF
fi
ensure_sysctl_svc
sysctl --system >/dev/null || note "Algún sysctl no se pudo aplicar; revisa el aviso anterior."

# --- earlyoom: mata lo más pesado antes de que el equipo se congele; nunca el escritorio ---
# -r 3600: un informe por hora. --avoid (regex sobre el nombre del proceso): el escritorio no se toca.
install -Dm755 /dev/stdin /usr/local/lib/ink/earlyoom <<'SH'
#!/bin/sh
exec /usr/bin/earlyoom -r 3600 -m 10 -s 10 --avoid '^(labwc|waybar|greetd|dinit|Xwayland|foot)$'
SH
add_svc ink-earlyoom now <<'SVC'
type = process
command = /usr/local/lib/ink/earlyoom
restart = true
SVC

# --- hora sincronizada (chrony) ---
getent passwd chrony >/dev/null || useradd -r -d /var/lib/chrony -s /usr/bin/nologin chrony
install -d -o chrony -g chrony /var/lib/chrony /var/log/chrony 2>/dev/null || true
if ! dinit_pkg chrony now; then
  add_svc chrony now <<'SVC'
type = process
command = /usr/bin/chronyd -n -u chrony
restart = true
SVC
fi

# --- mantenimiento: cron sustituye a los timers de systemd ---
dinit_pkg cronie now || note "No hay cronie-dinit: activa el servicio cronie a mano."
ROOT_FS=$(findmnt -no FSTYPE /)
ROOT_OPTS=$(findmnt -no OPTIONS /)
{
  echo 'SHELL=/bin/sh'
  echo 'MAILTO=""'          # sin MTA: evita avisos de correo no entregable
  echo 'PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin'
  # TRIM semanal, salvo que el montaje ya lo haga (Btrfs con discard=async)
  if [[ $ROOT_OPTS == *discard* ]]; then note "/ ya usa discard: no hace falta fstrim semanal."
  else echo '30 3 * * 0 root fstrim -Av'; fi
  # Limpieza de la caché de pacman: deja 2 versiones de cada paquete
  echo '45 3 * * 0 root paccache -rk2'
  # Btrfs: scrub mensual (detecta corrupción silenciosa), con prioridad mínima de CPU y disco
  if [[ $ROOT_FS == btrfs ]]; then echo '15 4 1 * * root ionice -c3 nice -n19 btrfs scrub start -B / >/dev/null'; fi
} | install -Dm644 /dev/stdin /etc/cron.d/ink-maintenance

# --- Limine: al actualizar el paquete, vuelve a copiar el binario EFI a la ESP (si lo instaló 01-install-base) ---
if [[ -f /boot/EFI/limine/BOOTX64.EFI ]]; then
  install -Dm644 /dev/stdin /etc/pacman.d/hooks/90-limine-esp.hook <<'HOOK'
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = limine

[Action]
Description = Actualizando Limine en la ESP...
When = PostTransaction
Exec = /bin/sh -c 'install -Dm644 /usr/share/limine/BOOTX64.EFI /boot/EFI/limine/BOOTX64.EFI && install -Dm644 /usr/share/limine/BOOTX64.EFI /boot/EFI/BOOT/BOOTX64.EFI'
HOOK
  ok "Hook de pacman para Limine instalado"
fi

ok "Listo. Comprueba: zramctl · dinitctl list · cat /etc/cron.d/ink-maintenance$( ((LAPTOP)) && echo ' · sudo tlp-stat -s')"
