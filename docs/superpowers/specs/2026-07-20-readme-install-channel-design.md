# README install-channel alignment

## Problem

The landing-page README describes the unreleased CLI on `main`, including
the `*-server` and `*-box` role names, but its first install command selects
the latest release. At present that is 0.2.0, whose CLI accepts the retired
role names instead. A reader following the quick start therefore installs a
CLI that rejects the README's examples.

## Decision

The README is documentation for the branch that contains it. Its primary
install command will explicitly set `RIG_REF=main`, making the installed tree
match the commands documented below it. The stable channel remains documented
next to the development and pinned channels, but is no longer presented as the
matching prerequisite for the `main` README's quick start.

The obsolete pre-0.1.0 transitional notice will be removed. No installer
behavior, role compatibility aliases, or release process will change.

## Regression protection

The dependency-free CLI test suite will assert that the README's full GitHub
installer command opts into `RIG_REF=main`. This directly protects the broken
onboarding path without trying to infer semantic compatibility between every
README example and every historical release.

## Acceptance criteria

- The first complete installer command in `README.md` installs `main`.
- The README still explains how to install the latest release and a pinned tag.
- The stale “until 0.1.0 is cut” notice is absent.
- `bash test/cli.sh` fails on the old README and passes after the documentation
  correction.

