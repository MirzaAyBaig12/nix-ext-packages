# nix-ext-packages guide

Nix flake for `x86_64-linux` external applications and a few NixOS/home-manager modules.
The more detailed OpenCode workflow is in `.opencode/skills/nix-ext-packages/SKILL.md`;
keep both documents consistent when changing the packaging workflow.

## Package layout

- `packages/<name>.nix`: one package per file.
- `flake.nix`: expose it as `packages.x86_64-linux.<name>` with `pkgs.callPackage`.
- `README.md`: add/update its Packages table row.
- `template.nix`: starting point for AppImages (`appimageTools.extract` + `wrapType2`).
- `packages/openidea.nix`, `packages/iloader.nix`: examples
  for running an unpacked, self-contained `.deb` in `buildFHSEnv`.
- `packages/ventoy.nix`: release-tarball pattern with `autoPatchelfHook`.

For bundled Qt/CEF/Electron apps, unpack with `dpkg-deb -x`, set `dontFixup = true`,
do not strip or autoPatchelf the payload, expose it through `targetPkgs`, and run its
launcher from the unwrapped store path. Add host libraries to `targetPkgs`. Arbitrary
`$out/usr/bin` files are not guaranteed to appear at FHS `/usr/bin`, and hardcoded
`/opt` paths must exist in the FHS root.

## Automatic updates

`scripts/update.sh` scans every `packages/*.nix`; no per-package workflow entry is
needed. For auto-bumping, keep these as plain strings:

```nix
version = "x.y.z";
url = "https://github.com/OWNER/REPO/releases/download/v${version}/asset-${version}.deb";
hash = "sha256-...";
```

The URL must match the GitHub release pattern documented in `template.nix`. The updater
gets the latest release tag, replaces `${version}`, prefetches each versioned asset from
the same repository, and updates its adjacent hash. If the tag and asset versions differ,
keep the asset suffix hardcoded in the URL.
Use `DRY_RUN=1 ./scripts/update.sh` to inspect changes without applying them.

`scripts/update-natsumi.sh` separately bumps the tagged Natsumi input and refreshes only
the `fx-autoconfig` and `natsumi` flake inputs. `.github/workflows/update.yml` runs every
four hours, checks the flake, builds every package, and pushes successful updates.

## Build and test

```sh
nix build .#<name> --print-build-logs
./result/bin/<mainProgram> --version       # when supported
nix flake check --no-build
nix shell nixpkgs#jq -c bash -c 'DRY_RUN=1 ./scripts/update.sh'
```

New package files must be tracked by Git before a flake build can see them. For GUI tests,
verify both that the process stays alive and that a window appears; use a timeout for
cleanup. Inspect missing runtime libraries with `ldd`/`strace` inside the FHS environment.
CEF may `dlopen` libraries not reported by the main binary's `ldd`, notably `libudev.so.1`
from `systemdLibs`.

Do not apply unrelated updater version bumps or commit changes unless requested.
