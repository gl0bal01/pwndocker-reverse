# pwndocker-reverse

[![Build](https://github.com/gl0bal01/pwndocker-reverse/actions/workflows/build.yml/badge.svg)](https://github.com/gl0bal01/pwndocker-reverse/actions)
[![Docker](https://img.shields.io/badge/docker-ubuntu%2024.04-blue?logo=docker)](https://ghcr.io/gl0bal01/pwndocker-reverse)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](https://github.com/gl0bal01/pwndocker-reverse/blob/master/LICENSE)

A single Dockerfile that bundles 45+ CTF pwn and reverse-engineering tools into one Ubuntu 24.04 image. Includes 7 disassemblers and decompilers (Ghidra, IDA Free, Binary Ninja Free, Cutter, radare2, rizin, retdec), 3 GDB plugins with instant switching, and a pre-populated command history.

IDA Free and Binary Ninja Free are installed from their vendors' free-tier downloads. Users are responsible for compliance with each vendor's license terms.

## Why?

Given Docker on the host, this image packages 45+ tools that would otherwise require separate installation steps -- Python packages, Java-based disassemblers, GDB plugins, and Ruby gems -- into a single Dockerfile.

## Quick Start

```bash
# Pull from GHCR (fastest)
docker pull ghcr.io/gl0bal01/pwndocker-reverse:latest
docker run -it --rm --cap-add=SYS_PTRACE -v $(pwd):/ctf ghcr.io/gl0bal01/pwndocker-reverse

# Or build locally
docker build -t pwndocker-reverse .
docker run -it --rm --cap-add=SYS_PTRACE -v $(pwd):/ctf pwndocker-reverse

# With X11 forwarding (requires X11 server on host -- see GUI tools section)
docker run -it --rm --cap-add=SYS_PTRACE \
  -e DISPLAY=$DISPLAY \
  -v /tmp/.X11-unix:/tmp/.X11-unix \
  -v $(pwd):/ctf pwndocker-reverse

# Custom UID/GID (if your host UID is not 1000)
docker build --build-arg CTF_UID=$(id -u) --build-arg CTF_GID=$(id -g) -t pwndocker-reverse .
```

You land in `/ctf` as user `ctf` with sudo, oh-my-zsh, and 78 pre-loaded history entries searchable via Ctrl+R.

## Reproducibility & Verification

The image is **rebuilt every Monday** from `master` so `latest` stays fresh against upstream tool releases. Three ways to consume it:

```bash
# Rolling (weekly fresh) — convenient, not reproducible
docker pull ghcr.io/gl0bal01/pwndocker-reverse:latest

# Dated weekly snapshot — fresh but frozen, good for a CTF weekend
docker pull ghcr.io/gl0bal01/pwndocker-reverse:weekly-20260427    # replace with latest weekly-YYYYMMDD tag

# Immutable digest — fully reproducible, pin this in team setups / scripts
docker pull ghcr.io/gl0bal01/pwndocker-reverse@sha256:<digest>
```

Every pushed image is signed with [cosign](https://github.com/sigstore/cosign) (keyless, via GitHub OIDC) and ships with an SBOM + SLSA provenance attestation. Verify before running in sensitive contexts:

```bash
cosign verify ghcr.io/gl0bal01/pwndocker-reverse:latest \
  --certificate-identity-regexp 'https://github.com/gl0bal01/pwndocker-reverse/.*' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com

# Inspect the SBOM
docker buildx imagetools inspect ghcr.io/gl0bal01/pwndocker-reverse:latest --format '{{ json .SBOM }}'
```

## Tools

| Category | Tools |
|---|---|
| **Exploit Dev** | pwntools, angr, ROPgadget, ropper, one_gadget, seccomp-tools, qiling, pwninit |
| **Libraries** | capstone, keystone, unicorn, z3, yara, r2pipe *(in pwntools venv)* |
| **Disassemblers / Decompilers** | Ghidra, IDA Free, Binary Ninja Free, Cutter (rizin), retdec, radare2, rizin, pycdc, jd-gui |
| **GDB** | pwndbg, GEF, PEDA + switcher scripts |
| **Hex Editors** | ImHex, hexedit |
| **Fuzzing** | AFL++ |
| **Dynamic** | frida, strace, ltrace, villoc |
| **Workflow** | libc-database, pwninit, patchelf, binwalk, unblob, upx |
| **Analysis** | binary-refinery, opengrep, hash-identifier |
| **Networking** | socat, ncat, tcpdump, tshark, nmap |
| **Editors** | vim, neovim |
| **System** | QEMU user-mode (+ arm/aarch64 cross-libc sysroots), wabt, gdb-multiarch, p7zip, oh-my-zsh |

## Usage

### Typical CTF workflow

```bash
# Start the container with your challenge directory mounted
docker run -it --rm --cap-add=SYS_PTRACE -v $(pwd):/ctf pwndocker-reverse

# Analyze the binary
checksec --file=./challenge
file ./challenge
strings -n 8 ./challenge
r2 -A ./challenge

# Find gadgets
ROPgadget --binary ./challenge --ropchain
ropper --file ./challenge --search "pop rdi"
one_gadget ./libc.so.6

# Patch the binary to use the provided libc
pwninit --bin ./challenge --libc ./libc.so.6
patchelf --set-interpreter ./ld-linux-x86-64.so.2 --set-rpath . ./challenge

# Write and run your exploit
python3 exploit.py
```

### GDB plugin switching

Three plugins installed, instantly switchable:

```bash
gdb-pwndbg ./binary       # launch with pwndbg
gdb-gef ./binary           # launch with GEF
gdb-peda ./binary          # launch with PEDA
gdb-switch pwndbg          # set default for plain `gdb`
```

### GUI tools (Ghidra, IDA, Cutter, Binary Ninja, jd-gui)

Requires X11 forwarding. On Linux this works natively; on macOS install [XQuartz](https://www.xquartz.org/), on Windows install [VcXsrv](https://sourceforge.net/projects/vcxsrv/) or use WSLg.

```bash
docker run -it --rm --cap-add=SYS_PTRACE \
  -e DISPLAY=$DISPLAY \
  -v /tmp/.X11-unix:/tmp/.X11-unix \
  -v $(pwd):/ctf pwndocker-reverse

# Inside the container
ghidra                         # launch Ghidra
ida64 ./binary                 # launch IDA Free
binaryninja ./binary           # launch Binary Ninja Free
start-cutter.sh ./binary       # launch Cutter (checks $DISPLAY)
jd-gui ./app.jar               # launch Java decompiler
```

### Disassemblers (CLI)

```bash
r2 -A ./binary                 # radare2 with analysis
rizin -A ./binary              # rizin with analysis
retdec-decompiler ./binary     # decompile to C
pycdc ./script.pyc             # decompile Python bytecode
```

### Fuzzing

```bash
afl-fuzz -i input/ -o output/ -- ./binary @@
afl-cmin -i input/ -o input_min/ -- ./binary @@
```

### Dynamic analysis

```bash
frida -f ./binary -l script.js           # hook functions at runtime
frida-trace -f ./binary -i "malloc"      # trace calls
strace -f ./binary                       # system call trace
ltrace ./binary                          # library call trace
villoc /tmp/ltrace.out > heap.html       # heap visualization
```

### Libc identification

libc-database is installed with scripts only. Download libcs on demand:

```bash
# First time: download libc database (run once)
cd /opt/libc-database && sudo PATH=/usr/bin:$PATH ./get ubuntu debian

# Then use it
libc-find d8 e9 31 60
libc-identify ./libc.so.6
libc-dump ./libc.so.6 system __free_hook
```

### Emulation

ARM and AARCH64 cross-libc sysroots are pre-installed, so dynamic binaries run out of the box.

```bash
# Static binaries: no sysroot needed
qemu-arm ./arm_static_binary
qemu-aarch64 ./aarch64_static_binary

# Dynamic binaries: -L points at the cross-libc sysroot baked into the image
qemu-arm     -L /usr/arm-linux-gnueabihf ./arm_binary
qemu-aarch64 -L /usr/aarch64-linux-gnu   ./aarch64_binary

# Run under GDB server on :1234, then attach with `gdb-multiarch -ex 'target remote :1234'`
qemu-aarch64 -g 1234 -L /usr/aarch64-linux-gnu ./aarch64_binary
```

### Networking

```bash
socat TCP-LISTEN:1337,reuseaddr,fork EXEC:./binary    # host a binary
ncat -lvp 1337                                          # listen
tcpdump -i any -w capture.pcap                          # capture traffic
tshark -r capture.pcap                                  # analyze pcap
```

## Pre-Populated History

Hit Ctrl+R and search. 78 commands covering all installed tools are already in your history -- no need to remember syntax.

## Project Structure

```
Dockerfile              # Single-file image definition (13 layers)
config/
  gdb-pwndbg            # GDB launcher (pwndbg)
  gdb-gef                # GDB launcher (GEF)
  gdb-peda               # GDB launcher (PEDA)
  gdb-switch             # Set default GDB plugin
  jd-gui                 # java -jar wrapper
  start-cutter.sh        # GUI launcher with $DISPLAY check
  start-ghidra.sh        # GUI launcher with $DISPLAY check
  zsh_history            # Pre-populated command history
.dockerignore
```

## License

[MIT](https://github.com/gl0bal01/pwndocker-reverse/blob/master/LICENSE)
