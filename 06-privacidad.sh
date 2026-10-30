#!/usr/bin/env bash
# 06-privacidad.sh — seguridad y privacidad de sistema (Artix + dinit).
#   dns        DNS cifrado (DoT) con stubby + Quad9 (Artix no trae systemd-resolved)
#   network    NetworkManager: MAC estable por red, IPv6 privado
#   firewall   ufw: entrante denegado, saliente permitido
#   hardening  sysctl + sin coredumps
# Uso:  ./06-privacidad.sh [dns network firewall hardening]   (sin argumentos = todos)
#       ./06-privacidad.sh --revert
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
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib/artix.sh"
require_artix
NM=$(nm_svc)

# Deja el DNS como estaba (o en Quad9 si no había copia) y repone NetworkManager.
dns_rollback() {
  svc_stop ink-stubby; svc_disable ink-stubby
  rm -f /etc/NetworkManager/conf.d/10-dns-none.conf /etc/resolv.conf
  if [[ -e /etc/resolv.conf.ink-bak || -L /etc/resolv.conf.ink-bak ]]; then mv -T /etc/resolv.conf.ink-bak /etc/resolv.conf
  else printf 'nameserver 9.9.9.9\n' > /etc/resolv.conf; fi
  if svc_active "$NM"; then svc_restart "$NM"; fi
}
dns_works() { local i; for i in 1 2 3 4 5; do timeout 8 getent hosts archlinux.org >/dev/null 2>&1 && return 0; sleep 2; done; return 1; }

mod_dns() {
  command -v stubby >/dev/null || { warn "stubby no está instalado (¿[extra] de Arch activado?). Omito dns."; return 0; }
  # stubby no arranca si debe escuchar en una dirección que no existe: ::1 solo si hay IPv6 en lo
  local v6=0 listen="  - 127.0.0.1@53" ns="nameserver 127.0.0.1"
  if grep -qE '[[:space:]]lo$' /proc/net/if_inet6 2>/dev/null; then
    v6=1; listen+=$'\n'"  - 0::1@53"; ns+=$'\n'"nameserver ::1"
  fi
  local auth="" transports="  - GETDNS_TRANSPORT_TLS
  - GETDNS_TRANSPORT_UDP
  - GETDNS_TRANSPORT_TCP"
  if [[ $DOT_MODE == yes ]]; then   # estricto: solo TLS y certificado verificado
    auth="tls_authentication: GETDNS_AUTHENTICATION_REQUIRED"
    transports="  - GETDNS_TRANSPORT_TLS"
  fi
  install -Dm644 /dev/stdin /etc/stubby/stubby.yml <<CONF
resolution_type: GETDNS_RESOLUTION_STUB
dns_transport_list:
${transports}
${auth}
tls_query_padding_blocksize: 128
edns_client_subnet_private: 1
round_robin_upstreams: 1
idle_timeout: 10000
listen_addresses:
${listen}
upstream_recursive_servers:
  - address_data: 9.9.9.9
    tls_auth_name: "dns.quad9.net"
  - address_data: 149.112.112.112
    tls_auth_name: "dns.quad9.net"
  - address_data: 2620:fe::fe
    tls_auth_name: "dns.quad9.net"
  - address_data: 2620:fe::9
    tls_auth_name: "dns.quad9.net"
CONF

  # Servicio propio (sin depender del paquete stubby-dinit): en primer plano y como root para usar el puerto 53.
  # Si una ejecución anterior dejó un servicio «stubby», se retira para que no ocupe el puerto.
  svc_stop stubby; svc_disable stubby
  pacman -Qo /etc/dinit.d/stubby &>/dev/null || rm -f /etc/dinit.d/stubby
  add_svc ink-stubby <<'SVC'
type = process
command = /usr/bin/stubby -C /etc/stubby/stubby.yml
restart = true
SVC
  svc_stop ink-stubby; svc_start ink-stubby
  sleep 2
  if ! svc_active ink-stubby; then
    warn "ink-stubby no arrancó. Mira: dinitctl status ink-stubby  y  stubby -C /etc/stubby/stubby.yml -l"
    svc_disable ink-stubby; return 0
  fi

  # Se prueba ANTES de dar por buena la configuración: si no resuelve, vuelve todo atrás y la red sigue funcionando
  [[ -e /etc/resolv.conf || -L /etc/resolv.conf ]] && ! [[ -e /etc/resolv.conf.ink-bak || -L /etc/resolv.conf.ink-bak ]] && cp -P /etc/resolv.conf /etc/resolv.conf.ink-bak
  rm -f /etc/resolv.conf
  printf '%s\n' "$ns" > /etc/resolv.conf
  if ! dns_works; then
    dns_rollback
    warn "stubby no resuelve: se deja el DNS anterior. ¿Tu red bloquea el puerto 853? Prueba DOT_MODE=opportunistic ./06-privacidad.sh dns"
    return 0
  fi
  # NetworkManager no debe volver a escribir resolv.conf; se repite la prueba tras reiniciarlo
  install -Dm644 /dev/stdin /etc/NetworkManager/conf.d/10-dns-none.conf <<'NMCONF'
[main]
dns=none
NMCONF
  if svc_active "$NM"; then svc_restart "$NM"; sleep 4; fi
  if ! grep -q '127.0.0.1' /etc/resolv.conf; then rm -f /etc/resolv.conf; printf '%s\n' "$ns" > /etc/resolv.conf; fi
  if ! dns_works; then
    dns_rollback
    warn "Tras reiniciar NetworkManager el DNS dejó de resolver: se restauró el anterior."
    return 0
  fi
  ok "DNS cifrado activo (DoT: ${DOT_MODE}) y comprobado con una consulta real"
  if [[ $DOT_MODE == yes ]]; then warn "DoT estricto: en redes con portal cautivo (hotel, café) vuelve a ejecutarlo con DOT_MODE=opportunistic."; fi
  return 0
}

mod_network() {
  if ! svc_active "$NM"; then warn "NetworkManager inactivo; omito network."; return 0; fi
  install -Dm644 /dev/stdin /etc/NetworkManager/conf.d/20-privacy.conf <<CONF
[device]
wifi.scan-rand-mac-address=yes

[connection]
wifi.cloned-mac-address=${MAC_MODE}
ethernet.cloned-mac-address=${MAC_MODE}
ipv6.ip6-privacy=2
CONF
  svc_restart "$NM"
  ok "MAC ${MAC_MODE} + IPv6 privado. Reconecta la red para aplicarlo."
}

mod_firewall() {
  if ! command -v ufw >/dev/null; then
    pacman -Si ufw &>/dev/null || { warn "ufw no está en los repos. Omito firewall."; return 0; }
    pacman -S --needed --noconfirm ufw
  fi
  if ! dinit_pkg ufw now; then
    add_svc ufw now <<'SVC'
type = scripted
command = /usr/lib/ufw/ufw-init start quiet
stop-command = /usr/lib/ufw/ufw-init stop
SVC
  fi
  ufw default deny incoming
  ufw default allow outgoing
  LC_ALL=C ufw status | grep -q "Status: active" || ufw --force enable   # LC_ALL=C: ufw está traducido
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
  # Sin systemd-coredump: se descartan los volcados con core_pattern y límites
  install -Dm644 /dev/stdin /etc/sysctl.d/99-ink-nocore.conf <<'CONF'
kernel.core_pattern = |/bin/false
CONF
  install -Dm644 /dev/stdin /etc/security/limits.d/10-ink-nocore.conf <<'CONF'
* hard core 0
CONF
  ensure_sysctl_svc
  # sysctl --system devuelve error si el kernel no admite alguna clave en caliente: no debe abortar el script
  sysctl --system >/dev/null || warn "Algún sysctl no se pudo aplicar; revisa el aviso anterior."
  ok "sysctl aplicado y coredumps desactivados"
}

revert() {
  rm -f /etc/stubby/stubby.yml /etc/NetworkManager/conf.d/20-privacy.conf \
        /etc/sysctl.d/99-privacy.conf /etc/sysctl.d/99-ink-nocore.conf /etc/security/limits.d/10-ink-nocore.conf
  svc_stop stubby; svc_disable stubby          # nombre usado por versiones anteriores
  pacman -Qo /etc/dinit.d/stubby &>/dev/null || rm -f /etc/dinit.d/stubby
  dns_rollback
  rm -f /etc/dinit.d/ink-stubby
  sleep 2; [[ -s /etc/resolv.conf ]] || printf 'nameserver 9.9.9.9\n' > /etc/resolv.conf   # red de seguridad
  sysctl --system >/dev/null || warn "sysctl --system terminó con errores (revisa arriba)."
  ok "Revertido. ufw no se toca (desactívalo con: sudo ufw disable)."
}

[[ "${1:-}" == "--revert" ]] && { revert; exit 0; }
mods=("$@"); [[ ${#mods[@]} -eq 0 ]] && mods=(network firewall hardening dns)   # dns el último: si algo falla, ya está todo instalado

# Paquetes primero, con la red tal cual está: así un cambio de DNS no puede dejar nada a medias
pre=()
for m in "${mods[@]}"; do
  case "$m" in
    dns)      command -v stubby >/dev/null || { pacman -Si stubby &>/dev/null && pre+=(stubby) || warn "stubby no está en los repos: se omitirá dns."; } ;;
    firewall) command -v ufw >/dev/null || { pacman -Si ufw &>/dev/null && pre+=(ufw) || warn "ufw no está en los repos: se omitirá firewall."; }
              pacman -Si ufw-dinit &>/dev/null && pre+=(ufw-dinit) ;;
  esac
done
if (( ${#pre[@]} )); then pacman -S --needed --noconfirm "${pre[@]}" || warn "No se pudieron instalar: ${pre[*]}"; fi

for m in "${mods[@]}"; do
  case "$m" in dns|network|firewall|hardening) echo "== $m =="; "mod_$m" ;; *) warn "Módulo desconocido: $m" ;; esac
done
ok "Listo. Comprueba: cat /etc/resolv.conf · dinitctl list · sudo ufw status verbose"
