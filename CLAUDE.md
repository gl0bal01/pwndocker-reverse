# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A Docker image for CTF pwn/reverse-engineering. Single Dockerfile (Ubuntu 24.04) with 45+ pre-installed tools, a non-root `ctf` user (UID configurable via build args), and GDB plugin switching.

## Build & Run

```bash
# Build
docker build -t pwndocker-reverse .

# Build with custom UID/GID (if host UID is not 1000)
docker build --build-arg CTF_UID=$(id -u) --build-arg CTF_GID=$(id -g) -t pwndocker-reverse .

# Run interactively (--cap-add=SYS_PTRACE needed for GDB)
docker run -it --rm --cap-add=SYS_PTRACE -v $(pwd):/ctf pwndocker-reverse

# Run with X11 (for Ghidra, Cutter, IDA, Binary Ninja, jd-gui, ImHex)
docker run -it --rm --cap-add=SYS_PTRACE -e DISPLAY=$DISPLAY -v /tmp/.X11-unix:/tmp/.X11-unix -v $(pwd):/ctf pwndocker-reverse
```

## Architecture

Single `Dockerfile` with 13 logical layers, organized by purpose:

| Layer | Contents |
|---|---|
| 1. Base | Ubuntu 24.04, system deps, multilib, X11/GL, JDK 21, QEMU user-mode + arm/aarch64 cross-libc sysroots, wabt, neovim, upx, p7zip |
| 2-4. Python | pwntools, angr, qiling, ropper, ROPgadget, binary-refinery, frida-tools, unblob (pipx). Libraries (capstone, keystone, unicorn, z3, yara, r2pipe) injected into pwntools venv |
| 5. Pip/Manual | binwalk, hash-identifier, opengrep |
| 6. Ruby | one_gadget, seccomp-tools |
| 7. GDB | pwndbg, GEF, PEDA + switcher (`gdb-pwndbg`, `gdb-gef`, `gdb-peda`, `gdb-switch`) |
| 8. RE | radare2, rizin, Cutter, Ghidra, retdec, IDA Free, Binary Ninja Free, ImHex, pycdc, jd-gui |
| 9. Fuzzing | AFL++, villoc |
| 10. Workflow | libc-database (`libc-find`, `libc-identify`, `libc-dump`), pwninit |
| 11-13. User | `ctf` user (UID/GID configurable via `CTF_UID`/`CTF_GID` build args, default 1000) with sudo, oh-my-zsh, pre-populated history, helper scripts, MOTD |

## File Structure

- `Dockerfile` — image definition
- `config/` — scripts copied into the image:
  - `gdb-pwndbg`, `gdb-gef`, `gdb-peda` — GDB launcher aliases
  - `gdb-switch` — change default GDB plugin (`gdb-switch {pwndbg|gef|peda}`)
  - `jd-gui` — java -jar wrapper for jd-gui
  - `start-cutter.sh`, `start-ghidra.sh` — GUI launchers with `$DISPLAY` check
  - `zsh_history` — pre-populated command history (Ctrl+R searchable)
- `.dockerignore` — excludes .git, docs, markdown from build context

## Key Design Decisions

- **pipx with PIPX_HOME=/opt/pipx and PIPX_BIN_DIR=/usr/local/bin** — tools installed as root are accessible to the `ctf` user
- **Libraries injected via `pipx inject pwntools`** — capstone, keystone, etc. are libraries (no CLI), so they go into pwntools' venv rather than standalone pipx installs
- **Cutter AppImage extracted** — Docker has no FUSE, so the AppImage is extracted to `/opt/cutter/`
- **Ghidra zip is platform-independent** — no "linux" in the asset name, jq filter uses `endswith(".zip")` + `test("PUBLIC")`
- **decomp2dbg deferred** — requires interactive `--install` step; noted in MOTD for manual setup
- **libc-database replaces Docker-in-Docker multi-glibc** — the original approach was broken by design
- **`CTF_UID`/`CTF_GID` build args** — default 1000 to match most Linux hosts; avoids X11 socket permission issues
- **`openjdk-21-jdk` (not headless)** — Ghidra needs AWT/Swing for its GUI
- **`--cap-add=SYS_PTRACE`** — required at runtime for GDB to attach to processes
- **`libc6-{armhf,arm64}-cross` baked in** — provides `/usr/arm-linux-gnueabihf` and `/usr/aarch64-linux-gnu` sysroots for `qemu-user -L`. Avoids per-container `apt-get` (broken in air-gapped CTF env) at ~50-80 MB cost
