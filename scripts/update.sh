#!/usr/bin/env bash
# Bumps version + hashes for every packages/*.nix that fetches from GitHub releases.
# A package may have several versioned assets (url + hash pairs); all of them are
# refreshed, as long as they point at the same repository.
# DRY_RUN=1 ./scripts/update.sh   -> only report what would change
set -euo pipefail
cd "$(dirname "$0")/.."

re='github\.com/([^/]+)/([^/]+)/releases/download/([^$]*)\$\{version\}'

for file in packages/*.nix; do
  name=$(basename "$file" .nix)
  # grep exits 1 on no match (e.g. packages that don't fetch anything, like
  # browser-ext-sync), which would kill the script under pipefail.
  urls=$(grep -oP '^\s*url = "\K[^"]+' "$file" || true)
  cur=$(grep -oP '^\s*version = "\K[^"]+' "$file" | head -1 || true)

  first_url=""
  while IFS= read -r url; do
    if [[ $url =~ $re ]]; then
      first_url=$url
      owner=${BASH_REMATCH[1]}; repo=${BASH_REMATCH[2]}; prefix=${BASH_REMATCH[3]}
      break
    fi
  done <<<"$urls"

  if [[ -z $first_url ]]; then
    echo "[$name] url isn't a GitHub release pattern, skipping"
    continue
  fi

  tag=$(curl -fsSL ${GH_TOKEN:+-H "Authorization: Bearer $GH_TOKEN"} \
    "https://api.github.com/repos/$owner/$repo/releases/latest" | jq -r .tag_name)
  new=${tag#"$prefix"}

  if [[ -z $new || $new == "null" || $new == "$cur" ]]; then
    echo "[$name] up to date ($cur)"
    continue
  fi

  echo "[$name] $cur -> $new"
  [[ -n ${DRY_RUN:-} ]] && continue

  # Update every versioned asset from this repo and the hash that follows it.
  while IFS= read -r url; do
    [[ $url =~ $re ]] || continue
    [[ ${BASH_REMATCH[1]} == "$owner" && ${BASH_REMATCH[2]} == "$repo" ]] || continue

    new_url=${url//'${version}'/$new}
    new_hash=$(nix store prefetch-file --json "$new_url" | jq -r .hash)
    URL=$url NEW_HASH=$new_hash perl -0pi -e \
      's|(\Q$ENV{URL}\E.*?hash = ")[^"]+(")|${1}$ENV{NEW_HASH}${2}|s' "$file"
  done <<<"$urls"

  sed -i "s|version = \"$cur\";|version = \"$new\";|" "$file"

  if [[ -n ${CI:-} ]]; then
    git add "$file"
    git -c user.name="github-actions[bot]" \
        -c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
        commit -m "$name: $cur -> $new"
  fi
done
