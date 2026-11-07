# nix-ext-packages

Nix packaging for external apps that aren't in nixpkgs (AppImages, upstream `.deb`s,
prebuilt tarballs), plus a couple of NixOS / home-manager modules. Built for
`x86_64-linux`.

It also fills two public **[Cachix binary caches](#binary-cache)**, including one with **Lix built
from its `main` branch** (ahead of nixpkgs), so you can run a newer Lix without compiling it yourself.

A GitHub Action runs every 4 hours, bumps versions and hashes (`scripts/update.sh`,
`scripts/update-natsumi.sh`), checks the flake and builds every package before pushing.

## Usage

```nix
{
  inputs.nix-ext-packages = {
    url = "github:MirzaAyBaig12/nix-ext-packages";
    inputs.nixpkgs.follows = "nixpkgs";
  };
}
```

Then install a package, for example:

```nix
environment.systemPackages = [
  inputs.nix-ext-packages.packages.x86_64-linux.openidea
];
```

Or just try one: `nix run github:MirzaAyBaig12/nix-ext-packages#openidea`

## Binary cache

Two public [Cachix](https://cachix.org) caches, both filled by GitHub Actions in this repo:

| Cache | URL | Public key | What's in it |
| --- | --- | --- | --- |
| `lix` | `https://lix.cachix.org` | `lix.cachix.org-1:Pnz9vvW0pvlTmUAFmvlx3LHseovdCUMf81z69y6AYAw=` | [Lix](https://lix.systems) built from its **`main` branch** through the official [lix-module](https://git.lix.systems/lix-project/nixos-module), plus the other things its overlay builds (`nix-eval-jobs`, `nix-doc`) |
| `nix-ext-packages` | `https://nix-ext-packages.cachix.org` | `nix-ext-packages.cachix.org-1:Jg15MvXM0xKhn4pymDYoWfA7t5SdIGUVQeywOe9j9EU=` | `cpak`, `nil` (rebuilt against Lix) and the Dux suite |

**If you only want Lix, you only need the `lix` cache.** It exists so Lix can run ahead of nixpkgs
(nixpkgs' Lix lags `main` and the release branches) without a ~40 minute local compile after every
bump.

Lix `main` is a development branch (at the time of writing it is 2.97.0-dev) and moves about
daily, so expect the occasional breakage. This is a personal cache, best effort, and not
affiliated with the Lix project.

### Use the cache

```nix
nix.settings = {
  extra-substituters = [ "https://lix.cachix.org" ];
  extra-trusted-public-keys = [
    "lix.cachix.org-1:Pnz9vvW0pvlTmUAFmvlx3LHseovdCUMf81z69y6AYAw="
  ];
};
```

Nix only trusts a new cache after a build has activated it, so for the first switch pass it on
the command line (as root, or as a trusted user):

```sh
nixos-rebuild switch --flake . \
  --option extra-substituters https://lix.cachix.org \
  --option extra-trusted-public-keys "lix.cachix.org-1:Pnz9vvW0pvlTmUAFmvlx3LHseovdCUMf81z69y6AYAw="
```

### Run Lix from `main`

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Lix source, tracking main.
    lix = {
      url = "https://git.lix.systems/lix-project/lix/archive/refs/heads/main.tar.gz";
      flake = false;
    };

    # The module builds whatever `lix` points at (without the override it uses its own stale pin).
    lix-module = {
      url = "https://git.lix.systems/lix-project/nixos-module/archive/main.tar.gz";
      inputs.lix.follows = "lix";
    };
  };

  outputs = { nixpkgs, lix-module, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      modules = [
        lix-module.nixosModules.default
        ./configuration.nix
      ];
    };
  };
}
```

### What gets cached, and when

| What | Cache | Workflow |
| --- | --- | --- |
| `lix`, `nix-eval-jobs`, `nix-doc` (Lix `main` via lix-module's overlay) | `lix` | [`cache-lix`](.github/workflows/cache-lix.yml) |
| `cpak` ([Containerpak/cpak](https://github.com/Containerpak/cpak) `v2`), `nil` | `nix-ext-packages` | [`cache-misc`](.github/workflows/cache-misc.yml) |
| Dux suite: `dux-shell`, `quickshell`, `dux-greeter`, `dux-search`, `dux-gop`, `dux-files`, plugins ([duxlabs-dev](https://github.com/duxlabs-dev) `master` branches) | `nix-ext-packages` | [`cache-dux`](.github/workflows/cache-dux.yml) |

The workflows only do real work when upstream has new commits. Every 15 minutes a cheap check
(a few `git ls-remote` calls, no Nix) looks at the commits that feed the build: Lix `main`, plus
lix-module and nixpkgs `nixos-unstable`, because those change the derivation (and the store path)
even when Lix itself didn't move. If that exact set was already built the run ends within
seconds, otherwise it builds and pushes. The revisions each run used are in its job summary. A
failed build is retried at most every 6 hours (or when upstream changes), and you can force one
from the Actions tab. `nil` is only built once the matching Lix is in the `lix` cache, since its
tests run against Lix.

### Will it hit for me?

Store paths depend on the exact nixpkgs revision and Lix commit, and the caches are built against
the latest `nixos-unstable` and Lix `main`. So:

- Follow `nixos-unstable` and update shortly after a green run. If nixpkgs or Lix `main` moved in
  between, you compile once and the next run covers it.
- Your own overlays that change `stdenv` or Lix's dependencies will miss.
- Check before you switch (the path is whatever your config evaluates):

  ```sh
  nix path-info --store https://lix.cachix.org \
    "$(nix eval --raw .#nixosConfigurations.myhost.pkgs.lix.outPath)"
  ```

## Packages

| Package | Description | Packaged from |
| --- | --- | --- |
| [`3utools`](packages/3utools.nix) | 3uTools, an Apple device (iPhone/iPad) management tool. Unfree. Needs `services.usbmuxd.enable = true` and this package in `services.udev.packages` for device access. | Official `.deb`, run in an FHS env |
| [`bibata-material-cursor`](packages/bibata-material-cursor.nix) | Bibata Material cursor themes (dark variants), a Material Design 3 take on Bibata. nixpkgs' `bibata-cursors` has no Material variants. | Prebuilt release tarball |
| [`browser-ext-sync`](packages/browser-ext-sync.nix) | Script that installs Chrome Web Store extensions declaratively for Helium and ungoogled-chromium, which can't install them on their own. Also pins, prunes and installs uBlock Origin (MV2). Used by the `browser-extensions` module. | Shell script (nothing fetched) |
| [`compas-tools`](packages/compas-tools.nix) | Compás Tools, desktop companion for Compás music players. | AppImage |
| [`hydra-launcher`](packages/hydra-launcher.nix) | Hydra, an open-source game launcher. | AppImage |
| [`modrinth`](packages/modrinth.nix) | Modrinth App, a Minecraft launcher and mod manager. | AppImage |
| [`openidea`](packages/openidea.nix) | OpenIDEA, an open-source IDE inspired by IntelliJ IDEA, rebuilt in Rust (Tauri). Not affiliated with JetBrains, and JetBrains plugins don't work with it. | Official `.deb`, run in an FHS env |
| [`sklauncher`](packages/sklauncher.nix) | SKLauncher, a Minecraft launcher. | AppImage |
| [`ventoy`](packages/ventoy.nix) | Ventoy, a tool to create bootable USB drives for ISO/WIM/IMG/VHD(x)/EFI files. Provides `ventoy` (CLI), `ventoy-web` (web UI) and `ventoy-gui` (GTK3 GUI). | Upstream release tarball, patched except the GTK3 binary |

## Modules

| Module | Description |
| --- | --- |
| `nixosModules.natsumi` / `homeManagerModules.natsumi` | `programs.natsumi`: installs fx-autoconfig and the [Natsumi](https://github.com/greeeen-dev/natsumi-browser) theme into a Firefox-family browser (Firefox, LibreWolf, Floorp). Sources are pinned as flake inputs and auto-bumped. |
| `homeManagerModules.browser-extensions` | `programs.ungoogled-chromium.extensions` and `programs.helium.extensions`: declarative Chrome Web Store extensions, built on `browser-ext-sync`. Doesn't install the browsers themselves. |

There's also an overlay (`overlays.default`) that adds `pkgs.browser-ext-sync` and
`pkgs.ungoogled-chromium-base`.

## Adding a package

Copy [`template.nix`](template.nix) (AppImage template) to `packages/<name>.nix`, add it to
`flake.nix`, and run `./scripts/update.sh` to fill in the hash. Keep `version`, `url` and
`hash` as plain strings on a GitHub release URL so the auto-updater can bump it.

## License

The packaging in this repo is mine; each package keeps its own upstream license
(see `meta.license` in the package files).
