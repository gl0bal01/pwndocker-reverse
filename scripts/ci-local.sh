#!/usr/bin/env bash
# shellcheck disable=SC2317  # step_* functions are invoked indirectly via run()
# Local mirror of .github/workflows/build.yml (job "build"), same order.
# Runs every step (no stop at first failure), prints a pass/fail summary,
# exits non-zero if any step failed. Add a CI step -> add it here too.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

TRIVY_VERSION=v0.70.0            # default pinned by aquasecurity/trivy-action@v0.36.0
IMAGE=smoke-test:local           # tag used by the workflow (also what trivy scans)
LOGDIR=$(mktemp -d -t ci-local.XXXXXX)
echo "logs: $LOGDIR"

declare -a RESULTS
run() { # run <name> <function>
  local name=$1 fn=$2
  echo "=== $name"
  if "$fn" >"$LOGDIR/$name.log" 2>&1; then RESULTS+=("PASS     $name  ($LOGDIR/$name.log)")
  else RESULTS+=("FAIL     $name  ($LOGDIR/$name.log)"); fi
}
skip() { RESULTS+=("SKIPPED  $1  (CI-only: $2)"); }

# --- Lint shell scripts: ludeeus/action-shellcheck@2.0.0, scandir: config,
# defaults: format=gcc, no severity filter, excludes .git/*, *.go, mvnw.
step_shellcheck() {
  local files=() f
  while IFS= read -r f; do
    case $f in *.sh|*.bash|*.ksh|*.bats) files+=("$f"); continue;; esac
    head -n1 "$f" | grep -Eq '^#!.*\b(ba|k|da)?sh\b' && files+=("$f")
  done < <(find config -type f ! -path '*./.git/*' ! -path '*.go' ! -path '*/mvnw' | sort)
  echo "files: ${files[*]}"
  shellcheck --format=gcc "${files[@]}"
}

# --- Build (local load for smoke test): secret github_token as in CI.
step_build() {
  local tok; tok=$(gh auth token 2>/dev/null || true)
  GITHUB_TOKEN=$tok docker buildx build --load -t "$IMAGE" -t pwndocker-reverse:ci-local \
    --secret id=github_token,env=GITHUB_TOKEN .
}

# --- Smoke test: copied 1:1 from the workflow.
step_smoke() {
  docker run --rm "$IMAGE" bash -c '
            set -eo pipefail
            for bin in pwn gdb-pwndbg gdb-gef gdb-peda r2 rizin ghidra \
                       ROPgadget ropper afl-fuzz frida one_gadget \
                       opengrep pwninit cutter ida64 binaryninja \
                       pycdc jd-gui binwalk imhex; do
              command -v "$bin" >/dev/null || { echo "MISSING: $bin"; exit 1; }
            done
            # Functional checks (only quick, non-interactive invocations)
            r2 -qv >/dev/null
            rizin -qv >/dev/null
            opengrep --version >/dev/null
            pwninit --help >/dev/null
            one_gadget --version >/dev/null
            ROPgadget --version >/dev/null
            # afl-fuzz -h exits non-zero AND grep -q closes the pipe early
            # (SIGPIPE), so wrap to satisfy `set -eo pipefail`.
            ( afl-fuzz -h 2>&1 || true ) | grep -qi afl
            pwn version >/dev/null
            pwn checksec /bin/ls >/dev/null
            # pwntools lives in its pipx venv; bare python3 cannot import it.
            /opt/pipx/venvs/pwntools/bin/python -c "from pwn import *; from capstone import *; from keystone import *; from unicorn import *"
            # -nx skips ~/.gdbinit so we test gdb itself, not the pwndbg plugin.
            gdb-multiarch -nx --batch -ex quit >/dev/null
            # Loads the pwndbg plugin to confirm it imports cleanly.
            gdb-pwndbg --batch -ex quit >/dev/null
            echo "Smoke test passed"
          '
}

# --- Trivy: CRITICAL OS CVEs with a fix only (trivy-action@v0.36.0 inputs).
step_trivy() {
  mkdir -p "${HOME}/.cache/trivy"
  docker run --rm -v /var/run/docker.sock:/var/run/docker.sock:ro \
    -v "${HOME}/.cache/trivy:/root/.cache/trivy" \
    "aquasec/trivy:${TRIVY_VERSION#v}" image --timeout 30m --skip-version-check --format table --exit-code 1 \
    --ignore-unfixed --severity CRITICAL --pkg-types os "$IMAGE"
}

run shellcheck step_shellcheck
run build step_build
run smoke-test step_smoke
run trivy step_trivy
skip "ghcr-login" "needs GITHUB_TOKEN/registry write"
skip "extract-metadata" "only feeds the push tags"
skip "push-ghcr(sbom,provenance)" "pushes to registry"
skip "cosign-sign" "keyless signing needs GitHub OIDC"

echo; echo "===== SUMMARY (logs: $LOGDIR) ====="
printf '%s\n' "${RESULTS[@]}"
printf '%s\n' "${RESULTS[@]}" | grep -q '^FAIL' && exit 1
exit 0
