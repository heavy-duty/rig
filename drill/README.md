# The drill — running it

`drill/drill.sh` is the instrument; `drills/` is the record it feeds
(see [drills/README.md](../drills/README.md) for what a record means and
how the three repos' drills relate). rig's drill asserts **convergence**:
a machine reaches its role, idempotently. This file is the procedure —
written down so a run is repeatable, not reconstructed from memory each
release (#105, and #107's debt).

## What you need

- **A throwaway Debian 13 machine** you can format, reached as root. The
  drill hardens its sshd, renames it, joins it to a tailnet, and installs
  box/Incus, Coolify and a GitHub runner on it. It is not coming back.
  The machine is its own reset — there is no teardown script and no need
  for one.
- **The pinned candidate refs, both of them.** `--rig-ref` and
  `--box-ref` are required; the harness refuses to run without them and
  refuses to continue if what installed disagrees with what was asked
  (`INSTALLED_FROM`, both trees). Until heavy-duty/rig#103 lands, both
  installers default to `main` when unpinned — which is exactly why the
  drill will not let a ref go unstated.
- **A single-use, tagged tailscale pre-auth key** in `TS_AUTHKEY`
  (`tag:local` for the default `staging-server` role — bootstrap refuses
  `tag:server` outside the control-plane shapes).
- **A users file** (`--users`) naming at least one operator — leg 1
  asserts the accounts and keys actually converged.
- **For leg 3** (runner lifecycle): a fork to register against
  (`--runner-repo you/rig`) carrying a `workflow_dispatch` workflow —
  default name `drill.yml` — whose job has `runs-on: [self-hosted, drill]`
  and does something trivial (`echo drilled`). Tokens come from an
  authenticated `gh`, or from `RUNNER_TOKEN` / `RUNNER_REMOVE_TOKEN`.
  Without a fork the leg **skips, loudly, into the record**.
- **For leg 4** (coolify): a version pin, `--coolify-version 4.1.2`.
  No pin, no leg — rig's own `coolify install` refuses to default a
  version and so does its drill. The skip is recorded.
- **A run ID** (`--run-id`) when this drill shares a substrate with
  box's or cast's — the shared ID is what lets the per-repo records be
  joined afterwards. Defaults to `drill-<date>`.

## Running it

From a checkout of this repo on the throwaway machine (the record lands
in the checkout's `drills/`):

```sh
TS_AUTHKEY=tskey-... bash drill/drill.sh \
  --rig-ref release/0.4.0 --box-ref release/0.10.0 \
  --users ./drill-users --run-id drill-2026-07-24-a \
  --coolify-version 4.1.2 --runner-repo you/rig --yes
```

It runs unattended from there. Legs execute as 1, 4, 2, 3 — Coolify's
installer is what puts Docker on the box and the db leg needs a daemon —
and the record lists them as they ran. A failing check never aborts the
run (`set -u`, no `-e`: a failing check is data), and the summary counts
passes, failures and skips separately.

## What it asserts

1. **Convergence, and idempotence.** `rig bootstrap <role> --users …`
   reaches the declared role, asserted on *effective* state — the marker,
   `sshd -T`, the granted tailnet tag, the operators' accounts and keys.
   Then bootstrap runs **again**, and the state captured before and after
   the re-run must diff **empty**. The diff is mechanical; "watched it
   not obviously break" is exactly what this leg exists to replace.
   Riding along, the `--host yes` assertions: the **pinned** box
   installed (`INSTALLED_FROM` matches `--box-ref`, fatal if not),
   `box doctor` passes. It stops there and says so in the output — the
   isolation boundary is **box's** drill's assertion, never rig's.
2. **db** — `test/db-integration.sh` from the *installed* tree: a real
   dump/restore round-trip. Its clean-skip contract (no Docker → loud
   skip, exit 0) survives into the record as a SKIP, never a pass.
3. **Runner lifecycle** — register against the fork, dispatch the drill
   workflow and watch the runner take it, deregister, and assert the
   box's registration is actually gone.
4. **Coolify** — installed at the pin, `AUTOUPDATE=false` landed in the
   effective `.env`, container running.

## The record

The run always ends by writing `drills/<version>.md` (the version is the
installed tree's own `VERSION`) — on failures too: **a failed drill is a
valid record**; the gate wants evidence, not success. Skipped legs are
named as not-run so the record can never read as a clean sweep. Commit
the file on the release branch; the `drill-recorded` guard reads that
file and nothing else.

The instrument's own honesty — the refusals, the skip accounting, the
capture-and-diff, the emitter — is `test/drill.sh`'s job, and CI runs it
on every PR. The live four-leg run is a release's job, once per cycle.
