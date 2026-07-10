#!/usr/bin/env bash
set -euo pipefail

# deployor installer — intended for: curl -fsSL .../install.sh | bash
#
# Downloads the deployor repo tarball, installs the whole tree under $DEST,
# and puts a `deployor` symlink on PATH via $BINDIR. Re-run any time to
# upgrade.

REPO="${DEPLOYOR_REPO:-claude-hdb/deployor}"
REF="${DEPLOYOR_REF:-main}"
DEST="${DEPLOYOR_HOME:-$HOME/.local/share/deployor}"
if [ "$(id -u)" -eq 0 ]; then
  BINDIR="${DEPLOYOR_BIN:-/usr/local/bin}"
else
  BINDIR="${DEPLOYOR_BIN:-$HOME/.local/bin}"
fi

log() { printf 'deployor-install: %s\n' "$*"; }
warn() { printf 'deployor-install: WARNING: %s\n' "$*" >&2; }
die() { printf 'deployor-install: ERROR: %s\n' "$*" >&2; exit 1; }

# --- prerequisites -----------------------------------------------------------
command -v curl >/dev/null 2>&1 || die "curl is required but was not found."
command -v tar  >/dev/null 2>&1 || die "tar is required but was not found."

# --- temp workspace ----------------------------------------------------------
TMPDIR="$(mktemp -d)"
cleanup() { rm -rf "$TMPDIR"; }
trap cleanup EXIT

URL="https://github.com/$REPO/archive/refs/heads/$REF.tar.gz"

log "installing deployor ($REPO@$REF)"
log "downloading $URL"
curl -fsSL "$URL" -o "$TMPDIR/deployor.tar.gz" \
  || die "failed to download $URL"

log "extracting archive"
tar -xzf "$TMPDIR/deployor.tar.gz" -C "$TMPDIR" \
  || die "failed to extract archive"

# GitHub archives extract to a single top-level dir like deployor-<ref>/
EXTRACTED="$(find "$TMPDIR" -maxdepth 1 -type d -name 'deployor-*' | head -n1)"
[ -n "$EXTRACTED" ] || die "could not find extracted deployor-* directory in archive"
[ -f "$EXTRACTED/bin/deployor" ] || die "archive does not contain bin/deployor — is $REPO@$REF correct?"

# --- atomically replace $DEST --------------------------------------------------
log "installing into $DEST"
rm -rf "$DEST"
mkdir -p "$(dirname "$DEST")"
mv "$EXTRACTED" "$DEST"

chmod +x "$DEST/bin/deployor" "$DEST"/commands/*.sh

# --- put deployor on PATH ------------------------------------------------------
mkdir -p "$BINDIR"
ln -sf "$DEST/bin/deployor" "$BINDIR/deployor"
log "linked $BINDIR/deployor -> $DEST/bin/deployor"

# --- PATH check ----------------------------------------------------------------
case ":$PATH:" in
  *":$BINDIR:"*) : ;;
  *)
    warn "$BINDIR is not on your PATH."
    warn "  add: export PATH=\"$BINDIR:\$PATH\""
    ;;
esac

log "done — try: deployor --help"
