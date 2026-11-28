/*
  Yapfast (a native Discord/Matrix client) from the official Arch Linux
  .pkg.tar.zst nightly. The payload is copied verbatim (no patchelf) and run
  inside buildFHSEnv, so the binary finds the /lib64, /usr/lib and /usr/share
  paths it was built against, including the Wayland/X11/GPU libraries it
  dlopens at runtime.

  Upstream publishes nightlies as GitHub *prereleases*. `/releases/latest` only
  returns the older stable release, so scripts/update.sh tracks the newest
  prerelease for this package (see the marker below). The tag is
  `v0.5.0-nightly.YYYYMMDD.N`, while the asset's Arch pkgver drops the dash
  (`0.5.0nightly.YYYYMMDD.N`); keep both `version` and `pkgver` as plain strings.
*/
# updater: prerelease
{
  lib,
  stdenvNoCC,
  fetchurl,
  zstd,
  buildFHSEnv,
  writeShellScript,
  glib,
  libpulseaudio,
  wayland,
  libxkbcommon,
  xkeyboard-config,
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
  dejavu_fonts,
  fontconfig,
}:

let
  pname = "yapfast";
  version = "0.5.0-nightly.20261124.21";
  pkgver = "0.5.0nightly.20261124.21";

  src = fetchurl {
    url = "https://github.com/yapfast/yapfast/releases/download/v${version}/yapfast-${pkgver}-1-x86_64.pkg.tar.zst";
    hash = "sha256-AukjvdQxQxfiWC1t9HifrhCOoNeKFkuED5ipMeYEOgQ=";
  };

  # The Arch payload, untouched.
  unwrapped = stdenvNoCC.mkDerivation {
    pname = "${pname}-unwrapped";
    inherit version src;

    nativeBuildInputs = [ zstd ];

    dontConfigure = true;
    dontBuild = true;
    # Keep the binary and its loader paths exactly as shipped.
    dontFixup = true;

    unpackPhase = ''
      runHook preUnpack
      mkdir -p source
      tar --zstd -xf $src -C source --strip-components=1
      runHook postUnpack
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p $out
      cp -r source/. $out/
      runHook postInstall
    '';
  };
in
buildFHSEnv {
  inherit pname version;

  targetPkgs =
    pkgs: with pkgs; [
      # Direct NEEDED libs from the Arch PKGINFO.
      glib
      libpulseaudio
      stdenv.cc.cc.lib
      # Windowing/input, some loaded lazily by winit and x11-dl.
      wayland
      libxkbcommon
      xkeyboard-config
      libX11
      libxcb
      libxcursor
      libXi
      libXext
      libXfixes
      alsa-lib
      # Optional: GPU rendering, screen sharing, capture, VA-API.
      vulkan-loader
      libglvnd
      pipewire
      libdrm
      libgbm
      libXcomposite
      libXdamage
      libXrandr
      libva
      # Data files, fonts and TLS trust from the Arch dependencies.
      hicolor-icon-theme
      adwaita-icon-theme
      shared-mime-info
      dejavu_fonts
      fontconfig
      cacert
    ];

  runScript = writeShellScript "yapfast-run" ''
    export XDG_DATA_DIRS="${unwrapped}/share:/usr/share:''${XDG_DATA_DIRS:-}"
    export XKB_CONFIG_ROOT=/usr/share/X11/xkb
    export SSL_CERT_FILE="${cacert}/etc/ssl/certs/ca-bundle.crt"
    exec ${unwrapped}/bin/yapfast "$@"
  '';

  extraInstallCommands = ''
    mkdir -p $out/share
    cp -r ${unwrapped}/share/applications ${unwrapped}/share/icons \
      ${unwrapped}/share/metainfo $out/share/

    # Absolute Exec: some compositors don't resolve a bare Exec via PATH.
    substituteInPlace $out/share/applications/io.github.yapfast.Yapfast.desktop \
      --replace-fail 'Exec=yapfast' "Exec=$out/bin/yapfast"
  '';

  passthru = { inherit unwrapped; };

  meta = {
    description = "Native Discord/Matrix client that stays light on memory";
    homepage = "https://github.com/yapfast/yapfast";
    license = lib.licenses.gpl3Plus;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "yapfast";
  };
}
