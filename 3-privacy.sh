#!/usr/bin/env bash
# INK · 3-privacy.sh — seguridad y privacidad de sistema.
#   dns        DNS cifrado (DoT) con systemd-resolved + Quad9
#   network    NetworkManager: MAC estable por red, IPv6 privado
#   firewall   ufw: entrante denegado, saliente permitido
#   hardening  sysctl + sin coredumps
# Uso:  ./3-privacy.sh [dns network firewall hardening]   (sin argumentos = todos)
#       ./3-privacy.sh --revert
# Variables:  DOT_MODE=opportunistic  (predeterminado; "yes" = DoT estricto, no cae en portales cautivos)
#             MAC_MODE=stable         (predeterminado; "random" = MAC nueva en cada conexión)
set -euo pipefail

# Re-ejecuta como root pasando el modo por argumentos: `sudo -E` no es de fiar,
# sudoers aplica env_reset y descartaría DOT_MODE/MAC_MODE sin avisar.
if [[ $EUID -ne 0 ]]; then
  exec sudo bash "$0" --ink-root "${DOT_MODE:-opportunistic}" "${MAC_MODE:-stable}" "$@"
fi
if [[ "${1:-}" == "--ink-root" ]]; then
  shift
  DOT_MODE="${1:-opportunistic}"
  if [[ $# -gt 0 ]]; then shift; fi
  MAC_MODE="${1:-stable}"
  if [[ $# -gt 0 ]]; then shift; fi
fi
DOT_MODE="${DOT_MODE:-opportunistic}"
MAC_MODE="${MAC_MODE:-stable}"
case "$DOT_MODE" in yes|opportunistic) ;; *) echo "DOT_MODE inválido: $DOT_MODE"; exit 1 ;; esac
case "$MAC_MODE" in stable|random) ;; *) echo "MAC_MODE inválido: $MAC_MODE"; exit 1 ;; esac
ok()   { printf '\e[32m[ok]\e[0m %s\n' "$*"; }
warn() { printf '\e[33m[!]\e[0m %s\n' "$*"; }

mod_dns() {
  install -Dm644 /dev/stdin /etc/systemd/resolved.conf.d/10-privacy.conf <<CONF
[Resolve]
DNS=9.9.9.9#dns.quad9.net 149.112.112.112#dns.quad9.net 2620:fe::fe#dns.quad9.net 2620:fe::9#dns.quad9.net
# FallbackDNS vacío dejaba a resolved sin plan B: sin lista no hay a dónde
# recurrir si los servidores globales fallan (red de hotel, portal cautivo).
FallbackDNS=1.1.1.1 9.9.9.9
Domains=~.
DNSOverTLS=${DOT_MODE}
DNSSEC=allow-downgrade
LLMNR=no
MulticastDNS=no
CONF
  systemctl enable --now systemd-resolved
  ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
  systemctl restart systemd-resolved
  if systemctl is-active --quiet NetworkManager; then   # NM debe delegar el DNS en resolved, o lo pisa
    install -Dm644 /dev/stdin /etc/NetworkManager/conf.d/10-dns-resolved.conf <<'NMCONF'
[main]
dns=systemd-resolved
NMCONF
    systemctl restart NetworkManager
  fi
  ok "DNS cifrado (DoT: ${DOT_MODE}) · verifica: resolvectl status"
  [[ $DOT_MODE == yes ]] && warn "DoT estricto: en redes con portal cautivo (hotel, café) vuelve a ejecutarlo con DOT_MODE=opportunistic."
  return 0
}

mod_network() {
  if ! systemctl is-active --quiet NetworkManager; then warn "NetworkManager inactivo; omito network."; return 0; fi
  install -Dm644 /dev/stdin /etc/NetworkManager/conf.d/20-privacy.conf <<CONF
[device]
wifi.scan-rand-mac-address=yes

[connection]
wifi.cloned-mac-address=${MAC_MODE}
ethernet.cloned-mac-address=${MAC_MODE}
ipv6.ip6-privacy=2
CONF
  systemctl restart NetworkManager
  ok "MAC ${MAC_MODE} + IPv6 privado. Reconecta la red para aplicarlo."
}

mod_firewall() {
  command -v ufw >/dev/null || pacman -S --needed --noconfirm ufw
  systemctl enable --now ufw.service
  ufw default deny incoming
  ufw default allow outgoing
  ufw status | grep -q "Status: active" || ufw --force enable
  ok "ufw activo (entrante denegado, saliente permitido)"
}

mod_hardening() {
  install -Dm644 /dev/stdin /etc/sysctl.d/99-privacy.conf <<'CONF'
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
# BPF sin privilegios: 0 = permitido (valor por defecto del kernel). Con 1 el
# sandbox de V8 (Helium/Chromium) falla al arrancar; con 2 ni root puede usarlo.
# Se deja explícito en 0 para que la configuración también revierta el valor
# ya aplicado en caliente (si el kernel no lo permite, hace falta reiniciar).
kernel.unprivileged_bpf_disabled = 0
net.core.bpf_jit_harden = 2
kernel.kexec_load_disabled = 1
kernel.yama.ptrace_scope = 1
fs.suid_dumpable = 0
fs.protected_fifos = 2
fs.protected_regular = 2
# rp_filter laxo (2): no rompe VPN ni rutas asimétricas
net.ipv4.conf.all.rp_filter = 2
net.ipv4.conf.default.rp_filter = 2
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.tcp_syncookies = 1
# tcp_rfc1337=1 congela el socket al recibir un FIN antes de tiempo: rompe
# conexiones salientes (proxies, VPN, some hosts). 0 = comportamiento normal.
net.ipv4.tcp_rfc1337 = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0
net.ipv6.conf.all.use_tempaddr = 2
net.ipv6.conf.default.use_tempaddr = 2
# No se toca unprivileged_userns_clone: el sandbox de Helium/Chromium/Firefox lo necesita.
CONF
  # sysctl --system devuelve error si alguna clave no se puede aplicar (p. ej. un
  # ajuste que el kernel no admite en caliente): no debe abortar el script.
  sysctl --system >/dev/null || warn "Algún sysctl no se pudo aplicar; revisa el aviso anterior."
  install -Dm644 /dev/stdin /etc/systemd/coredump.conf.d/10-privacy.conf <<'CONF'
[Coredump]
Storage=none
ProcessSizeMax=0
CONF
  ok "sysctl aplicado y coredumps desactivados"
}

revert() {
  rm -f /etc/systemd/resolved.conf.d/10-privacy.conf /etc/NetworkManager/conf.d/20-privacy.conf \
        /etc/NetworkManager/conf.d/10-dns-resolved.conf \
        /etc/sysctl.d/99-privacy.conf /etc/systemd/coredump.conf.d/10-privacy.conf
  systemctl restart systemd-resolved 2>/dev/null || true
  systemctl is-active --quiet NetworkManager && systemctl restart NetworkManager || true
  sysctl --system >/dev/null || warn "sysctl --system terminó con errores (revisa arriba)."
  ok "Revertido. ufw no se toca (desactívalo con: sudo ufw disable)."
}

[[ "${1:-}" == "--revert" ]] && { revert; exit 0; }
mods=("$@"); [[ ${#mods[@]} -eq 0 ]] && mods=(dns network firewall hardening)
for m in "${mods[@]}"; do
  case "$m" in dns|network|firewall|hardening) echo "== $m =="; "mod_$m" ;; *) warn "Módulo desconocido: $m" ;; esac
done
ok "Listo. Comprueba: resolvectl status · sudo ufw status verbose"
