# nix-ext-packages

Nix packaging for external apps that aren't in nixpkgs (AppImages, upstream `.deb`s,
prebuilt tarballs), plus a couple of NixOS / home-manager modules. Built for
`x86_64-linux`.

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

## Packages

| Package | Description | Packaged from |
| --- | --- | --- |
| [`3utools`](packages/3utools.nix) | 3uTools, an Apple device (iPhone/iPad) management tool. Unfree. Needs `services.usbmuxd.enable = true` and this package in `services.udev.packages` for device access. | Official `.deb`, run in an FHS env |
| [`bibata-material-cursor`](packages/bibata-material-cursor.nix) | Bibata Material cursor themes (dark variants), a Material Design 3 take on Bibata. nixpkgs' `bibata-cursors` has no Material variants. | Prebuilt release tarball |
| [`browser-ext-sync`](packages/browser-ext-sync.nix) | Script that installs Chrome Web Store extensions declaratively for Helium and ungoogled-chromium, which can't install them on their own. Also pins, prunes and installs uBlock Origin (MV2). Used by the `browser-extensions` module. | Shell script (nothing fetched) |
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
