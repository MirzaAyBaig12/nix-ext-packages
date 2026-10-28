{ config, lib, pkgs, ... }:

# Home-manager module: declarative Chrome Web Store extensions for browsers
# that can't install them themselves (see packages/browser-ext-sync.nix).
#
#   programs.ungoogled-chromium.extensions = { enable = true; ids = [ "..." ]; };
#   programs.helium.extensions             = { enable = true; ids = [ "..." ]; };
#
# `ids` takes a list of extension ids or an attrset of name = id.
#
# - ungoogled-chromium: unpacked copies are loaded with --load-extension via
#   `programs.chromium` (the package is wrapped with those flags). Don't also
#   install ungoogled-chromium system-wide and don't set the nixos
#   `programs.chromium.extensions` policy: a force-installed id can't also be
#   loaded unpacked ("blocked by the administrator").
# - Helium: external_crx jsons in its External Extensions dir.
#
# Extensions are re-synced on every home-manager switch and (optionally) by a
# daily user timer. New versions apply on the next browser restart.
let
  inherit (lib) mkEnableOption mkOption mkIf types;

  cfg = config.programs;
  u = cfg.ungoogled-chromium.extensions;
  h = cfg.helium.extensions;
  syncCfg = cfg.browser-ext-sync;

  idsType = types.either (types.listOf types.str) (types.attrsOf types.str);
  toIds = v: if builtins.isAttrs v then lib.attrValues v else v;

  uIds = toIds u.ids;
  hIds = toIds h.ids;
  sync = "${syncCfg.package}/bin/browser-ext-sync";

  unpackedDir = id: "${config.home.homeDirectory}/.local/share/browser-extensions/unpacked/${id}";

  syncAll = pkgs.writeShellScript "browser-ext-sync-all" ''
    ${lib.optionalString u.enable "${sync} --chromium ${lib.escapeShellArgs uIds} || true"}
    ${lib.optionalString h.enable "${sync} --helium ${lib.escapeShellArgs hIds} || true"}
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
      package = mkOption {
        type = types.package;
        default = pkgs.ungoogled-chromium;
        defaultText = lib.literalExpression "pkgs.ungoogled-chromium";
        description = "ungoogled-chromium package to wrap with the extension flags.";
      };
    };

    helium.extensions = {
      enable = mkEnableOption "declarative Web Store extensions for Helium";
      ids = mkOption {
        type = idsType;
        default = [ ];
        description = "Chrome Web Store extension ids (list, or attrset of name = id).";
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
        description = "Also re-sync daily with a systemd user timer (not only on home-manager switch).";
      };
    };
  };

  config = mkIf (u.enable || h.enable) {
    programs.chromium = mkIf u.enable {
      enable = true;
      package = u.package;
      commandLineArgs = [
        # Newer Chromium gates --load-extension behind this feature.
        "--disable-features=DisableLoadExtensionCommandLineSwitch"
        "--load-extension=${lib.concatMapStringsSep "," unpackedDir uIds}"
      ];
    };

    home.activation.browserExtensions = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run ${syncAll} || true
    '';

    systemd.user.services.browser-ext-sync = mkIf syncCfg.autoUpdate {
      Unit.Description = "Sync Web Store extensions for Helium / ungoogled-chromium";
      Service = {
        Type = "oneshot";
        ExecStart = "${syncAll}";
      };
    };
    systemd.user.timers.browser-ext-sync = mkIf syncCfg.autoUpdate {
      Unit.Description = "Daily Web Store extension sync";
      Timer = {
        OnStartupSec = "5min";
        OnUnitActiveSec = "1d";
      };
      Install.WantedBy = [ "timers.target" ];
    };
  };
}
