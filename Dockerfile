# syntax=docker/dockerfile:1
FROM ubuntu:24.04
LABEL maintainer="gl0bal01 <gl0bal01@users.noreply.github.com>"

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=UTC \
    PIPX_HOME=/opt/pipx \
    PIPX_BIN_DIR=/usr/local/bin \
    PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin

# Layer 1: System packages
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
        build-essential gcc-multilib g++-multilib liblzma-dev elfutils \
        wabt \
        libc6-i386 libc6-dev-i386 \
        gdb-multiarch patchelf strace ltrace \
        xxd binutils file less hexedit \
        curl wget socat netcat-openbsd nmap tcpdump tshark lsof gnupg \
        git unzip p7zip-full jq tmux zsh vim neovim sudo procps bsdmainutils libfuse2 zstd upx \
        x11-apps libx11-dev libgl1 libegl1 libegl-mesa0 libglx-mesa0 libosmesa6 libopengl0 \
        libxcb-icccm4 libxcb-image0 libxcb-keysyms1 libxcb-render-util0 \
        libxcb-render0 libxcb-shape0 libxcb-xinerama0 libxcb-xkb1 \
        libxkbcommon-x11-0 libxkbcommon0 \
        openjdk-21-jdk \
        qemu-user qemu-user-static \
        llvm clang lld \
        python3 python3-dev python3-pip python3-venv pipx \
        ruby-dev

# Layer 2: Python pwn tools (pipx) — merged into fewer layers
RUN --mount=type=cache,target=/root/.cache/pip \
    pipx install pwntools \
    && pipx install ropper \
    && pipx install ropgadget \
    && pipx install angr \
    && pipx install qiling

# Layer 3: Python libraries (injected into pwntools venv)
RUN --mount=type=cache,target=/root/.cache/pip \
    pipx inject pwntools capstone keystone-engine unicorn z3-solver yara-python r2pipe

# Layer 4: Python CLI tools (pipx)
RUN --mount=type=cache,target=/root/.cache/pip \
    REFINERY_PREFIX='r.' pipx install 'binary-refinery' \
    && pipx install frida-tools \
    && pipx install unblob

# Layer 5: Python tools (pip/manual)
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --break-system-packages binwalk

RUN git clone --depth=1 https://github.com/blackploit/hash-identifier /opt/hash-identifier \
    && ln -s /opt/hash-identifier/hash-id.py /usr/local/bin/hash-identifier \
    && chmod +x /opt/hash-identifier/hash-id.py

RUN --mount=type=secret,id=github_token \
    curl -s -H "Authorization: token $(cat /run/secrets/github_token 2>/dev/null || true)" https://api.github.com/repos/opengrep/opengrep/releases/latest \
    | jq -r '.assets[] | select(.name == "opengrep_manylinux_x86") | .browser_download_url' \
    | head -1 | xargs wget -qO /usr/local/bin/opengrep \
    && chmod +x /usr/local/bin/opengrep

# Layer 6: Ruby tools
RUN gem install one_gadget seccomp-tools

# Layer 7: GDB plugins
RUN git clone --depth=1 https://github.com/pwndbg/pwndbg /opt/pwndbg \
    && cd /opt/pwndbg && ./setup.sh

RUN git clone --depth=1 https://github.com/hugsy/gef /opt/gef \
    && git clone --depth=1 https://github.com/longld/peda /opt/peda

# GDB shared init (defines init-pwndbg, init-gef, init-peda commands)
COPY config/gdbinit /etc/gdb/gdbinit.d/init-plugins

# GDB switcher and wrapper scripts
COPY config/gdb-pwndbg config/gdb-gef config/gdb-peda config/gdb-switch /usr/local/bin/
RUN chmod +x /usr/local/bin/gdb-pwndbg /usr/local/bin/gdb-gef /usr/local/bin/gdb-peda /usr/local/bin/gdb-switch

# Layer 8: Disassemblers & Decompilers

# radare2 (apt — pre-built)
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends radare2

# rizin (OBS repo — pre-built)
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    echo 'deb http://download.opensuse.org/repositories/home:/RizinOrg/xUbuntu_24.04/ /' > /etc/apt/sources.list.d/rizin.list \
    && curl -fsSL https://download.opensuse.org/repositories/home:RizinOrg/xUbuntu_24.04/Release.key \
       | gpg --dearmor -o /etc/apt/trusted.gpg.d/rizin.gpg \
    && apt-get update && apt-get install -y --no-install-recommends rizin

# Cutter (rizin GUI) — extracted AppImage for Docker compatibility
RUN --mount=type=secret,id=github_token \
    curl -s -H "Authorization: token $(cat /run/secrets/github_token 2>/dev/null || true)" https://api.github.com/repos/rizinorg/cutter/releases/latest \
    | jq -r '.assets[] | select(.name | test("Linux-x86_64\\.AppImage$")) | .browser_download_url' \
    | head -1 | xargs wget -qO /tmp/cutter.AppImage \
    && chmod +x /tmp/cutter.AppImage \
    && cd /tmp && ./cutter.AppImage --appimage-extract \
    && mv squashfs-root /opt/cutter \
    && ln -s /opt/cutter/AppRun /usr/local/bin/cutter \
    && rm /tmp/cutter.AppImage

# Ghidra (platform-independent zip)
RUN --mount=type=secret,id=github_token \
    curl -s -H "Authorization: token $(cat /run/secrets/github_token 2>/dev/null || true)" https://api.github.com/repos/NationalSecurityAgency/ghidra/releases/latest \
    | jq -r '.assets[] | select(.name | endswith(".zip")) | select(.name | test("PUBLIC")) | .browser_download_url' \
    | head -1 | xargs wget -qO /tmp/ghidra.zip \
    && unzip /tmp/ghidra.zip -d /opt \
    && mv /opt/ghidra_* /opt/ghidra \
    && ln -s /opt/ghidra/ghidraRun /usr/local/bin/ghidra \
    && rm /tmp/ghidra.zip

# retdec (pre-built, no wrapper dir in archive)
RUN --mount=type=secret,id=github_token \
    mkdir -p /opt/retdec \
    && curl -s -H "Authorization: token $(cat /run/secrets/github_token 2>/dev/null || true)" https://api.github.com/repos/avast/retdec/releases/latest \
    | jq -r '.assets[] | select(.name | test("[Ll]inux.*tar")) | .browser_download_url' \
    | head -1 | xargs wget -qO /tmp/retdec.tar.xz \
    && tar xf /tmp/retdec.tar.xz -C /opt/retdec \
    && ln -s /opt/retdec/bin/* /usr/local/bin/ \
    && rm /tmp/retdec.tar.xz

# IDA Free (Wayback archive — original URL removed by Hex-Rays)
RUN wget -qO /tmp/idafree_linux.run "https://web.archive.org/web/20240921184600if_/https://out7.hex-rays.com/files/idafree84_linux.run" \
    && chmod +x /tmp/idafree_linux.run \
    && /tmp/idafree_linux.run --mode unattended --prefix /opt/idafree \
    && ln -s /opt/idafree/ida64 /usr/local/bin/ida64 \
    && rm /tmp/idafree_linux.run

# Binary Ninja Free
RUN wget -qO /tmp/binaryninja_free.zip "https://cdn.binary.ninja/installers/binaryninja_free_linux.zip" \
    && unzip /tmp/binaryninja_free.zip -d /opt \
    && ln -s /opt/binaryninja/binaryninja /usr/local/bin/binaryninja \
    && rm /tmp/binaryninja_free.zip

# ImHex (hex editor for RE)
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    --mount=type=secret,id=github_token \
    curl -s -H "Authorization: token $(cat /run/secrets/github_token 2>/dev/null || true)" https://api.github.com/repos/WerWolv/ImHex/releases/latest \
    | jq -r '.assets[] | select(.name | test("Ubuntu.*24\\.04.*\\.deb$")) | .browser_download_url' \
    | head -1 | xargs wget -qO /tmp/imhex.deb \
    && apt-get update && apt-get install -y --no-install-recommends /tmp/imhex.deb \
    && rm /tmp/imhex.deb

# pycdc (pre-built from decompyle-builds)
RUN --mount=type=secret,id=github_token \
    curl -s -H "Authorization: token $(cat /run/secrets/github_token 2>/dev/null || true)" https://api.github.com/repos/extremecoders-re/decompyle-builds/releases/latest \
    | jq -r '.assets[] | select(.name == "pycdc.x86_64") | .browser_download_url' \
    | head -1 | xargs wget -qO /usr/local/bin/pycdc \
    && curl -s -H "Authorization: token $(cat /run/secrets/github_token 2>/dev/null || true)" https://api.github.com/repos/extremecoders-re/decompyle-builds/releases/latest \
    | jq -r '.assets[] | select(.name == "pycdas.x86_64") | .browser_download_url' \
    | head -1 | xargs wget -qO /usr/local/bin/pycdas \
    && chmod +x /usr/local/bin/pycdc /usr/local/bin/pycdas

# jd-gui (Java decompiler)
COPY config/jd-gui /usr/local/bin/jd-gui
RUN mkdir -p /opt/jd-gui \
    && wget -qO /opt/jd-gui/jd-gui.jar \
       "https://github.com/java-decompiler/jd-gui/releases/download/v1.6.6/jd-gui-1.6.6.jar" \
    && chmod +x /usr/local/bin/jd-gui

# Layer 9: Fuzzing & Dynamic Analysis

# AFL++ (apt — pre-built)
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends afl++

# villoc (heap visualization)
RUN git clone --depth=1 https://github.com/wapiflapi/villoc /opt/villoc \
    && ln -s /opt/villoc/villoc.py /usr/local/bin/villoc \
    && chmod +x /opt/villoc/villoc.py

# Layer 10: Pwn Workflow Tools

# libc-database (scripts only — run "cd /opt/libc-database && ./get ubuntu" at runtime to download libcs)
RUN git clone --depth=1 https://github.com/niklasb/libc-database /opt/libc-database \
    && ln -s /opt/libc-database/find /usr/local/bin/libc-find \
    && ln -s /opt/libc-database/identify /usr/local/bin/libc-identify \
    && ln -s /opt/libc-database/dump /usr/local/bin/libc-dump

# pwninit
RUN --mount=type=secret,id=github_token \
    curl -s -H "Authorization: token $(cat /run/secrets/github_token 2>/dev/null || true)" https://api.github.com/repos/io12/pwninit/releases/latest \
    | jq -r '.assets[] | select(.name == "pwninit") | .browser_download_url' \
    | head -1 | xargs wget -qO /usr/local/bin/pwninit \
    && chmod +x /usr/local/bin/pwninit

# Layer 11: User Setup & Shell
ARG CTF_UID=1000
ARG CTF_GID=1000
RUN userdel -r ubuntu 2>/dev/null; groupdel ubuntu 2>/dev/null; true \
    && groupadd -f -g ${CTF_GID} ctf \
    && useradd -m -s /bin/zsh -u ${CTF_UID} -g ${CTF_GID} -G sudo ctf \
    && echo "ctf ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers \
    && mkdir -p /ctf && chown ctf:ctf /ctf

# MOTD with post-build notes
RUN echo '\n=== pwndocker-reverse ===\nNote: Run "decomp2dbg --install" for Ghidra/Cutter GDB integration.\nUse "gdb-switch {pwndbg|gef|peda}" to change default GDB plugin.\n' > /etc/motd

# Layer 12: Config files and helper scripts
COPY config/zsh_history /home/ctf/.zsh_history
COPY config/start-cutter.sh config/start-ghidra.sh /usr/local/bin/
RUN chown ctf:ctf /home/ctf/.zsh_history \
    && chmod +x /usr/local/bin/start-cutter.sh /usr/local/bin/start-ghidra.sh

USER ctf

# oh-my-zsh
RUN sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

# Set default GDB plugin to pwndbg
RUN gdb-switch pwndbg

WORKDIR /ctf
CMD ["zsh"]
