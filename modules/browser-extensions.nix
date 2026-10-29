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
#   is yours to install. uBlock Origin is only handled for ungoogled-chromium.
#
# `pinned` is additive: it pins the listed ids, it never unpins anything you
# pinned by hand. It's applied at launch (chromium) and on every sync, and
# skipped while the browser is running.
#
# Extensions are re-synced on every home-manager switch and (optionally) once a
# day by a user timer. Nothing is touched unless a new version exists. New
# versions apply on the next browser restart.
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
  uPinned = map (resolve u.ids uExtra) u.pinned;
  hPinned = map (resolve h.ids { }) h.pinned;

  sync = "${syncCfg.package}/bin/browser-ext-sync";
  home = config.home.homeDirectory;
  chromiumDir = "${home}/.config/chromium";
  heliumDir = "${home}/.config/net.imput.helium";

  unpackedDir = id: "${home}/.local/share/browser-extensions/unpacked/${id}";
  loadList = (map unpackedDir uIds) ++ lib.optional u.uBlockOrigin (unpackedDir "ublock-origin");

  pinCmd = dir: pins: "${sync} pin ${lib.escapeShellArg dir} ${lib.escapeShellArgs pins}";

  chromiumArgs = [
    # Newer Chromium gates --load-extension behind this feature.
    "--disable-features=DisableLoadExtensionCommandLineSwitch"
    "--load-extension=${lib.concatStringsSep "," loadList}"
  ] ++ lib.optional (uPinned != [ ])
    # Raw shell in the nixpkgs wrapper: pins before launch, prints nothing.
    "$(${pinCmd chromiumDir uPinned} >/dev/null 2>&1 || true)";

  syncAll = pkgs.writeShellScript "browser-ext-sync-all" ''
    ${lib.optionalString u.enable ''
      ${sync} --chromium ${lib.optionalString u.uBlockOrigin "--ublock-origin"} ${lib.escapeShellArgs uIds} || true
      ${lib.optionalString (uPinned != [ ]) "${pinCmd chromiumDir uPinned} || true"}
    ''}
    ${lib.optionalString h.enable ''
      ${sync} --helium ${lib.escapeShellArgs hIds} || true
      ${lib.optionalString (hPinned != [ ]) "${pinCmd heliumDir hPinned} || true"}
    ''}
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
        example = [ "ublock-origin" "proton-pass" ];
        description = "Extensions to pin to the toolbar: names from `ids` (or \"ublock-origin\"), or raw ids. Additive.";
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
        description = "Extensions to pin to the toolbar: names from `ids`, or raw ids. Additive.";
      };
    };

    browser-ext-sync = {
      package = mkOption {
        type = types.package;
        default = pkgs.browser-ext-sync or (pkgs.callPackage ../packages/browser-ext-sync.nix { });
        defaultText = lib.literalExpression "pkgs.browser-ext-sync";
        description = "The browser-ext-sync package (from the nix-ext-packages overlay).";
      };
      autoUpdate = mkOption {
        type = types.bool;
        default = true;
        description = "Also re-sync once a day with a systemd user timer (not only on home-manager switch).";
      };
    };
  };

  config = mkIf (u.enable || h.enable) {
    programs.ungoogled-chromium.extensions = mkIf u.enable {
      commandLineArgs = chromiumArgs;
      wrapped = u.package.override { commandLineArgs = lib.concatStringsSep " " chromiumArgs; };
    };

    home.activation.browserExtensions = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run ${syncAll} || true
    '';

    systemd.user.services.browser-ext-sync = mkIf syncCfg.autoUpdate {
      Unit = {
        Description = "Sync Web Store extensions for Helium / ungoogled-chromium";
        # home-manager switch already syncs; don't run again just because the unit changed.
        X-RestartIfChanged = false;
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${syncAll}";
      };
    };
    systemd.user.timers.browser-ext-sync = mkIf syncCfg.autoUpdate {
      Unit.Description = "Daily Web Store extension sync";
      Timer = {
        OnCalendar = "daily";
        Persistent = true;
        RandomizedDelaySec = "30m";
      };
      Install.WantedBy = [ "timers.target" ];
    };
  };
}
