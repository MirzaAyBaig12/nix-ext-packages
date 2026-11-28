/*
  Yapfast (a native Discord/Matrix client) from the official Arch Linux
  .pkg.tar.zst nightly. The archive is just one prebuilt binary plus its desktop
  entry, icon and license/doc files; upstream's own build is Nix-based, so the
  binary is patched in place with autoPatchelfHook instead of being wrapped in
  an FHS env.

  Upstream publishes nightlies as GitHub *prereleases*. `/releases/latest` only
  returns the older stable release, so scripts/update.sh tracks the newest
  prerelease for this package (see the marker below). The tag is
  `v0.5.0-nightly.YYYYMMDD.N`, while the asset's Arch pkgver drops the dash
  (`0.5.0nightly.YYYYMMDD.N`); keep both `version` and `pkgver` as plain strings.
*/
# updater: prerelease
{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  zstd,
  glib,
  libpulseaudio,
  wayland,
  libxkbcommon,
  libX11,
  libxcb,
  libxcursor,
  libXi,
  alsa-lib,
  vulkan-loader,
  libglvnd,
  pipewire,
  libdrm,
  libgbm,
  libXcomposite,
  libXdamage,
  libXext,
  libXfixes,
  libXrandr,
  libva,
  hicolor-icon-theme,
  adwaita-icon-theme,
  shared-mime-info,
  cacert,
  xkeyboard-config,
}:

let
  version = "0.5.0-nightly.20261124.21";
  pkgver = "0.5.0nightly.20261124.21";

  src = fetchurl {
    url = "https://github.com/yapfast/yapfast/releases/download/v${version}/yapfast-${pkgver}-1-x86_64.pkg.tar.zst";
    hash = "sha256-AukjvdQxQxfiWC1t9HifrhCOoNeKFkuED5ipMeYEOgQ=";
  };

  runtimeLibs = [
    glib
    libpulseaudio
    stdenv.cc.cc.lib
    wayland
    libxkbcommon
    libX11
    libxcb
    libxcursor
    libXi
    alsa-lib
    # Optional: GPU rendering, screen sharing, X11 screen capture, VA-API.
    vulkan-loader
    libglvnd
    pipewire
    libdrm
    libgbm
    libXcomposite
    libXdamage
    libXext
    libXfixes
    libXrandr
    libva
  ];

  runtimeData = [
    hicolor-icon-theme
    adwaita-icon-theme
    shared-mime-info
    cacert
    xkeyboard-config
  ];
in
stdenv.mkDerivation {
  pname = "yapfast";
  inherit version src;

  nativeBuildInputs = [ autoPatchelfHook makeWrapper zstd ];

  buildInputs = runtimeLibs ++ runtimeData;

  strictDeps = true;

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;
  # The upstream binary is already stripped; don't run strip over 130 MB again.
  dontStrip = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    tar --zstd -xf $src -C $out --strip-components=1

    # winit/x11-dl dlopen Wayland, X11 and GPU libs at runtime; a RUNPATH from
    # autoPatchelf isn't consulted for those, so the wrapper exports the full
    # library path (and XKB data) without needing an FHS env.
    mv $out/bin/yapfast $out/bin/.yapfast-real
    makeWrapper $out/bin/.yapfast-real $out/bin/yapfast \
      --set LD_LIBRARY_PATH "${lib.makeLibraryPath runtimeLibs}" \
      --set XKB_CONFIG_ROOT "${xkeyboard-config}/share/X11/xkb" \
      --set SSL_CERT_FILE "${cacert}/etc/ssl/certs/ca-bundle.crt" \
      --prefix XDG_DATA_DIRS : "${lib.makeSearchPath "share" runtimeData}:$out/share"

    runHook postInstall
  '';

  meta = {
    description = "Native Discord/Matrix client that stays light on memory";
    homepage = "https://github.com/yapfast/yapfast";
    license = lib.licenses.gpl3Plus;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "yapfast";
  };
}
