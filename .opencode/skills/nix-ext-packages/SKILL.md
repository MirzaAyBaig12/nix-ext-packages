---
name: nix-ext-packages
description: Use when adding, updating, or debugging packages in the nix-ext-packages Nix flake (packages/*.nix, AppImage, .deb, release tarball), wiring them into flake.nix / README.md / scripts/update.sh, or running nix build and nix flake check for this repo.
---

# nix-ext-packages

Repo-specific workflow for packaging external apps that are not in nixpkgs.
Most packages are prebuilt AppImages, `.deb`s, or release tarballs fetched from
GitHub. The GitHub Action `.github/workflows/update.yml` bumps versions/hashes
every 4 hours, runs `nix flake check --no-build`, then builds every package.

## Key files

- `flake.nix` — add the package attr here (`packages.${system}`).
- `packages/<name>.nix` — one file per package.
- `README.md` — add a row to the Packages table.
- `scripts/update.sh` — auto-discovers `packages/*.nix`; no workflow edit needed.
- `template.nix` — AppImage starting point.
- `packages/openidea.nix`, `packages/iloader.nix` — FHS-env patterns for
  self-contained `.deb` bundles.
- `packages/ventoy.nix` — release tarball pattern with `autoPatchelfHook`.

## Add a package

1. Find the upstream release asset and version (GitHub API/release page).
   Prefer an official `.deb`, AppImage, or tarball.
2. Pick the packaging pattern:
   - **AppImage**: follow `template.nix` / an existing AppImage package
     (`elixiroffice.nix`, `modrinth.nix`, `sklauncher.nix`, `hydra-launcher.nix`).
   - **Self-contained `.deb` bundle** (ships Qt/CEF/Electron/its own libs):
     unpack untouched with `dpkg-deb -x`, set `dontFixup = true`, run it inside
     `buildFHSEnv`, and add host-side libraries to `targetPkgs`.
   - **Prebuilt ELF** linked against system libs: use `autoPatchelfHook` +
     `runtimeDependencies` (see `ventoy.nix`; note its caveat about patching
     self-contained binaries). This is usually better than FHS when the app
     re-execs itself or writes autostart files with `current_exe()`.
   - **Tarball**: see `ventoy.nix`.
3. Keep `version`, `url`, and `hash` as plain strings for `update.sh`.
   - `version = "x.y.z";`
   - At least one `url =` line must contain `${version}` and match:
     `https://github.com/<owner>/<repo>/releases/download/<prefix>${version}/...`
   - `hash = "sha256-...";`
   - If a package has several versioned assets from the same repo, put each full
     URL on its own `url =` line followed by its `hash`; `update.sh` refreshes
     all of them.
   - If the release tag and asset version differ, set `version` to the tag
     version and keep the asset suffix hardcoded in the URL.
   - If upstream has no GitHub releases, extend `update.sh` with a special case.
4. Compute the hash:
   - `nix store prefetch-file --json <url> | jq -r .hash`
   - or `nix hash file --sri --type sha256 <downloaded-file>`
5. Wire it up:
   - `flake.nix`: `foo = pkgs.callPackage ./packages/foo.nix { };`
     Use `pkgsUnfree.callPackage` only for unfree packages.
   - `README.md`: add the table row.
6. **`git add` the new file before building.** Flakes only see tracked files:
   `error: Path 'packages/foo.nix' ... is not tracked by Git`.
7. Build and test:
   - `nix build .#foo --print-build-logs`
   - `./result/bin/<mainProgram> --version`
   - For Qt apps, prefix GUI-less tests with `QT_QPA_PLATFORM=offscreen`.
   - `nix flake check --no-build`
   - `nix shell nixpkgs#jq -c bash -c 'DRY_RUN=1 ./scripts/update.sh'`

## FHS env gotchas

- `buildFHSEnv` exposes a target package's `bin/`, `lib/`, etc. at the FHS root.
  Arbitrary `$out/usr/bin/foo` from a target package may **not** appear as
  `/usr/bin/foo`. Either install the launcher into `$out/bin` or call it from its
  store path inside `runScript` (`exec ${unwrapped}/usr/bin/foo "$@"`).
- `pname = "foo"` already creates `$out/bin/foo`. Do not add a symlink with the
  same name; add aliases such as `desktopeditors` instead.
- For self-contained bundles, do not run `autoPatchelf` or stripping; keep
  `dontFixup = true` and preserve symlinks.
- If the bundle hardcodes `/opt/<vendor>/<app>`, expose the unpacked package to
  `targetPkgs` so that path exists inside the FHS root, or patch the launcher.
- Missing shared libraries: inspect the FHS rootfs with:
  `LD_LIBRARY_PATH="<rootfs>/usr/lib64:<appdir>" ldd <appdir>/<binary> | grep 'not found'`
  then add the owning nixpkgs packages to `targetPkgs` (for example `libgbm`,
  `zstd`, `brotli`, `libkrb5`, `libxcb-*`). Also check runtime `dlopen` failures with
  `strace -f -e trace=openat,openat2`: CEF can crash when `libudev.so.1` is absent even
  though the main binary's `ldd` is clean; add `systemdLibs` for it.
- Add an absolute desktop `Exec` and copy icons in `extraInstallCommands`:
  `install -Dm644 ...desktop $out/share/applications/...` then
  `substituteInPlace ... --replace-fail '/usr/bin/old' "$out/bin/new"`.

## Conventions

- Package attr names are lowercase, usually hyphenated (`bibata-material-cursor`,
  `elixiroffice`). `mainProgram` should match the binary in `$out/bin`.
- Add a short comment block at the top of each package explaining what the
  upstream artifact is, why FHS vs autoPatchelf was chosen, and any
  `update.sh` constraints.
- Do not commit unless the user asks. Do not apply unrelated version bumps
  reported by `update.sh` dry runs.
