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
      url = "github:greeeen-dev/natsumi-browser/v6.12.4";
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
        sklauncher = pkgs.callPackage ./packages/sklauncher.nix { };
        hydra-launcher = pkgs.callPackage ./packages/hydra-launcher.nix { };
        modrinth = pkgs.callPackage ./packages/modrinth.nix { };
        lumine-capture = pkgs.callPackage ./packages/lumine-capture.nix { };
        ventoy = pkgs.callPackage ./packages/ventoy.nix { };
        bibata-material-cursor = pkgs.callPackage ./packages/bibata-material-cursor.nix { };
        browser-ext-sync = pkgs.callPackage ./packages/browser-ext-sync.nix { };
      };

      # `pkgs.browser-ext-sync`: declarative Web Store extensions for Helium +
      # ungoogled-chromium (see packages/browser-ext-sync.nix).
      overlays.default = final: _prev: {
        browser-ext-sync = final.callPackage ./packages/browser-ext-sync.nix { };
      };

      nixosModules.natsumi = mkNatsumiModule { isHomeManager = false; };
      homeManagerModules.natsumi = mkNatsumiModule { isHomeManager = true; };

      # programs.{ungoogled-chromium,helium}.extensions (see modules/browser-extensions.nix)
      homeManagerModules.browser-extensions = ./modules/browser-extensions.nix;
    };
}
