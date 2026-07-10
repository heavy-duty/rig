# deployor

A CLI that turns a **pristine Debian server into a hardened, tailnet-joined
node** — one curl, one command. A second command installs a version-pinned
Coolify on a control-plane box.

Philosophy (shared with [claudebox](https://github.com/heavy-duty/claudebox)):
**public tool, private state**. deployor carries plumbing logic only — no
hostnames, no bindings, no secrets, nothing about *your* infrastructure. It
takes arguments, does its work, and stores no credential, ever.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/claude-hdb/deployor/main/install.sh | bash
```

Installs the tree to `~/.local/share/deployor` and links `deployor` onto your
PATH (`/usr/local/bin` when root). Re-run any time to upgrade.

## Commands

### `deployor bootstrap <control-plane|workload>`

Run as root on the fresh box (over SSH). Convergent — safe to re-run; a
second run changes nothing.

```sh
deployor bootstrap control-plane --hostname my-coolify-box
deployor bootstrap workload --hostname my-prod-box
```

- `--hostname <name>` — tailnet hostname (default: the role name)
- `--ts-tag <tag>` — tailnet tag to advertise (default: `tag:server`)

What it does: installs `curl ca-certificates unattended-upgrades` (and
enables periodic unattended upgrades); writes an sshd hardening drop-in
(`PermitRootLogin prohibit-password`, `PasswordAuthentication no`); installs
tailscale and joins your tailnet.

**The pre-auth key:** provide it via the `TS_AUTHKEY` env var or type it at
the interactive prompt. Use a **single-use, tagged, short-expiry** key. It
lives in process memory only — deployor never writes a credential to disk.

The two roles are identical today except the default hostname; they exist
because control-plane and workload boxes diverge over time, and because the
next command applies to exactly one of them.

### `deployor coolify install --version <pin>`

Control-plane box only. Installs Coolify at exactly the pinned version with
`AUTOUPDATE=false` — your deploy tooling is verified against an API surface;
the platform must never move underneath it on its own. Upgrading is an
explicit re-run with a new pin. The pin is required; there is no default.

## What deployor deliberately does NOT do

- **Provider firewalls** — Docker publishes ports past host firewalls, so
  the real boundary is your cloud provider's firewall, configured outside
  this tool.
- **Fetch your config** — boxes never receive repo credentials. Everything
  deployor needs arrives as arguments or an interactive prompt.
- **Manage deployments** — deploy manifests/executors are separate concerns.
  (Planned: the `apply`/`diff` executor half joins deployor as commands that
  run on operator machines, never on boxes.)

## Testing

`bash test/cli.sh` (dependency-free assertions) + shellcheck run in CI. The
end-to-end rehearsal is a throwaway VM/container: pristine Debian → install →
`bootstrap workload` with a real single-use key → assert the sshd drop-in,
tailnet join, and a no-op second run → destroy, remove the node from the
tailnet.
