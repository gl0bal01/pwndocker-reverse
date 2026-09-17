# Docker Image Optimization Audit: pwndocker-reverse

**Date:** 2026-07-31
**Image size:** 13.3 GB
**Base:** ubuntu:24.04
**Grade:** B+ (well-structured Dockerfile, ~1 GB of recoverable waste)

---

## Verdict

The Dockerfile is **well-built**. BuildKit cache mounts, secrets, download validation, pipefail, non-root user, CI with smoke test + Trivy gate + cosign signing — this is above 95% of Dockerfiles I see. Zero critical OS CVEs.

But it's 13.3 GB and ~1 GB of that is recoverable waste that leaked past the cache mounts. The tools themselves are genuinely big (retdec 1.5G, Ghidra 890M, Binary Ninja 827M, angr 593M) — that's irreducible. The waste is in caches, build artifacts, and git history that never got cleaned.

---

## Recoverable Waste (in priority order)

### 1. `/root/.cache` — 890 MB (BIGGEST WIN)

```
655M  /root/.cache/uv       ← pwndbg setup.sh (uv install)
214M  /root/.cache/opengrep  ← opengrep first-run cache
 22M  /root/.cache/pip       ← leftover despite cache mount
```

The `--mount=type=cache,target=/root/.cache/pip` prevents pip cache from entering layers, but pwndbg's `setup.sh` uses **uv** which caches to `/root/.cache/uv` — not covered by any cache mount. opengrep creates its own cache dir on install.

**Fix:** Add a cleanup step after the pwndbg and opengrep layers, or better, use cache mounts:

```dockerfile
# After pwndbg setup (line 77)
RUN git clone --depth=1 https://github.com/pwndbg/pwndbg /opt/pwndbg \
    && cd /opt/pwndbg && ./setup.sh \
    && rm -rf /root/.cache/uv

# After opengrep (line 70)
RUN --mount=type=secret,id=github_token \
    fetch-gh-release.sh opengrep/opengrep ...; \
    chmod +x /usr/local/bin/opengrep; \
    /usr/local/bin/opengrep --version >/dev/null; \
    rm -rf /root/.cache/opengrep
```

Or add a single sweep before the USER line:
```dockerfile
RUN rm -rf /root/.cache/uv /root/.cache/opengrep /root/.cache/pip
```

**Savings: ~890 MB**

### 2. `.git` directories from clones — 31 MB

Six git clones leave their `.git` dirs in the image:
```
25M  /opt/pwndbg/.git
4.4M /opt/gef/.git
360K /opt/libc-database/.git
308K /opt/hash-identifier/.git
264K /opt/peda/.git
204K /opt/villoc/.git
```

**Fix:** Remove `.git` after each clone+setup. For pwndbg specifically:
```dockerfile
RUN git clone --depth=1 https://github.com/pwndbg/pwndbg /opt/pwndbg \
    && cd /opt/pwndbg && ./setup.sh \
    && rm -rf /opt/pwndbg/.git /root/.cache/uv
```

Same pattern for gef, peda, villoc, libc-database, hash-identifier.

**Savings: ~31 MB**

### 3. pwndbg docs + tests — 37 MB

```
21M  /opt/pwndbg/docs
16M  /opt/pwndbg/tests
```

Not needed at runtime.

```dockerfile
&& rm -rf /opt/pwndbg/.git /opt/pwndbg/docs /opt/pwndbg/tests
```

**Savings: ~37 MB**

### 4. apt lists — 50 MB

`/var/lib/apt/lists` is 50 MB. The `--mount=type=cache,target=/var/lib/apt/lists` prevents it from entering the layer for the layers that use it, but the rizin OBS repo and ImHex deb layers do their own `apt-get update` without the cache mount fully flushing.

**Fix:** Add `&& rm -rf /var/lib/apt/lists/*` at the end of apt-based layers, or a single sweep:
```dockerfile
RUN rm -rf /var/lib/apt/lists/*
```

**Savings: ~50 MB**

### Total recoverable: ~1 GB (13.3 GB → ~12.3 GB, ~7.5% reduction)

---

## Architectural Observations (not bugs, just facts)

### Duplicate LLVM toolchain (~550 MB)
Both `llvm-17` (318M) and `llvm-18` are installed. llvm-17 is pulled in transitively by `libosmesa6` → `libgl1-mesa-dri` (Mesa depends on LLVM 17). Can't remove without breaking GL. This is an Ubuntu 24.04 packaging artifact, not your fault.

### pwndbg's standalone venv (645 MB)
pwndbg's `setup.sh` creates `/opt/pwndbg/.venv` (645 MB) — separate from the pipx pwntools venv (303 MB). Both install overlapping Python deps (capstone, etc.). This is pwndbg's design decision (uv-managed venv), not something you can easily deduplicate without breaking pwndbg updates.

### retdec (1.5 GB)
1.1 GB is in `share/` — decompiler signatures and support files. Required for functionality. Nothing to trim.

### angr (593 MB)
`angr_data` (208M) + z3 (107M) + sympy (74M) are all runtime dependencies. Irreducible.

---

## hadolint Warnings (17 total)

All warnings are **acceptable trade-offs** for a CTF tools bundle:

| Warning | Count | Verdict |
|---------|-------|---------|
| DL3008/DL3013 (pin apt/pip versions) | 8 | **Ignore.** You WANT latest tool versions in a CTF image. Pinning 45+ tools would be a maintenance nightmare with no real benefit. |
| DL4001 (curl + wget both used) | 5 | **Ignore.** Some download endpoints work better with one vs the other. Cosmetic. |
| DL3028 (pin gem versions) | 1 | Same — ignore. |
| DL3003 (use WORKDIR instead of cd) | 2 | Minor. Would clean up the Cutter extraction step. |
| DL3046 (useradd without -l) | 1 | **Worth fixing.** UID 1000 is low so this won't actually create a large `/var/log/lastlog`, but `-l` is free. |
| SC2015 (A && B \|\| C pattern) | 2 | False positive — your validation blocks are intentional. |

---

## What's Already Done Right

- ✅ BuildKit cache mounts (`/var/cache/apt`, `/root/.cache/pip`) — correct and consistent
- ✅ `SHELL ["/bin/bash", "-eo", "pipefail", "-c"]` — correct
- ✅ `--no-install-recommends` on every apt install
- ✅ Triple validation on downloads (size + format + smoke test)
- ✅ BuildKit secrets for GitHub token (never in layers)
- ✅ `.dockerignore` excludes secrets, `.git`, markdown
- ✅ Non-root `ctf` user with configurable UID/GID
- ✅ `userdel ubuntu` cleanup
- ✅ Layer ordering: system → Python → tools → user (correct volatility order)
- ✅ CI: build → smoke test (functional, not just `command -v`) → Trivy CRITICAL gate → push → cosign sign + SBOM
- ✅ Weekly rebuild schedule catches upstream breakage
- ✅ `/tmp` downloads cleaned within each layer
- ✅ `PWNDBG_NO_AUTOUPDATE=1` env to prevent runtime permission errors

---

## CI Security Notes

- **Trivy gate scope is correct.** Gating on CRITICAL OS CVEs only (not library CVEs in bundled tools) is the right call — the image ships 45+ tools with vendored deps you don't control.
- **Zero CRITICAL OS CVEs** found in this scan.
- Consider adding `--pkg-types os` to future-proof (Trivy deprecated `--vuln-type`).

---

## Priority Fix Order

1. **Add `rm -rf /root/.cache/*` before `USER ctf`** — single line, ~890 MB saved
2. Remove `.git` dirs from all 6 clones — ~31 MB
3. Remove pwndbg `docs/` and `tests/` — ~37 MB
4. Add `useradd -l` flag — free fix for DL3046
5. Optional: `rm -rf /var/lib/apt/lists/*` final sweep — ~50 MB

All five fixes are ~5 lines of Dockerfile changes for ~1 GB savings.
