{ lib, writeShellScriptBin, writeText, curl, gnugrep, coreutils, unzip, python3 }:

# browser-ext-sync [--helium] [--chromium] [--ublock-origin] [--prune] <extension-id>...
# browser-ext-sync pin [--add] <user-data-dir> <extension-id>...
# browser-ext-sync prune-cache <extension-id>...
#
# Declarative Chrome Web Store extensions for browsers that won't install
# them on their own:
#   - Helium strips `prodversion` from its update requests, so Google answers
#     "noupdate" and `external_update_url` never installs anything.
#   - ungoogled-chromium (nixpkgs) ignores External Extensions + policies.
#
# We ask the store ourselves (with a prodversion), cache the CRX, then:
#   --helium    write `external_crx` jsons into Helium's External Extensions
#   --chromium  unpack to ~/.local/share/browser-extensions/unpacked/<id>
#               (load with --load-extension). The CRX's signing key is
#               written back into manifest.json as "key" so the unpacked
#               extension keeps its real Web Store id.
#   --ublock-origin  (with --chromium) also install uBlock Origin (MV2) from its
#               GitHub release; Web Store only ships uBO Lite now. id below.
# --prune     also REMOVE what's no longer in the id list: Helium's external_crx
#             jsons (Helium uninstalls the orphaned extension on its next start)
#             and ungoogled-chromium's unpacked copies. Without it nothing is
#             ever deleted.
# `pin` SETS the browser's toolbar-pinned list to exactly the given ids (adds
#   and removes; skips if the browser is running, since it would overwrite the
#   file on exit). With --add it only appends (used at browser launch so it
#   doesn't wipe pins you made by hand between rebuilds).
# `prune-cache` deletes cached CRXs that aren't in the given id list.
# No flag = helium + chromium. Offline / failures just skip and keep what's cached.
let
  # CRX3 header -> public key whose sha256 matches the crx_id -> manifest "key".
  injectKey = writeText "inject-key.py" ''
    import base64, hashlib, json, struct, sys

    crx, manifest = sys.argv[1], sys.argv[2]
    data = open(crx, "rb").read()
    assert data[:4] == b"Cr24" and struct.unpack("<I", data[4:8])[0] == 3
    hlen = struct.unpack("<I", data[8:12])[0]
    header = data[12:12 + hlen]

    def varint(b, i):
        r = s = 0
        while True:
            c = b[i]
            i += 1
            r |= (c & 0x7F) << s
            s += 7
            if not c & 0x80:
                return r, i

    def fields(b):
        i = 0
        while i < len(b):
            k, i = varint(b, i)
            f, w = k >> 3, k & 7
            if w == 2:
                n, i = varint(b, i)
                v = b[i:i + n]
                i += n
            elif w == 0:
                v, i = varint(b, i)
            elif w == 1:
                v = b[i:i + 8]
                i += 8
            elif w == 5:
                v = b[i:i + 4]
                i += 4
            else:
                raise ValueError("bad wire type")
            yield f, v

    crx_id, keys = None, []
    for f, v in fields(header):
        if f == 10000:
            for f2, v2 in fields(v):
                if f2 == 1:
                    crx_id = v2
        elif f in (2, 3):
            for f2, v2 in fields(v):
                if f2 == 1:
                    keys.append(v2)

    key = next(k for k in keys if hashlib.sha256(k).digest()[:16] == crx_id)
    with open(manifest, encoding="utf-8-sig") as fh:
        m = json.load(fh)
    m["key"] = base64.b64encode(key).decode()
    with open(manifest, "w") as fh:
        json.dump(m, fh, indent=2)
  '';
  # Set (or, with --add, append to) extensions.pinned_extensions in
  # <user-data-dir>/Default/Preferences.
  pinPy = writeText "pin-extensions.py" ''
    import json, os, sys

    args = sys.argv[1:]
    add_only = False
    if args and args[0] == "--add":
        add_only = True
        args = args[1:]
    d, ids = args[0], args[1:]
    lock = os.path.join(d, "SingletonLock")
    if os.path.islink(lock):
        try:
            os.kill(int(os.readlink(lock).rsplit("-", 1)[1]), 0)
            sys.exit(0)  # browser is running; it would overwrite us on exit
        except (ValueError, IndexError, ProcessLookupError):
            pass  # stale lock
        except PermissionError:
            sys.exit(0)

    path = os.path.join(d, "Default", "Preferences")
    data = {}
    if os.path.exists(path):
        try:
            with open(path) as fh:
                data = json.load(fh)
        except Exception:
            sys.exit(0)  # don't clobber a prefs file we can't parse
    else:
        os.makedirs(os.path.dirname(path), exist_ok=True)

    ext = data.setdefault("extensions", {})
    cur = list(ext.get("pinned_extensions", []))
    new = cur + [i for i in ids if i not in cur] if add_only else list(ids)
    if new != cur:
        ext["pinned_extensions"] = new
        with open(path + ".tmp", "w") as fh:
            json.dump(data, fh)
        os.replace(path + ".tmp", path)
  '';
in
writeShellScriptBin "browser-ext-sync" ''
  export PATH=${lib.makeBinPath [ curl gnugrep coreutils unzip python3 ]}

  if [ "''${1:-}" = pin ]; then
    shift
    exec python3 ${pinPy} "$@"
  fi

  # Delete cached CRXs for ids that aren't wanted anymore (one run, union of all ids).
  if [ "''${1:-}" = prune-cache ]; then
    shift
    base="$HOME/.local/share/browser-extensions"
    for f in "$base"/crx/*.crx; do
      [ -e "$f" ] || continue
      id=$(basename "$f" .crx)
      keep=0
      for w in "$@"; do [ "$w" = "$id" ] && keep=1; done
      if [ "$keep" = 0 ]; then
        rm -f "$f" "$base/crx/$id.version"
        echo "browser-ext-sync: pruned cache $id"
      fi
    done
    exit 0
  fi

  want_helium=0
  want_chromium=0
  want_ubo=0
  want_prune=0
  ids=()
  for a in "$@"; do
    case "$a" in
      --helium) want_helium=1 ;;
      --chromium) want_chromium=1 ;;
      --ublock-origin) want_ubo=1 ;;
      --prune) want_prune=1 ;;
      *) ids+=("$a") ;;
    esac
  done
  if [ "$want_helium" = 0 ] && [ "$want_chromium" = 0 ]; then
    want_helium=1
    want_chromium=1
  fi

  base="$HOME/.local/share/browser-extensions"
  helium_ext="$HOME/.config/net.imput.helium/External Extensions"
  mkdir -p "$base/crx" "$base/unpacked"
  if [ "$want_helium" = 1 ]; then mkdir -p "$helium_ext"; fi

  for id in "''${ids[@]}"; do
    xml=$(curl -fsSL --max-time 30 "https://clients2.google.com/service/update2/crx?os=linux&arch=x64&prod=chromecrx&prodversion=150.0.0.0&acceptformat=crx3&x=id%3D$id%26uc") || { echo "browser-ext-sync: skip $id (query failed)"; continue; }
    url=$(grep -oP 'codebase="\K[^"]+' <<<"$xml" | head -1)
    ver=$(grep -oP '<updatecheck[^>]*\sversion="\K[^"]+' <<<"$xml" | head -1)
    if [ -z "$url" ] || [ -z "$ver" ]; then echo "browser-ext-sync: skip $id (no codebase/version)"; continue; fi

    crx="$base/crx/$id.crx"
    if [ ! -f "$crx" ] || [ "$(cat "$base/crx/$id.version" 2>/dev/null)" != "$ver" ]; then
      if curl -fsSL --max-time 180 -o "$crx.tmp" "$url"; then
        mv -f "$crx.tmp" "$crx"
        echo "$ver" > "$base/crx/$id.version"
      else
        rm -f "$crx.tmp"
        echo "browser-ext-sync: skip $id (download failed)"
        continue
      fi
    fi

    if [ "$want_helium" = 1 ]; then
      want=$(printf '{"external_crx":"%s","external_version":"%s"}\n' "$crx" "$ver")
      if [ -L "$helium_ext/$id.json" ] || [ "$(cat "$helium_ext/$id.json" 2>/dev/null)" != "$want" ]; then
        rm -f "$helium_ext/$id.json"
        printf '%s\n' "$want" > "$helium_ext/$id.json"
      fi
    fi

    if [ "$want_chromium" = 1 ]; then
      if [ ! -f "$base/unpacked/$id/manifest.json" ] || [ "$(cat "$base/unpacked/$id.version" 2>/dev/null)" != "$ver" ]; then
        tmp=$(mktemp -d)
        unzip -qo "$crx" -d "$tmp" >/dev/null 2>&1 || true   # CRX3 header => unzip warns, still extracts
        if [ -f "$tmp/manifest.json" ]; then
          python3 ${injectKey} "$crx" "$tmp/manifest.json" || echo "browser-ext-sync: $id: couldn't inject key (id will differ)"
          rm -rf "$base/unpacked/$id"
          mv "$tmp" "$base/unpacked/$id"
          echo "$ver" > "$base/unpacked/$id.version"
        else
          rm -rf "$tmp"
          echo "browser-ext-sync: skip $id (unpack failed)"
          continue
        fi
      fi
    fi
    echo "browser-ext-sync: $id $ver"
  done

  if [ "$want_ubo" = 1 ] && [ "$want_chromium" = 1 ]; then
    rel=$(curl -fsSL --max-time 30 https://api.github.com/repos/gorhill/uBlock/releases/latest) || rel=""
    uurl=$(grep -oP '"browser_download_url": "\K[^"]+\.chromium\.crx' <<<"$rel" | head -1)
    uver=$(grep -oP '"tag_name": "\K[^"]+' <<<"$rel" | head -1)
    if [ -n "$uurl" ] && [ -n "$uver" ]; then
      ucrx="$base/crx/ublock-origin.crx"
      if [ ! -f "$ucrx" ] || [ "$(cat "$base/crx/ublock-origin.version" 2>/dev/null)" != "$uver" ] || [ ! -f "$base/unpacked/ublock-origin/manifest.json" ]; then
        if curl -fsSL --max-time 180 -o "$ucrx.tmp" "$uurl"; then
          mv -f "$ucrx.tmp" "$ucrx"
          tmp=$(mktemp -d)
          unzip -qo "$ucrx" -d "$tmp" >/dev/null 2>&1 || true
          if [ -f "$tmp/manifest.json" ]; then
            python3 ${injectKey} "$ucrx" "$tmp/manifest.json" || echo "browser-ext-sync: ublock-origin: couldn't inject key"
            rm -rf "$base/unpacked/ublock-origin"
            mv "$tmp" "$base/unpacked/ublock-origin"
            echo "$uver" > "$base/crx/ublock-origin.version"
            echo "browser-ext-sync: ublock-origin $uver"
          else
            rm -rf "$tmp"
            echo "browser-ext-sync: skip ublock-origin (unpack failed)"
          fi
        else
          rm -f "$ucrx.tmp"
          echo "browser-ext-sync: skip ublock-origin (download failed)"
        fi
      fi
    else
      echo "browser-ext-sync: skip ublock-origin (couldn't find release)"
    fi
  fi

  # Remove whatever is no longer in the list (only with --prune). Done from the
  # requested ids, not the successful ones, so being offline never deletes anything.
  if [ "$want_prune" = 1 ]; then
    in_ids() { local x; for x in "''${ids[@]}"; do [ "$x" = "$1" ] && return 0; done; return 1; }

    if [ "$want_helium" = 1 ]; then
      for f in "$helium_ext"/*.json; do
        [ -e "$f" ] || [ -L "$f" ] || continue
        id=$(basename "$f" .json)
        # only touch files that look like extension ids
        grep -qE '^[a-p]{32}$' <<<"$id" || continue
        if ! in_ids "$id"; then
          rm -f "$f"
          echo "browser-ext-sync: removed $id from helium (gone on next browser start)"
        fi
      done
    fi

    if [ "$want_chromium" = 1 ]; then
      for d in "$base"/unpacked/*/; do
        [ -d "$d" ] || continue
        id=$(basename "$d")
        if [ "$id" = ublock-origin ] && [ "$want_ubo" = 1 ]; then continue; fi
        if ! in_ids "$id"; then
          rm -rf "$d" "$base/unpacked/$id.version"
          echo "browser-ext-sync: removed $id from chromium"
        fi
      done
    fi
  fi
''
