# README Install-Channel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ensure the `main` README installs the same development tree whose CLI it documents.

**Architecture:** Keep installer channel behavior unchanged and correct the documentation entry point. Add one source-level regression assertion to the existing dependency-free CLI suite.

**Tech Stack:** Bash, Markdown, the existing `test/cli.sh` assertion harness.

## Global Constraints

- The stable latest-release and pinned-tag channels remain documented.
- No compatibility aliases or installer behavior changes.
- The regression must run inside the existing `bash test/cli.sh` CI step.

---

### Task 1: Align the README install channel

**Files:**
- Modify: `README.md`
- Test: `test/cli.sh`

**Interfaces:**
- Consumes: The existing `check` helper in `test/cli.sh`.
- Produces: A README quick-start command containing `RIG_REF=main bash`.

- [ ] **Step 1: Write the failing regression test**

Add this assertion near the existing README checks in `test/cli.sh`:

```bash
check "README: the main-branch quick start installs the documented tree" 0 "" \
  grep -qF 'curl -fsSL https://raw.githubusercontent.com/heavy-duty/rig/main/install.sh | RIG_REF=main bash' "$ROOT/README.md"
```

- [ ] **Step 2: Verify the test fails for the reported mismatch**

Run: `bash test/cli.sh`

Expected: one failure named `README: the main-branch quick start installs the documented tree` because the full command lacks `RIG_REF=main`.

- [ ] **Step 3: Make the minimal README correction**

Change the primary install command to:

```sh
curl -fsSL https://raw.githubusercontent.com/heavy-duty/rig/main/install.sh | RIG_REF=main bash
```

Explain that the README tracks `main`; retain examples for the default latest-release and pinned-tag channels, and delete the obsolete transitional notice about cutting 0.1.0.

- [ ] **Step 4: Verify the focused and full suites pass**

Run: `bash test/cli.sh`

Expected: all CLI assertions pass with zero failures.

Run: `bash test/release.sh`

Expected: all release assertions pass with zero failures.

- [ ] **Step 5: Commit**

```bash
git add README.md test/cli.sh
git commit -m "docs: align README quick start with main"
```
