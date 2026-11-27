#!/usr/bin/env bash
# Bumps version + hashes for every packages/*.nix that fetches from GitHub
# releases, plus ladybird's RPM from the yum repo at rpm.ladybird.org.
# A package may have several versioned assets (url + hash pairs); all of them are
# refreshed, as long as they point at the same repository.
# DRY_RUN=1 ./scripts/update.sh   -> only report what would change
set -euo pipefail
cd "$(dirname "$0")/.."

re='github\.com/([^/]+)/([^/]+)/releases/download/([^$]*)\$\{version\}'

commit_bump() {
  [[ -n ${CI:-} ]] || return 0
  git add "$1"
  git -c user.name="github-actions[bot]" \
      -c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
      commit -m "$2"
}

# Ladybird publishes RPMs into an R2 yum repo (no directory listing). The
# repodata primary.xml.gz lists every release; pick the newest x86_64 binary
# (not debuginfo) and print "version<TAB>relative href".
ladybird_latest() {
  local repomd primary xml entry
  repomd=$(curl -fsSL https://rpm.ladybird.org/repodata/repomd.xml)
  primary=$(printf '%s\n' "$repomd" | grep -o 'repodata/[^"]*-primary.xml.gz' | head -1)
  [[ -n $primary ]] || return 1
  xml=$(curl -fsSL "https://rpm.ladybird.org/$primary" | gzip -dc)
  entry=$(printf '%s\n' "$xml" | awk '
    /<package type="rpm">/ { name = ""; ver = ""; href = "" }
    /<name>/ {
      name = $0; sub(/.*<name>/, "", name); sub(/<\/name>.*/, "", name)
    }
    /<version / {
      ver = $0; sub(/.*ver="/, "", ver); sub(/".*/, "", ver)
    }
    /<location href=/ {
      href = $0; sub(/.*href="/, "", href); sub(/".*/, "", href)
    }
    /<\/package>/ {
      if (name == "ladybird" && href ~ /x86_64\.rpm$/) print ver "\t" href
    }
  ' | sort -V | tail -1)
  [[ -n $entry ]] || return 1
  printf '%s\n' "$entry"
}

for file in packages/*.nix; do
  name=$(basename "$file" .nix)
  # grep exits 1 on no match (e.g. packages that don't fetch anything, like
  # browser-ext-sync), which would kill the script under pipefail.
  urls=$(grep -oP '^\s*url = "\K[^"]+' "$file" || true)
  cur=$(grep -oP '^\s*version = "\K[^"]+' "$file" | head -1 || true)

  # Ladybird is an RPM from rpm.ladybird.org, not a GitHub release.
  if grep -q 'rpm\.ladybird\.org/packages/ladybird-' "$file"; then
    entry=$(ladybird_latest) || {
      echo "[$name] couldn't read Ladybird repodata, skipping"
      continue
    }
    IFS=$'\t' read -r new href <<<"$entry"

    if [[ -z $new || $new == "$cur" ]]; then
      echo "[$name] up to date ($cur)"
      continue
    fi

    echo "[$name] $cur -> $new"
    [[ -n ${DRY_RUN:-} ]] && continue

    # Keep the ${version} interpolation in the URL, but follow an RPM release
    # bump (e.g. -1.fc44 -> -2.fc44) if upstream changes it.
    old_url=$(printf '%s\n' "$urls" | head -1)
    old_rel=$(printf '%s' "$old_url" | sed -E 's|.*\$\{version\}-||; s|\.x86_64\.rpm$||')
    rel=$(printf '%s' "$href" | sed -E "s|^packages/ladybird-${new}-||; s|\.x86_64\.rpm$||")

    new_url="https://rpm.ladybird.org/$href"
    new_hash=$(nix store prefetch-file --json "$new_url" | jq -r .hash)

    if [[ $old_rel != "$rel" ]]; then
      OLD_REL=$old_rel NEW_REL=$rel perl -0pi -e \
        's|-\Q$ENV{OLD_REL}\E\.x86_64\.rpm|-$ENV{NEW_REL}.x86_64.rpm|' "$file"
    fi
    URL=$old_url NEW_HASH=$new_hash perl -0pi -e \
      's|(\Q$ENV{URL}\E.*?hash = ")[^"]+(")|${1}$ENV{NEW_HASH}${2}|s' "$file"
    sed -i "s|version = \"$cur\";|version = \"$new\";|" "$file"

    commit_bump "$file" "$name: $cur -> $new"
    continue
  fi

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

  commit_bump "$file" "$name: $cur -> $new"
done
