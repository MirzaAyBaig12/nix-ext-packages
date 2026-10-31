#!/usr/bin/env bash
# Bumps version + hash for every packages/*.nix that fetches from GitHub releases,
# plus the packages with their own upstream feed (3utools: scraped from 3u.com).
# DRY_RUN=1 ./scripts/update.sh   -> only report what would change
set -euo pipefail
cd "$(dirname "$0")/.."

re='github\.com/([^/]+)/([^/]+)/releases/download/([^$]*)\$\{version\}'

# 3uTools is proprietary and has no GitHub releases: the official download page
# links the current Linux deb (…/com.3u.3utools_<version>_amd64.deb).
latest_3utools_url() {
  curl -fsSL -A 'Mozilla/5.0' https://www.3u.com/download \
    | grep -oP 'https://dl\.3u\.com/[^"'"'"' <>]*/com\.3u\.3utools_[0-9][0-9.]*_amd64\.deb' \
    | sort -uV | tail -n1 || true
}

for file in packages/*.nix; do
  name=$(basename "$file" .nix)
  # grep exits 1 on no match (e.g. packages that don't fetch anything, like
  # browser-ext-sync), which would kill the script under pipefail.
  url=$(grep -oP '^\s*url = "\K[^"]+' "$file" | head -1 || true)
  cur=$(grep -oP '^\s*version = "\K[^"]+' "$file" | head -1 || true)
  old_hash=$(grep -oP '^\s*hash = "\K[^"]+' "$file" | head -1 || true)
  url_template=$url

  if [[ $name == 3utools ]]; then
    scraped=$(latest_3utools_url)
    if [[ -z $scraped ]]; then
      echo "[$name] couldn't find the deb link on 3u.com, skipping"
      continue
    fi
    new=$(grep -oP '_\K[0-9][0-9.]*(?=_amd64\.deb$)' <<<"$scraped")
    # keep the url in the .nix templated on ${version} (the vNNN dir may change upstream)
    url_template=${scraped//"_${new}_"/'_${version}_'}
  elif [[ -n $url && $url =~ $re ]]; then
    owner=${BASH_REMATCH[1]}; repo=${BASH_REMATCH[2]}; prefix=${BASH_REMATCH[3]}

    tag=$(curl -fsSL ${GH_TOKEN:+-H "Authorization: Bearer $GH_TOKEN"} \
      "https://api.github.com/repos/$owner/$repo/releases/latest" | jq -r .tag_name)
    new=${tag#"$prefix"}
  else
    echo "[$name] url isn't a GitHub release pattern, skipping"
    continue
  fi

  if [[ -z $new || $new == "null" || $new == "$cur" ]]; then
    echo "[$name] up to date ($cur)"
    continue
  fi

  echo "[$name] $cur -> $new"
  [[ -n ${DRY_RUN:-} ]] && continue

  new_url=${url_template//'${version}'/$new}
  new_hash=$(nix store prefetch-file --json "$new_url" | jq -r .hash)

  sed -i "s|version = \"$cur\";|version = \"$new\";|" "$file"
  sed -i "s|hash = \"$old_hash\";|hash = \"$new_hash\";|" "$file"
  if [[ $url_template != "$url" ]]; then
    sed -i "s|url = \"$url\";|url = \"$url_template\";|" "$file"
  fi

  if [[ -n ${CI:-} ]]; then
    git add "$file"
    git -c user.name="github-actions[bot]" \
        -c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
        commit -m "$name: $cur -> $new"
  fi
done
