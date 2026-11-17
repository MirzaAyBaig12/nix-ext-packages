---
description: Add an external app to nix-ext-packages from a release URL or name
agent: build
---

Add a package to this nix-ext-packages flake from: $ARGUMENTS

Follow `.opencode/skills/nix-ext-packages/SKILL.md`:

1. Find the upstream release asset and version.
2. Choose AppImage, FHS-env `.deb`, autoPatchelf `.deb`, or tarball based on the
   artifact.
3. Create `packages/<name>.nix` with plain-string `version`, `url` containing
   `${version}`, and `hash`.
4. Add it to `flake.nix` and the `README.md` package table.
5. `git add` the new file, then run `nix build .#<name> --print-build-logs`,
   test `./result/bin/<mainProgram> --version`, run `nix flake check --no-build`,
   and run `DRY_RUN=1 ./scripts/update.sh` with `jq` available.

Report the files changed, the test output, and any missing runtime libraries.
