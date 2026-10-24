#!/usr/bin/env bash
# INK · 2-optimize.sh — memoria, disco, arranque y (solo en portátiles) batería.
# Ejecútalo con:  ./2-optimize.sh   (pide sudo). Es idempotente.
set -euo pipefail
# Sin `-E`: no hay variables que propagar y el env_reset de sudoers puede descartarlas.
[[ $EUID -eq 0 ]] || exec sudo bash "$0" "$@"
ok()   { printf '\e[32m[ok]\e[0m %s\n' "$*"; }
note() { printf '\e[2m     %s\e[0m\n' "$*"; }

# ¿Hay batería? (portátil) → TLP tiene sentido; en un PC de escritorio solo añade ruido
LAPTOP=0
for d in /sys/class/power_supply/*; do   # se ignoran baterías de periféricos (scope=Device: ratón, mando…)
  [[ -r $d/type && $(<"$d/type") == Battery && $(cat "$d/scope" 2>/dev/null) != Device ]] && LAPTOP=1
done

# --- pacman: descargas en paralelo y color (antes de instalar, para que ya surtan efecto) ---
grep -qE '^ParallelDownloads' /etc/pacman.conf || sed -i 's/^#ParallelDownloads.*/ParallelDownloads = 5/' /etc/pacman.conf
grep -qE '^Color'             /etc/pacman.conf || sed -i 's/^#Color$/Color/' /etc/pacman.conf

PKGS=(zram-generator earlyoom pacman-contrib)
if (( LAPTOP )); then
  # TLP no convive con power-profiles-daemon
  if pacman -Qq power-profiles-daemon &>/dev/null; then
    systemctl disable --now power-profiles-daemon.service 2>/dev/null || true
    pacman -Rns --noconfirm power-profiles-daemon
    ok "power-profiles-daemon eliminado (choca con TLP)"
  fi
  PKGS+=(tlp)
fi
pacman -S --needed --noconfirm "${PKGS[@]}"

# --- TLP (solo portátiles; valores seguros, el resto usa los defaults de TLP) ---
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
  systemctl mask systemd-rfkill.service systemd-rfkill.socket   # lo exige TLP
  systemctl enable --now tlp.service
  tlp start >/dev/null || true
  ok "TLP configurado (portátil detectado)"
else
  note "Sin batería: se omite TLP (no aporta nada en un PC de escritorio)."
fi

# --- zram: swap comprimido en RAM (la mitad de la RAM, máx. 4 GiB) ---
install -Dm644 /dev/stdin /etc/systemd/zram-generator.conf <<'CONF'
[zram0]
zram-size = min(ram / 2, 4096)
compression-algorithm = zstd
swap-priority = 100
CONF

# --- sysctl: zram + SSD + red (valores de la wiki de Arch) ---
install -Dm644 /dev/stdin /etc/sysctl.d/99-ink-performance.conf <<'CONF'
vm.swappiness = 180
vm.page-cluster = 0
vm.watermark_boost_factor = 0
vm.watermark_scale_factor = 125
vm.vfs_cache_pressure = 50
kernel.nmi_watchdog = 0
CONF
# BBR + fq: mejor throughput y latencia en redes con pérdidas. Solo si el kernel trae el módulo.
if modprobe tcp_bbr 2>/dev/null; then
  echo tcp_bbr > /etc/modules-load.d/ink-bbr.conf
  install -Dm644 /dev/stdin /etc/sysctl.d/99-ink-network.conf <<'CONF'
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
CONF
fi

# --- earlyoom: mata lo más pesado antes de que el equipo se congele; nunca el escritorio ---
# -m 10 / -s 10: avisa al bajar del 10 % de memoria disponible o de swap libre.
# -r 3600: un informe de memoria por hora (sin esto earlyoom escribe uno por segundo en el journal).
# --ignore: el escritorio (labwc, waybar, mako, terminal, systemd) no se toca;
#           si hay que matar, se sacrifica otra aplicación antes.
install -Dm644 /dev/stdin /etc/default/earlyoom <<'CONF'
EARLYOOM_ARGS="-r 3600 -m 10 -s 10 --ignore (^|/)(labwc|waybar|greetd|systemd|Xwayland|foot)$"
CONF

# --- journal limitado y apagado rápido ---
install -Dm644 /dev/stdin /etc/systemd/journald.conf.d/10-ink.conf <<'CONF'
[Journal]
SystemMaxUse=100M
CONF
install -Dm644 /dev/stdin /etc/systemd/system.conf.d/10-ink.conf <<'CONF'
[Manager]
DefaultTimeoutStopSec=10s
CONF

sysctl --system >/dev/null || note "Algún sysctl no se pudo aplicar; revisa el aviso anterior."
systemctl daemon-reload

# --- servicios: TRIM semanal, limpieza de caché de pacman, hora sincronizada, OOM ---
systemctl enable --now fstrim.timer paccache.timer earlyoom.service systemd-timesyncd.service

# --- arranque más rápido: no esperar a la red para llegar al login ---
# (si montas unidades de red en fstab, quita esta línea o añade _netdev)
systemctl disable NetworkManager-wait-online.service 2>/dev/null || true

systemctl restart systemd-zram-setup@zram0.service 2>/dev/null || systemctl start systemd-zram-setup@zram0.service || true
ok "Listo. Comprueba: zramctl · systemctl list-timers · systemd-analyze$( ((LAPTOP)) && echo ' · sudo tlp-stat -s')"
