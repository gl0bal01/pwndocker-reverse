#!/usr/bin/env bash
# Install the pre-push hook that runs scripts/ci-local.sh.
# Override for an emergency push: SKIP_CI_LOCAL=1 git push
set -euo pipefail
root=$(git rev-parse --show-toplevel)
cat >"$root/.git/hooks/pre-push" <<'HOOK'
#!/usr/bin/env bash
[ "${SKIP_CI_LOCAL:-}" = 1 ] && { echo "pre-push: SKIP_CI_LOCAL=1, skipping local CI"; exit 0; }
exec "$(git rev-parse --show-toplevel)/scripts/ci-local.sh"
HOOK
chmod +x "$root/.git/hooks/pre-push"
echo "installed $root/.git/hooks/pre-push"
