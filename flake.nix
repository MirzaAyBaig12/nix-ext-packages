{
  description = "External Packages for NixOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      packages.${system} = {
        sklauncher = pkgs.callPackage ./packages/sklauncher.nix { };
        hydra-launcher = pkgs.callPackage ./packages/hydra-launcher.nix { };
      };
    };
}