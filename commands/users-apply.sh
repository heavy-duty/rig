#!/usr/bin/env bash
# rig users apply — converge named operator accounts from a declarative users
# file, on every class. Humans always enter as themselves and elevate via
# sudo: a shared root login is unattributable, so operators belong on servers
# too — class never gates this command, it only decides root SSH's fate AFTER
# users exist (close-root on human, kept as the control plane's automation
# door on server). Convergent: a second identical run changes nothing and
# says so.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=SCRIPTDIR/lib/users-config.sh
. "$HERE/lib/users-config.sh"

log()  { printf 'rig-users: %s\n' "$*"; }
warn() { printf 'rig-users: WARNING: %s\n' "$*" >&2; }
die()  { printf 'rig-users: ERROR: %s\n' "$1" >&2; exit "${2:-1}"; }

usage() {
  cat <<'EOF'
usage: rig users apply --file <path>

  --file <path>   users file (required; '-' reads it from stdin)

The file is line-based and bash-parseable on purpose — a rig box has no YAML
parser and no jq, and gets neither for this. Whitespace-separated: user,
comma-joined roles, then the SSH public key (the rest of the line). '#'
comments and blank lines are fine. Repeated username lines add authorized
keys; the roles must be identical on every line of one user.

  # user   roles       ssh public key
  dan      admin,box   ssh-ed25519 AAAA... dan@laptop
  maria    rig,box     ssh-ed25519 AAAA... maria@mac

roles:
  admin   group rig-admin — full NOPASSWD sudo
  rig     group rig       — NOPASSWD sudo for /usr/local/bin/rig only
  box     group incus     — Incus restricted tier, no sudo (box's setup-host
                            owns the Incus install; rig only asserts it)

All passwords stay locked, always — the SSH key at the door is the
authentication, and NOPASSWD sudo does not weaken it. Convergent: membership
in the three rig-managed groups is made exact (other groups are never
touched), authorized_keys becomes exactly the file's keys, and a user dropped
from the file is locked and stripped of the rig groups — home kept, never
deleted. Run as root.
EOF
}

# --- args (validated before the root check, so errors are testable) ---------
FILE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --file)
      [ $# -ge 2 ] || die "--file needs a value" 2
      FILE="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown flag: $1" 2 ;;
  esac
done
[ -n "$FILE" ] || die "--file <path> is required" 2

# stdin is read ONCE into a temp: the file is parsed for validation and then
# walked again to converge, and a pipe only plays once.
if [ "$FILE" = "-" ]; then
  STDIN_TMP="$(mktemp)"
  cat > "$STDIN_TMP"
  FILE="$STDIN_TMP"
fi
[ -r "$FILE" ] || die "cannot read users file: $FILE" 2

# File parsing is argument validation: every error in the file is reported in
# one pass, exit 2, still before the root check.
PARSED="$(parse_users_file "$FILE")" \
  || die "invalid users file: $FILE — every error is listed above; nothing was changed" 2

declare -A USER_ROLES=() USER_KEYS=()
USERS=()
NEED_SUDO=0
NEED_INCUS=0
while IFS='|' read -r u r k; do
  [ -n "$u" ] || continue
  if [ -z "${USER_ROLES[$u]:-}" ]; then
    USERS+=("$u")
    USER_ROLES[$u]="$r"
  fi
  USER_KEYS[$u]="${USER_KEYS[$u]:-}$k"$'\n'
  case ",$r," in *,admin,*|*,rig,*) NEED_SUDO=1 ;; esac
  case ",$r," in *,box,*) NEED_INCUS=1 ;; esac
done <<< "$PARSED"

# --- guards ------------------------------------------------------------------
[ "$(id -u)" -eq 0 ] || die "must run as root"

# Class is a note, never a refusal: #26's call is that operators belong on
# EVERY class — what differs is root SSH's fate once they exist.
case "$(read_role_marker /etc/rig/role)" in
  *class=server*) log "class=server: root SSH stays — it is the control plane's automation door" ;;
  *class=human*)  log "class=human: once your admin key works, 'rig users close-root' shuts the root door" ;;
  "")             warn "no /etc/rig/role marker — re-run rig bootstrap so this box knows what it is" ;;
esac

CHANGED=0

# --- sudo (only when some role actually grants through it) -------------------
if [ "$NEED_SUDO" -eq 1 ] && ! command -v sudo >/dev/null 2>&1; then
  log "installing sudo (admin/rig grants go through it)"
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq sudo
  CHANGED=1
fi

# --- groups ------------------------------------------------------------------
groupadd -f rig-admin
groupadd -f rig
# rig NEVER installs Incus: box's setup-host owns the daemon and its group. An
# absent incus group means that never ran — refuse with the pointer rather
# than conjure a group the (nonexistent) daemon would never consult.
if [ "$NEED_INCUS" -eq 1 ] && ! getent group incus >/dev/null; then
  die "a user carries role box but group incus is absent — install the box CLI and run 'box setup-host' first; rig never installs Incus"
fi

in_group() { id -nG "$1" 2>/dev/null | tr ' ' '\n' | grep -qx "$2"; }

# --- converge each user ------------------------------------------------------
for u in "${USERS[@]}"; do
  if ! id -u "$u" >/dev/null 2>&1; then
    useradd -m -s /bin/bash "$u"
    log "created user $u"
    CHANGED=1
  fi
  # Locked always, created or found: no password ever exists to guess or
  # rotate — the SSH key at the door is the authentication. Idempotent.
  usermod -L "$u"

  # Membership in the three rig-managed groups is made EXACT — added and
  # removed to match the file. Other groups are never touched: they are not
  # rig's to converge.
  roles="${USER_ROLES[$u]}"
  want=""
  case ",$roles," in *,admin,*) want="$want rig-admin" ;; esac
  case ",$roles," in *,rig,*)   want="$want rig" ;; esac
  case ",$roles," in *,box,*)   want="$want incus" ;; esac
  for g in rig-admin rig incus; do
    case " $want " in
      *" $g "*)
        if ! in_group "$u" "$g"; then
          usermod -aG "$g" "$u"
          log "added $u to $g"
          CHANGED=1
        fi ;;
      *)
        if in_group "$u" "$g"; then
          gpasswd -d "$u" "$g" >/dev/null
          log "removed $u from $g"
          CHANGED=1
        fi ;;
    esac
  done

  # authorized_keys becomes exactly the file's keys — cmp-guarded like every
  # file rig converges, so an unchanged file is a clean no-op.
  home="$(getent passwd "$u" | cut -d: -f6)"
  ugroup="$(id -gn "$u")"
  AK_TMP="$(mktemp)"
  printf '%s' "${USER_KEYS[$u]}" > "$AK_TMP"
  if ! cmp -s "$AK_TMP" "$home/.ssh/authorized_keys" 2>/dev/null; then
    mkdir -p "$home/.ssh"
    chmod 0700 "$home/.ssh"
    chown "$u:$ugroup" "$home/.ssh"
    install -m 0600 -o "$u" -g "$ugroup" "$AK_TMP" "$home/.ssh/authorized_keys"
    log "authorized_keys for $u: $(grep -c . "$AK_TMP") key(s)"
    CHANGED=1
  fi
  rm -f "$AK_TMP"
done

# --- previously managed users no longer in the file --------------------------
# The ledger is what lets a REMOVED user be found at all. Locked, not deleted:
# deleting frees the uid for reuse and orphans file ownership — attribution
# would rot. Home stays for the same reason.
LEDGER=/etc/rig/users
if [ -r "$LEDGER" ]; then
  while IFS= read -r prev; do
    [ -n "$prev" ] || continue
    case " ${USERS[*]:-} " in *" $prev "*) continue ;; esac
    id -u "$prev" >/dev/null 2>&1 || continue
    usermod -L "$prev"
    for g in rig-admin rig incus; do
      if in_group "$prev" "$g"; then gpasswd -d "$prev" "$g" >/dev/null; fi
    done
    warn "$prev is no longer in the file: locked and stripped of the rig groups (home kept — rig never deletes a user)"
    CHANGED=1
  done < "$LEDGER"
fi
LEDGER_TMP="$(mktemp)"
if [ "${#USERS[@]}" -gt 0 ]; then printf '%s\n' "${USERS[@]}" > "$LEDGER_TMP"; fi
if ! cmp -s "$LEDGER_TMP" "$LEDGER" 2>/dev/null; then
  mkdir -p /etc/rig
  install -m 0644 "$LEDGER_TMP" "$LEDGER"
  CHANGED=1
fi
rm -f "$LEDGER_TMP"

# --- sudoers -----------------------------------------------------------------
# Both group rules ship in one drop-in whether or not both roles are in use:
# the groups exist and the rules are inert without members. visudo gates the
# install because a bad file under /etc/sudoers.d can take down ALL of sudo —
# locking every admin out of the very escalation path apply just granted.
SUDOERS_TMP="$(mktemp)"
cat > "$SUDOERS_TMP" <<'EOF'
# Managed by `rig users apply` — do not edit; the next apply converges it.
%rig-admin ALL=(ALL:ALL) NOPASSWD: ALL
%rig ALL=(root) NOPASSWD: /usr/local/bin/rig
EOF
if command -v visudo >/dev/null 2>&1; then
  visudo -c -f "$SUDOERS_TMP" >/dev/null \
    || die "sudoers candidate failed validation — /etc/sudoers.d untouched; candidate kept at $SUDOERS_TMP for inspection"
  if ! cmp -s "$SUDOERS_TMP" /etc/sudoers.d/rig-roles 2>/dev/null; then
    install -m 0440 "$SUDOERS_TMP" /etc/sudoers.d/rig-roles
    log "sudoers role rules installed (/etc/sudoers.d/rig-roles)"
    CHANGED=1
  fi
  rm -f "$SUDOERS_TMP"
else
  # No sudo on the box means no role needed it (the install above would have
  # run otherwise): rules for a binary that is not there can wait for the
  # apply that brings a sudo-bearing role.
  rm -f "$SUDOERS_TMP"
  log "sudo not installed and no role needs it; skipping the sudoers drop-in"
fi

if [ "$CHANGED" -eq 0 ]; then
  log "already converged; no changes"
else
  log "converged ${#USERS[@]} user(s)"
fi
