{ config, lib, pkgs, ... }:

# Home-manager module: declarative Chrome Web Store extensions for browsers
# that can't install them themselves (see packages/browser-ext-sync.nix).
#
#   programs.ungoogled-chromium.extensions = {
#     enable = true;
#     ids = [ "..." ];          # list of ids, or attrset of name = id
#     pinned = [ "stylus" ];    # names from `ids` (or raw ids) to pin to the toolbar
#     uBlockOrigin = true;      # default; installed automatically, no id needed
#   };
#   programs.helium.extensions = { enable = true; ids = [ "..." ]; pinned = [ ... ]; };
#
# - ungoogled-chromium: unpacked copies are loaded with --load-extension. This
#   module does NOT install any browser. It exposes the flags as
#   `programs.ungoogled-chromium.extensions.commandLineArgs` and a ready-made
#   `.wrapped` package (your ungoogled-chromium + those flags) for you to put in
#   home.packages / systemPackages yourself. A plain, unwrapped chromium just
#   won't load the extensions. Don't set the nixos `programs.chromium.extensions`
#   policy either: a force-installed id can't also be loaded unpacked
#   ("blocked by the administrator").
# - Helium: external_crx jsons in its External Extensions dir; the Helium package
#   is yours to install. It ships uBlock Origin itself; we only keep it pinned.
#   (Installing uBlock Origin is ungoogled-chromium only.)
#
# `pinned` is authoritative: on every home-manager switch the toolbar-pinned
# list is set to exactly what you list (adds AND removes). That write is skipped
# while the browser is running (it would overwrite the file on exit), so close the
# browser before switching if you changed `pinned`. (ungoogled-chromium also
# re-adds missing pins at launch, without removing any.)
#
# Extensions are synced ONLY on home-manager switch (no timer): new versions are
# fetched, and anything you removed from `ids` is removed too (Helium drops the
# extension on its next start; ungoogled-chromium's unpacked copy is deleted).
# New versions apply on the next browser restart.
let
  inherit (lib) mkEnableOption mkOption mkIf types;

  cfg = config.programs;
  u = cfg.ungoogled-chromium.extensions;
  h = cfg.helium.extensions;
  syncCfg = cfg.browser-ext-sync;

  # uBlock Origin (MV2) from its GitHub release; id comes from the release's
  # signing key, so it's stable.
  uboId = "fkgkibajhfbepljeaefdnfnegdcjomkh";

  idsType = types.either (types.listOf types.str) (types.attrsOf types.str);
  pinnedType = types.listOf types.str;
  toIds = v: if builtins.isAttrs v then lib.attrValues v else v;

  # pinned entries may be a name from `ids` (or "ublock-origin") or a raw id
  resolve = ids: extra: n:
    let table = (if builtins.isAttrs ids then ids else { }) // extra;
    in table.${n} or n;

  uExtra = { "ublock-origin" = uboId; };
  uIds = toIds u.ids;
  hIds = toIds h.ids;
  # ungoogled-chromium: our uBlock Origin is pinned automatically. Helium pins its
  # built-in one by itself, so it is never added (and "ublock-origin" is ignored).
  uPinned = lib.unique ((map (resolve u.ids uExtra) u.pinned) ++ lib.optional u.uBlockOrigin uboId);
  hPinned = lib.filter (x: x != "ublock-origin") (map (resolve h.ids { }) h.pinned);

  # Extension ids are exactly 32 letters, a-p only.
  validId = id: builtins.match "[a-p]{32}" id != null;
  describeBad = ids:
    let
      pairs = if builtins.isAttrs ids
        then lib.mapAttrsToList (n: v: { inherit n v; }) ids
        else map (v: { n = v; inherit v; }) ids;
    in map (p: "${p.n} = \"${p.v}\" (${toString (builtins.stringLength p.v)} chars)")
      (lib.filter (p: !validId p.v) pairs);
  badPinned = ids: pinned: extra:
    lib.filter (id: !(validId id) && id != "ublock-origin") pinned;
  mkAssertion = option: bad: {
    assertion = bad == [ ];
    message = "${option}: invalid Chrome Web Store extension id(s), expected 32 letters a-p: ${lib.concatStringsSep ", " bad}";
  };

  sync = "${syncCfg.package}/bin/browser-ext-sync";
  home = config.home.homeDirectory;
  chromiumDir = "${home}/.config/chromium";
  heliumDir = "${home}/.config/net.imput.helium";

  unpackedDir = id: "${home}/.local/share/browser-extensions/unpacked/${id}";
  loadList = (map unpackedDir uIds) ++ lib.optional u.uBlockOrigin (unpackedDir "ublock-origin");

  # authoritative (set) on switch; add-only at browser launch.
  pinCmd = dir: pins: "${sync} pin ${lib.escapeShellArg dir} ${lib.escapeShellArgs pins}";
  pinAddCmd = dir: pins: "${sync} pin --add ${lib.escapeShellArg dir} ${lib.escapeShellArgs pins}";

  chromiumArgs = [
    # Newer Chromium gates --load-extension behind this feature.
    "--disable-features=DisableLoadExtensionCommandLineSwitch"
    "--load-extension=${lib.concatStringsSep "," loadList}"
  ] ++ lib.optional (uPinned != [ ])
    # Raw shell in the nixpkgs wrapper: pins before launch, prints nothing.
    "$(${pinAddCmd chromiumDir uPinned} >/dev/null 2>&1 || true)";

  # ids any enabled browser still wants (cache pruning keeps these)
  allIds = lib.unique (
    (lib.optionals u.enable uIds)
    ++ (lib.optionals h.enable hIds)
  );

  # name/id pairs, so changes can be reported by name (a plain list uses the id).
  toPairs = ids:
    if builtins.isAttrs ids
    then lib.mapAttrsToList (n: v: { inherit n v; }) ids
    else map (v: { n = v; inherit v; }) ids;
  uPairs = toPairs u.ids ++ lib.optional u.uBlockOrigin { n = "ublock-origin"; v = uboId; };
  hPairs = toPairs h.ids;

  # Prints "<name> added/removed" by diffing against the list from the last
  # switch (first run just records a baseline). Also pops a notification.
  report = browser: pairs: ''
    new=$(mktemp)
    printf '%s\t%s\n' ${lib.escapeShellArgs (lib.concatMap (p: [ p.n p.v ]) pairs)} | sort -u > "$new"
    old="$state/${browser}.list"
    if [ -f "$old" ]; then
      while IFS=$'\t' read -r name _; do
        [ -n "$name" ] || continue
        echo "browser-extensions [${browser}]: $name added"
        changes="$changes+ $name (${browser})"$'\n'
      done < <(awk -F'\t' 'NR==FNR{o[$2]=1; next} !($2 in o)' "$old" "$new")
      while IFS=$'\t' read -r name _; do
        [ -n "$name" ] || continue
        echo "browser-extensions [${browser}]: $name removed"
        changes="$changes- $name (${browser})"$'\n'
      done < <(awk -F'\t' 'NR==FNR{n[$2]=1; next} !($2 in n)' "$new" "$old")
    fi
    mv -f "$new" "$old"
  '';

  syncAll = pkgs.writeShellScript "browser-ext-sync-all" ''
    export PATH=${lib.makeBinPath [ pkgs.coreutils pkgs.gawk pkgs.libnotify ]}:$PATH
    state="$HOME/.local/share/browser-extensions/state"
    mkdir -p "$state"
    changes=""
    ${lib.optionalString u.enable (report "ungoogled-chromium" uPairs)}
    ${lib.optionalString h.enable (report "helium" hPairs)}
    if [ -n "$changes" ]; then
      DBUS_SESSION_BUS_ADDRESS="''${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/$(id -u)/bus}" \
        notify-send -a browser-extensions "Browser extensions changed" "$changes" 2>/dev/null || true
    fi
    ${lib.optionalString u.enable ''
      ${sync} --chromium --prune ${lib.optionalString u.uBlockOrigin "--ublock-origin"} ${lib.escapeShellArgs uIds} || true
      ${pinCmd chromiumDir uPinned} || true
    ''}
    ${lib.optionalString h.enable ''
      ${sync} --helium --prune ${lib.escapeShellArgs hIds} || true
      ${pinCmd heliumDir hPinned} || true
    ''}
    ${sync} prune-cache ${lib.escapeShellArgs allIds} || true
  '';
in
{
  options.programs = {
    ungoogled-chromium.extensions = {
      enable = mkEnableOption "declarative Web Store extensions for ungoogled-chromium";
      ids = mkOption {
        type = idsType;
        default = [ ];
        description = "Chrome Web Store extension ids (list, or attrset of name = id).";
      };
      pinned = mkOption {
        type = pinnedType;
        default = [ ];
        example = [ "proton-pass" "stylus" ];
        description = "Extensions to pin to the toolbar: names from `ids`, or raw ids. Authoritative (see top of file). uBlock Origin is pinned automatically when `uBlockOrigin` is on.";
      };
      uBlockOrigin = mkOption {
        type = types.bool;
        default = true;
        description = "Install uBlock Origin automatically (no id needed).";
      };
      package = mkOption {
        type = types.package;
        default = pkgs.ungoogled-chromium-base or pkgs.ungoogled-chromium;
        defaultText = lib.literalExpression "pkgs.ungoogled-chromium-base or pkgs.ungoogled-chromium";
        description = ''
          ungoogled-chromium package used to build `wrapped`. Not installed by this module.
          Defaults to `pkgs.ungoogled-chromium-base` (from the nix-ext-packages overlay), the
          untouched original, so overriding `pkgs.ungoogled-chromium` with `.wrapped` doesn't recurse.
        '';
      };
      commandLineArgs = mkOption {
        type = types.listOf types.str;
        readOnly = true;
        description = "Flags that load the extensions (for wrapping your own chromium).";
      };
      wrapped = mkOption {
        type = types.package;
        readOnly = true;
        description = "`package` wrapped with the extension flags. Install this yourself.";
      };
    };

    helium.extensions = {
      enable = mkEnableOption "declarative Web Store extensions for Helium";
      ids = mkOption {
        type = idsType;
        default = [ ];
        description = "Chrome Web Store extension ids (list, or attrset of name = id).";
      };
      pinned = mkOption {
        type = pinnedType;
        default = [ ];
        description = "Extensions to pin to the toolbar: names from `ids`, or raw ids. Authoritative (see top of file). Helium pins its own uBlock Origin; don't list it.";
      };
    };

    browser-ext-sync = {
      package = mkOption {
        type = types.package;
        default = pkgs.browser-ext-sync or (pkgs.callPackage ../packages/browser-ext-sync.nix { });
        defaultText = lib.literalExpression "pkgs.browser-ext-sync";
        description = "The browser-ext-sync package (from the nix-ext-packages overlay).";
      };
    };
  };

  config = mkIf (u.enable || h.enable) {
    assertions = [
      (mkAssertion "programs.ungoogled-chromium.extensions.ids" (lib.optionals u.enable (describeBad u.ids)))
      (mkAssertion "programs.ungoogled-chromium.extensions.pinned (not a name in `ids`)" (lib.optionals u.enable (badPinned u.ids (map (resolve u.ids uExtra) u.pinned) { })))
      (mkAssertion "programs.helium.extensions.ids" (lib.optionals h.enable (describeBad h.ids)))
      (mkAssertion "programs.helium.extensions.pinned (not a name in `ids`)" (lib.optionals h.enable (badPinned h.ids (map (resolve h.ids { }) h.pinned) { })))
    ];

    programs.ungoogled-chromium.extensions = mkIf u.enable {
      commandLineArgs = chromiumArgs;
      wrapped = u.package.override { commandLineArgs = lib.concatStringsSep " " chromiumArgs; };
    };

    # Only runs on home-manager switch (no timer): update, add, remove, re-pin.
    home.activation.browserExtensions = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run ${syncAll} || true
    '';
  };
}
