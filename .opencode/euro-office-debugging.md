# Euro-Office FHS/debugging notes

## 2026-11-17: immediate exit on launch

Euro-Office was already packaged with `buildFHSEnv`; the installed launcher resolved to
an `euro-office-9.3.8-bwrap` store path. FHS conversion was therefore not needed.

The actual failure was a `SIGTRAP` (exit status 133) from `libcef.so` during CEF
initialization. `strace -f -e trace=openat,openat2` showed the crashing thread trying and
failing to locate `libudev.so.1`, then `libudev.so.0`, immediately before the trap. This
is a runtime `dlopen` dependency, so checking only `ldd DesktopEditors` did not reveal it.

Fix: add `systemdLibs` to `targetPkgs` in `packages/euro-office.nix`. Nixpkgs'
`systemdLibs` supplies `libudev.so.1` inside the FHS environment.

Verification:

- `nix build .#euro-office --print-build-logs` succeeded.
- The rebuilt `./result/bin/euro-office` remained running instead of exiting with 133.
- `niri msg windows` showed a real window titled `Euro-Office` with app ID
  `euro-office-euro-office`.

The old fontconfig parse warnings and GTK `gtk_disable_setlocale()` warning still appear,
but they were not the cause of the crash. The window renders despite them. A portal app-ID
warning may also appear when launching directly from the build result.

The system-wide `/run/current-system/sw/bin/euro-office` is unchanged until the NixOS
configuration is rebuilt with this fixed package (or the fixed repository revision is
pushed and used by that configuration).

Note: `libxcb-util` was already staged in `packages/euro-office.nix` before this debugging
session. The new runtime fix is the separate `systemdLibs` addition.
