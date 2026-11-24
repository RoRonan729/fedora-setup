# shared helpers for install.sh
C_B=$'\e[1;34m'; C_G=$'\e[1;32m'; C_Y=$'\e[1;33m'; C_R=$'\e[1;31m'; C_0=$'\e[0m'
banner() { echo; echo "${C_B}==================== $* ====================${C_0}"; }
info()   { echo "${C_G}[+]${C_0} $*"; }
warn()   { echo "${C_Y}[!]${C_0} $*" >&2; }
die()    { echo "${C_R}[x]${C_0} $*" >&2; exit 1; }

CURRENT_PHASE=""
# usage: phase <id> <title> && { ...; done_phase; }
phase() {
  CURRENT_PHASE="$1"
  if [[ -f "$STATE_DIR/done.$1" ]]; then
    echo "${C_B}[skip]${C_0} $1 — $2 (already done)"
    return 1
  fi
  banner "$1 — $2"
  return 0
}
done_phase() { touch "$STATE_DIR/done.$CURRENT_PHASE"; }

sudo_keepalive() {
  sudo -v || die "sudo is required."
  ( while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || exit; done ) &
}
