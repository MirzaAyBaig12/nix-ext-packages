{ lib, writeShellScriptBin, writeText, curl, gnugrep, coreutils, unzip, python3 }:

# browser-ext-sync [--helium] [--chromium] <extension-id>...
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
# No flag = both. Offline / failures just skip and keep what's cached.
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
in
writeShellScriptBin "browser-ext-sync" ''
  export PATH=${lib.makeBinPath [ curl gnugrep coreutils unzip python3 ]}

  want_helium=0
  want_chromium=0
  ids=()
  for a in "$@"; do
    case "$a" in
      --helium) want_helium=1 ;;
      --chromium) want_chromium=1 ;;
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
      rm -f "$helium_ext/$id.json"
      printf '{"external_crx":"%s","external_version":"%s"}\n' "$crx" "$ver" > "$helium_ext/$id.json"
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
''
