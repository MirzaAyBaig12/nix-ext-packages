# programs.spotify-downloader -- NixOS + home-manager module.
#
# Installs the spot2hiby TUI into PATH with the target device baked into the
# wrapper:
#
#   programs.spotify-downloader = {
#     enable = true;
#     musicDevice = "HiBy R1 SD";
#   };
#
# The device is looked up at <mountRoot>/<musicDevice> and FLACs are written to
# <mountRoot>/<musicDevice>/<musicDir>/<Album>/.
{ isHomeManager }:
{ config, lib, pkgs, ... }:
let
  cfg = config.programs.spotify-downloader;

  # Normally provided by the nix-ext-packages overlay. The fallback lets this
  # module be imported on its own, without the overlay being applied.
  upstream = pkgs.spotify-downloader or pkgs.spot2hiby
    or (pkgs.callPackage ../packages/spot2hiby.nix { });

  built = upstream.override {
    musicDevice = cfg.musicDevice;
    mountRoot = cfg.mountRoot;
    musicDir = cfg.musicDir;
  };
in
{
  options.programs.spotify-downloader = {
    enable = lib.mkEnableOption "spotify-downloader (Spotify links to tagged FLACs on your music player)";

    musicDevice = lib.mkOption {
      type = lib.types.str;
      default = "HiBy R1 SD";
      example = "HiBy R1 SD";
      description = ''
        Name of the mounted device, exactly as it appears under `mountRoot`.
        The default is how the HiBy R1 SD card shows up on this machine:
        `/run/mount/ayaan_mirza/HiBy R1 SD`.
      '';
    };

    mountRoot = lib.mkOption {
      type = lib.types.str;
      default = "/run/mount/ayaan_mirza";
      description = ''
        Parent directory that mounted removable media appears in. The script
        looks for `<mountRoot>/<musicDevice>` and waits for it to show up.
      '';
    };

    musicDir = lib.mkOption {
      type = lib.types.str;
      default = "Music";
      description = "Folder on the device that the per-album folders go into.";
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = built;
      defaultText = lib.literalExpression "pkgs.spotify-downloader.override { ... }";
      description = "The spotify-downloader package installed into PATH when enabled.";
    };
  };

  config = lib.mkIf cfg.enable (
    if isHomeManager
    then { home.packages = [ cfg.package ]; }
    else { environment.systemPackages = [ cfg.package ]; }
  );
}
