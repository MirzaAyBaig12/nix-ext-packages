#!/usr/bin/env bash
# Bumps version + hash for every packages/*.nix that fetches from GitHub releases.
# DRY_RUN=1 ./scripts/update.sh   -> only report what would change
set -euo pipefail
cd "$(dirname "$0")/.."

re='github\.com/([^/]+)/([^/]+)/releases/download/([^$]*)\$\{version\}'

for file in packages/*.nix; do
  name=$(basename "$file" .nix)
  url=$(grep -oP '^\s*url = "\K[^"]+' "$file" | head -1)
  cur=$(grep -oP '^\s*version = "\K[^"]+' "$file" | head -1)
  old_hash=$(grep -oP '^\s*hash = "\K[^"]+' "$file" | head -1)

  if [[ ! $url =~ $re ]]; then
    echo "[$name] url isn't a GitHub release pattern, skipping"
    continue
  fi
  owner=${BASH_REMATCH[1]}; repo=${BASH_REMATCH[2]}; prefix=${BASH_REMATCH[3]}

  tag=$(curl -fsSL ${GH_TOKEN:+-H "Authorization: Bearer $GH_TOKEN"} \
    "https://api.github.com/repos/$owner/$repo/releases/latest" | jq -r .tag_name)
  new=${tag#"$prefix"}

  if [[ -z $new || $new == "null" || $new == "$cur" ]]; then
    echo "[$name] up to date ($cur)"
    continue
  fi

  echo "[$name] $cur -> $new"
  [[ -n ${DRY_RUN:-} ]] && continue

  new_url=${url//'${version}'/$new}
  new_hash=$(nix store prefetch-file --json "$new_url" | jq -r .hash)

  sed -i "s|version = \"$cur\";|version = \"$new\";|" "$file"
  sed -i "s|hash = \"$old_hash\";|hash = \"$new_hash\";|" "$file"

  if [[ -n ${CI:-} ]]; then
    git add "$file"
    git -c user.name="github-actions[bot]" \
        -c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
        commit -m "$name: $cur -> $new"
  fi
done
