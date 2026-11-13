{
  description = "CI-only flake: builds the Dux suite (master branches) so nix-config doesn't compile it";

  # Mirrors the dux inputs in MirzaAyBaig12/nix-config: every one tracks master and follows the
  # same nixpkgs, so (with a fresh lock) the derivations are the ones the laptop evaluates.
  # Used only by .github/workflows/cache-dux.yml; it is NOT part of the root flake's outputs.
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    dux-shell = {
      url = "github:duxlabs-dev/dux-shell/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    dux-greeter = {
      url = "github:duxlabs-dev/dux-greeter/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    dux-search = {
      url = "github:duxlabs-dev/dux-search/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    dux-gop = {
      url = "github:duxlabs-dev/dux-gop/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    dux-files = {
      url = "github:duxlabs-dev/dux-files/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    dux-plugin-registry = {
      url = "github:duxlabs-dev/dux-plugin-registry/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      dux-shell,
      dux-greeter,
      dux-search,
      dux-gop,
      dux-files,
      dux-plugin-registry,
      ...
    }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      # Plugins enabled in nix-config (programs.dank-material-shell.plugins). The workflow
      # regenerates this file from nix-config's modules/niri.nix before building.
      plugins = builtins.fromJSON (builtins.readFile ./plugins.json);

      # the dux-qt-base a given dux repo builds against (same call the repos make themselves)
      qtBaseOf = input: (input.inputs.dux-qt-base.overlays.default pkgs pkgs).dux-qt-base;
    in
    {
      packages.${system} = {
        dux-shell = dux-shell.packages.${system}.dms-shell;
        # quickshell was replaced upstream by dux-qt-base. Each of dux-shell / dux-greeter / dux-files
        # pins its own copy as a flake input and builds it through the overlay, so build the exact
        # one each of them uses (nix dedupes them when the revisions match).
        dux-qt-base = pkgs.linkFarm "dux-qt-base" [
          { name = "dux-shell"; path = qtBaseOf dux-shell; }
          { name = "dux-greeter"; path = qtBaseOf dux-greeter; }
          { name = "dux-files"; path = qtBaseOf dux-files; }
        ];
        dux-greeter = dux-greeter.packages.${system}.dms-greeter;
        dux-search = dux-search.packages.${system}.dsearch;
        dux-files = dux-files.packages.${system}.dux-files;

        # dux-gop (dgop): its Go test phase fails (api_test.go imports a module missing from the
        # vendored deps), so nix-config builds it with doCheck = false. Same override here.
        dux-gop = dux-gop.packages.${system}.default.overrideAttrs (_: {
          doCheck = false;
        });

        dux-plugins = pkgs.linkFarm "dux-plugins" (
          map (name: {
            inherit name;
            path = dux-plugin-registry.packages.${system}.${name};
          }) plugins
        );
      };
    };
}
