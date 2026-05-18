#!/bin/bash
# Fetch a GitHub release asset URL through the API and download it.
# Reads optional auth token from /run/secrets/github_token (BuildKit secret).
# Usage: fetch-gh-release.sh <owner/repo> <jq-filter> <output-path>
#   <jq-filter> must yield browser_download_url string(s); first match used.
set -eo pipefail

repo=${1:?repo required}
filter=${2:?jq filter required}
out=${3:?output path required}

tok=$(cat /run/secrets/github_token 2>/dev/null || true)
auth=()
[ -z "$tok" ] || auth=(-H "Authorization: token ${tok}")

url=$(curl -fsSL "${auth[@]}" "https://api.github.com/repos/${repo}/releases/latest" \
        | jq -er "${filter}" | head -1)
[ -n "$url" ] || { echo "ERROR: ${repo} asset URL not found"; exit 1; }

wget -qO "$out" "$url"
[ -s "$out" ] || { echo "ERROR: ${repo} download empty"; exit 1; }
