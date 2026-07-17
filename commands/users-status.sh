#!/usr/bin/env bash
# rig users status — what this box's operator accounts actually are, read from
# the machine itself: roles derived from REAL group membership (not the
# ledger's memory of an apply), key counts from authorized_keys, lock state
# from shadow. Reads only — no network, no writes.
set -euo pipefail

log()  { printf 'rig-users: %s\n' "$*"; }
warn() { printf 'rig-users: WARNING: %s\n' "$*" >&2; }
die()  { printf 'rig-users: ERROR: %s\n' "$1" >&2; exit "${2:-1}"; }

usage() {
  cat <<'EOF'
usage: rig users status

Per rig-managed user (the /etc/rig/users ledger): roles derived from the
groups the user is ACTUALLY in (rig-admin -> admin, rig -> rig, incus -> box),
the authorized_keys count, and whether the account is locked or active.
Reads the box only — no network, no writes. Run as root (shadow is read).
EOF
}

# --- args (validated before the root check, so errors are testable) ---------
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    *) die "unknown flag: $1" 2 ;;
  esac
done

[ "$(id -u)" -eq 0 ] || die "must run as root"

LEDGER=/etc/rig/users
if [ ! -r "$LEDGER" ]; then
  log "no rig-managed users (no $LEDGER yet — rig users apply creates it)"
  exit 0
fi

while IFS= read -r u; do
  [ -n "$u" ] || continue
  if ! id -u "$u" >/dev/null 2>&1; then
    # In the ledger but off the box: someone deleted by hand what rig only
    # ever locks. Say so rather than crash or silently skip.
    warn "$u: in the ledger but not on the box (rig never deletes — removed by hand?)"
    continue
  fi
  groups=" $(id -nG "$u") "
  roles=""
  case "$groups" in *" rig-admin "*) roles="admin" ;; esac
  case "$groups" in *" rig "*)       roles="${roles:+$roles,}rig" ;; esac
  case "$groups" in *" incus "*)     roles="${roles:+$roles,}box" ;; esac
  [ -n "$roles" ] || roles="none"
  home="$(getent passwd "$u" | cut -d: -f6)"
  keys=0
  if [ -r "$home/.ssh/authorized_keys" ]; then
    keys="$(grep -c . "$home/.ssh/authorized_keys" || true)"
  fi
  # Field 2 of `passwd -S` is the lock flag; locked is apply's resting state
  # for a user dropped from the file, so it is the fact worth surfacing.
  state=active
  case "$(passwd -S "$u" 2>/dev/null | awk '{print $2}')" in
    L|LK) state=locked ;;
  esac
  log "$u  roles=$roles  keys=$keys  $state"
done < "$LEDGER"
