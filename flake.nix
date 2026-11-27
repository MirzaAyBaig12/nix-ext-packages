{
  description = "External Packages for NixOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Plain source trees used by the programs.natsumi module (modules/natsumi.nix).
    # scripts/update-natsumi.sh bumps the natsumi tag below and refreshes both locks.
    fx-autoconfig = {
      url = "github:MrOtherGuy/fx-autoconfig";
      flake = false;
    };
    # Pinned to a tagged release (the repo doesn't publish release assets).
    natsumi = {
      url = "github:greeeen-dev/natsumi-browser/v6.12.5";
      flake = false;
    };
  };

  outputs = { nixpkgs, fx-autoconfig, natsumi, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      mkNatsumiModule = import ./modules/natsumi.nix { inherit fx-autoconfig natsumi; };
    in
    {
      packages.${system} = {
        ardia = pkgs.callPackage ./packages/ardia.nix { };
        sklauncher = pkgs.callPackage ./packages/sklauncher.nix { };
        compas-tools = pkgs.callPackage ./packages/compas-tools.nix { };
        hydra-launcher = pkgs.callPackage ./packages/hydra-launcher.nix { };
        modrinth = pkgs.callPackage ./packages/modrinth.nix { };
        ventoy = pkgs.callPackage ./packages/ventoy.nix { };
        openidea = pkgs.callPackage ./packages/openidea.nix { };
        iloader = pkgs.callPackage ./packages/iloader.nix { };
        ladybird = pkgs.callPackage ./packages/ladybird.nix { };
        doubletake = pkgs.callPackage ./packages/doubletake.nix { };
        bibata-material-cursor = pkgs.callPackage ./packages/bibata-material-cursor.nix { };
        browser-ext-sync = pkgs.callPackage ./packages/browser-ext-sync.nix { };
        freelook = pkgs.callPackage ./packages/freelook.nix { };
        prospect-mail = pkgs.callPackage ./packages/prospect-mail.nix { };
      };

      # `pkgs.browser-ext-sync`: declarative Web Store extensions for Helium +
      # ungoogled-chromium (see packages/browser-ext-sync.nix).
      #
      # `pkgs.ungoogled-chromium-base` is the ungoogled-chromium as it was when this
      # overlay ran. The browser-extensions module builds `.wrapped` from it, so a
      # later overlay that replaces `pkgs.ungoogled-chromium` with `.wrapped`
      # doesn't cause infinite recursion. Keep this overlay BEFORE such overrides.
      overlays.default = final: prev: {
        ardia = final.callPackage ./packages/ardia.nix { };
        browser-ext-sync = final.callPackage ./packages/browser-ext-sync.nix { };
        freelook = final.callPackage ./packages/freelook.nix { };
        ladybird = final.callPackage ./packages/ladybird.nix { };
        prospect-mail = final.callPackage ./packages/prospect-mail.nix { };
        ungoogled-chromium-base = prev.ungoogled-chromium;
      };

      nixosModules.natsumi = mkNatsumiModule { isHomeManager = false; };
      homeManagerModules.natsumi = mkNatsumiModule { isHomeManager = true; };

      # programs.{ungoogled-chromium,helium}.extensions (see modules/browser-extensions.nix)
      homeManagerModules.browser-extensions = ./modules/browser-extensions.nix;
    };
}
