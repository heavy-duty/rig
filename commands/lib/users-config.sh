#!/usr/bin/env bash
# Shared parsing for the rig users family. Sourced by the users-* commands and
# by the test harness against fixture files; never executed on its own.

# The users file is line-based and whitespace-separated on purpose: a
# rig-bootstrapped box has no YAML parser and no jq, and `read` parses this
# shape for free — same jq-free reason runner-config.sh greps JSON. One line
# per key:
#
#   # user   roles          ssh public key
#   dan      admin,box      ssh-ed25519 AAAA... dan@laptop
#
# Repeated username lines are additional authorized keys; the roles field must
# be IDENTICAL on each — a repeated line means "another key", never a quiet
# role edit hiding mid-file. '#' comments and blank lines are skipped.

# parse_users_file <path>
#
# Emits one normalized 'user|roles|key' line per key line on stdout. On ANY
# validation error: EVERY error goes to stderr, each with its line number, no
# stdout, return 1. All errors in one pass because a bad file should cost one
# fix cycle, not one round-trip per line.
#
# Refusals: unknown role (the valid set is named), differing roles across one
# user's lines, root as username (root's keys are class policy's business, not
# this file's), malformed line (fewer than 3 fields, or a key field that does
# not start with an SSH key type), duplicate identical key line.
parse_users_file() {
  local path="$1"
  local -a errs=() out=() rlist=()
  local -A first_roles=() seen=()
  local line u r k role ok n=0
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    if [[ "$line" =~ ^[[:space:]]*(#|$) ]]; then continue; fi
    read -r u r k <<< "$line"
    if [ -z "${k:-}" ]; then
      errs+=("line $n: malformed — expected 'user roles ssh-public-key' (3+ whitespace-separated fields)")
      continue
    fi
    case "$k" in
      ssh-*|ecdsa-*|sk-ssh-*|sk-ecdsa-*) ;;
      *)
        errs+=("line $n: malformed — key field must start with an SSH key type (ssh-..., ecdsa-...)")
        continue ;;
    esac
    if [ "$u" = "root" ]; then
      errs+=("line $n: 'root' is not a rig-managed user — this file names operators; root SSH's fate is class policy")
      continue
    fi
    ok=1
    IFS=',' read -ra rlist <<< "$r"
    for role in "${rlist[@]}"; do
      case "$role" in
        admin|rig|box) ;;
        *) errs+=("line $n: unknown role '$role' for $u (valid roles: admin rig box)"); ok=0 ;;
      esac
    done
    if [ -n "${first_roles[$u]:-}" ] && [ "${first_roles[$u]}" != "$r" ]; then
      errs+=("line $n: $u has roles '$r' here but '${first_roles[$u]}' earlier — repeated lines add keys, roles must be identical")
      ok=0
    fi
    if [ -z "${first_roles[$u]:-}" ]; then first_roles[$u]="$r"; fi
    if [ -n "${seen[$u|$k]:-}" ]; then
      errs+=("line $n: duplicate key line for $u (same key already on line ${seen[$u|$k]})")
      continue
    fi
    seen[$u|$k]="$n"
    if [ "$ok" -eq 1 ]; then out+=("$u|$r|$k"); fi
  done < "$path"
  if [ "${#errs[@]}" -gt 0 ]; then
    printf '%s\n' "${errs[@]}" >&2
    return 1
  fi
  if [ "${#out[@]}" -gt 0 ]; then printf '%s\n' "${out[@]}"; fi
  return 0
}

# read_role_marker <path> — the marker line bootstrap wrote
# (`role=... class=... host=... join=...`), or nothing when absent. NO policy
# here: what an absent marker or a given class MEANS is each caller's call
# (apply notes it, close-root refuses on it) — the lib only reads.
read_role_marker() {
  [ -r "$1" ] || return 0
  head -n1 "$1"
}
