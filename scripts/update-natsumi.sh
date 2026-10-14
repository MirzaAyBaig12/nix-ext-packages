#!/usr/bin/env bash
# Bumps the natsumi tag in flake.nix to the latest upstream vX.Y.Z tag and
# refreshes the fx-autoconfig + natsumi inputs in flake.lock (nixpkgs is left alone).
# DRY_RUN=1 ./scripts/update-natsumi.sh   -> only report what would change
set -euo pipefail
cd "$(dirname "$0")/.."

latest=$(git ls-remote --tags --refs https://github.com/greeeen-dev/natsumi-browser.git \
  | sed 's|.*refs/tags/||' \
  | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' \
  | sort -V | tail -n1)
current=$(grep -oE 'natsumi-browser/v[0-9]+\.[0-9]+\.[0-9]+' flake.nix | head -n1 | cut -d/ -f2)
echo "[natsumi] current=$current latest=$latest"

bumped=""
if [[ -n $current && -n $latest && $latest != "$current" ]]; then
  echo "[natsumi] $current -> $latest"
  bumped=$latest
fi

[[ -n ${DRY_RUN:-} ]] && exit 0

[[ -n $bumped ]] && sed -i "s|natsumi-browser/$current|natsumi-browser/$bumped|" flake.nix
nix flake update fx-autoconfig natsumi

if [[ -n ${CI:-} ]]; then
  git add flake.nix flake.lock
  if git diff --cached --quiet; then
    echo "[natsumi] nothing to update"
    exit 0
  fi
  if [[ -n $bumped ]]; then
    msg="natsumi: bump to $bumped"
  else
    msg="natsumi: update flake.lock"
  fi
  git -c user.name="github-actions[bot]" \
      -c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
      commit -m "$msg"
fi
