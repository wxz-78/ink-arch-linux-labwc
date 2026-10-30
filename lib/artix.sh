#!/usr/bin/env bash
# lib/artix.sh — utilidades comunes para Artix Linux + dinit. Se carga con `.`; no se ejecuta solo.
# SUDO: prefijo para lo que necesita root. Si el script ya corre como root queda vacío.
if [[ -z ${SUDO+x} ]]; then if [[ $EUID -eq 0 ]]; then SUDO=""; else SUDO=sudo; fi; fi
DINIT_DIRS=(/etc/dinit.d /usr/lib/dinit.d /usr/local/lib/dinit.d)
BOOT_D=/etc/dinit.d/boot.d

say()  { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
ok()   { printf '\033[32m[ok]\033[0m %s\n' "$*"; }
note() { printf '    \033[2m%s\033[0m\n' "$*"; }
warn() { printf '\033[33m[!]\033[0m %s\n' "$*"; }
die()  { printf '\033[31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

# Comprueba que estamos en Artix con dinit
require_artix() {
  [[ -f /etc/artix-release ]] || die "Esto es para Artix Linux (no existe /etc/artix-release)."
  command -v dinitctl >/dev/null 2>&1 || die "No hay dinitctl: este repo es solo para Artix con dinit."
}

# ---------- servicios dinit ----------
# ¿Existe el servicio NAME?
svc_exists() { local d; for d in "${DINIT_DIRS[@]}"; do [[ -e $d/$1 ]] && return 0; done; return 1; }

# Activa en el arranque SIN arrancarlo ahora (así no se lanzan elogind/greetd… en mitad de una instalación).
# Crea el enlace en boot.d; dinit resuelve las entradas por NOMBRE, el destino del enlace da igual.
svc_enable() {
  svc_exists "$1" || { echo "     (el servicio «$1» no existe: no se activa)" >&2; return 1; }
  [[ -d $BOOT_D ]] || echo "     (aviso: no existe $BOOT_D; comprueba dónde enlaza tu servicio «boot»)" >&2
  $SUDO install -d "$BOOT_D" && $SUDO ln -sf "../$1" "$BOOT_D/$1"
}
svc_disable() { $SUDO rm -f "$BOOT_D/$1"; $SUDO dinitctl disable "$1" &>/dev/null || true; }
svc_start()   { $SUDO dinitctl start "$1"   &>/dev/null || true; }
svc_stop()    { $SUDO dinitctl stop "$1"    &>/dev/null || true; }
svc_restart() { $SUDO dinitctl restart "$1" &>/dev/null || true; }
svc_active()  { dinitctl is-started "$1" &>/dev/null; }
# Activa y arranca ahora (solo servicios inocuos: cron, chrony, tlp, ufw, stubby…)
svc_enable_now() { svc_enable "$1" && svc_start "$1"; }

# Nombre del servicio de NetworkManager (según el paquete: NetworkManager o networkmanager)
nm_svc() { local s; for s in NetworkManager networkmanager; do svc_exists "$s" && { echo "$s"; return; }; done; echo NetworkManager; }

# dinit_pkg BASE [now] — instala BASE-dinit (si existe en los repos de Artix) y activa los servicios que trae.
# Con «now» también los arranca; sin él solo arrancan en el próximo reinicio. Devuelve 1 si el paquete no existe.
dinit_pkg() {
  local pkg="$1-dinit" f
  pacman -Si "$pkg" &>/dev/null || return 1
  $SUDO pacman -S --needed --noconfirm "$pkg" || return 1
  while IFS= read -r f; do
    if [[ ${2:-} == now ]]; then svc_enable_now "${f##*/}" || true; else svc_enable "${f##*/}" || true; fi
  done < <(pacman -Qlq "$pkg" | grep -E '^/(etc|usr/lib)/dinit\.d/[^/]+$' | grep -viE 'wait-online|-srv$' || true)
}

# write_svc NAME <<'EOF' … EOF — escribe /etc/dinit.d/NAME
write_svc() { $SUDO install -Dm644 /dev/stdin "/etc/dinit.d/$1"; }

# add_svc NOMBRE [now] <<'SVC' … SVC — escribe el servicio, lo activa y, con «now», lo arranca ya
add_svc() { write_svc "$1"; if [[ ${2:-} == now ]]; then svc_enable_now "$1" || true; else svc_enable "$1" || true; fi; }

# dep_lines SVC… — emite «depends-on: SVC» solo para los servicios que existen
dep_lines() { local s; for s in "$@"; do svc_exists "$s" && echo "depends-on: $s"; done; return 0; }

# sysctl.d no se aplica solo al arrancar sin systemd: un servicio propio lo hace
ensure_sysctl_svc() {
  $SUDO install -Dm755 /dev/stdin /usr/local/lib/ink/sysctl-apply <<'SH'
#!/bin/sh
# Carga BBR (si se configuró) y aplica /etc/sysctl.d
[ -r /etc/modules-load.d/ink-bbr.conf ] && modprobe tcp_bbr 2>/dev/null
sysctl --system >/dev/null 2>&1 || true
SH
  write_svc ink-sysctl <<'SVC'
type = scripted
command = /usr/local/lib/ink/sysctl-apply
SVC
  svc_enable_now ink-sysctl || true
}

# ---------- repositorios ----------
# offer_arch_extra PAQUETE… — si alguno falta en los repos de Artix, ofrece activar [extra] de Arch
# (paquete artix-archlinux-support). Solo se pregunta una vez y nunca si [extra] ya está activo.
offer_arch_extra() {
  local p missing=()
  grep -q '^\[extra\]' /etc/pacman.conf && return 0
  for p in "$@"; do pacman -Si "$p" &>/dev/null || missing+=("$p"); done
  (( ${#missing[@]} )) || return 0
  warn "No están en los repos de Artix: ${missing[*]}"
  read -rp "¿Activar [extra] de Arch (artix-archlinux-support)? [s/N] " r
  [[ $r =~ ^[sSyY]$ ]] || { note "Sigo sin [extra] de Arch: lo que falte se intentará por el AUR."; return 0; }
  $SUDO pacman -S --needed --noconfirm artix-archlinux-support || { warn "No se pudo instalar artix-archlinux-support."; return 0; }
  printf '\n[extra]\nInclude = /etc/pacman.d/mirrorlist-arch\n' | $SUDO tee -a /etc/pacman.conf >/dev/null
  $SUDO pacman-key --populate archlinux
  $SUDO pacman -Sy
  ok "[extra] de Arch activado."
}
