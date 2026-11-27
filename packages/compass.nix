/*
  Compass browser from the official Linux .tar.xz release (Chromium-based,
  "an open-source Arc alternative"). The archive is a self-contained folder:
  the `compass` binary, its .pak resources, locales and bundled ANGLE/Vulkan
  libs, all found relative to the executable.

  It is run unpatched in an FHS env so it finds /lib64 and the usual Chromium
  runtime libs. The archive's chrome-sandbox is not setuid, so the renderers
  rely on unprivileged user namespaces (the NixOS default); pass --no-sandbox
  explicitly if those are disabled.

  For scripts/update.sh to auto-bump it, keep version/url/hash as plain strings
  on the GitHub release URL below.
*/
{
  lib,
  stdenvNoCC,
  fetchurl,
  buildFHSEnv,
  writeShellScript,
  gtk3,
  gsettings-desktop-schemas,
}:

let
  pname = "compass";
  version = "20261126.0015";

  src = fetchurl {
    url = "https://github.com/Compass-Browser/Compass/releases/download/v${version}/Compass-${version}-linux-x64.tar.xz";
    hash = "sha256-JlJQIAW+SuedVWedn9t6RKjTq/K05raa0gxcCCoqlbA=";
  };

  # The tarball's contents, untouched.
  unwrapped = stdenvNoCC.mkDerivation {
    pname = "${pname}-unwrapped";
    inherit version src;

    dontConfigure = true;
    dontBuild = true;
    # Keep the binary and its relative resource lookup exactly as shipped.
    dontFixup = true;

    unpackPhase = ''
      runHook preUnpack
      mkdir -p source
      tar -xJf "$src" -C source --strip-components=1
      runHook postUnpack
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p $out/opt
      cp -r source $out/opt/compass
      runHook postInstall
    '';
  };
in
buildFHSEnv {
  inherit pname version;

  targetPkgs =
    pkgs: with pkgs; [
      # what the binary links against (Chromium runtime)
      nspr
      nss
      glib
      glib-networking
      atk
      at-spi2-atk
      at-spi2-core
      dbus
      expat
      mesa
      libgbm
      libglvnd
      libdrm
      alsa-lib
      pulseaudio
      libxcb
      libx11
      libxcomposite
      libxdamage
      libxext
      libxfixes
      libxrandr
      libxkbcommon
      cairo
      pango
      systemd # libudev
      gtk3
      cups
      vulkan-loader
      fontconfig
      freetype
      liberation_ttf
      dejavu_fonts
      adwaita-icon-theme
      hicolor-icon-theme
      shared-mime-info
      cacert
      curl
      openssl
      xdg-utils
      stdenv.cc.cc.lib
    ];

  runScript = writeShellScript "compass-run" ''
    # libsoup needs glib-networking's GIO modules for https
    export GIO_EXTRA_MODULES=/usr/lib/gio/modules
    # GTK file dialogs abort without the gtk3 / desktop gsettings schemas
    export XDG_DATA_DIRS="${gtk3}/share/gsettings-schemas/${gtk3.name}:${gsettings-desktop-schemas}/share/gsettings-schemas/${gsettings-desktop-schemas.name}:/usr/share:''${XDG_DATA_DIRS:-}"
    exec ${unwrapped}/opt/compass/compass "$@"
  '';

  extraInstallCommands = ''
    mkdir -p $out/share/applications $out/share/icons/hicolor/256x256/apps
    cp ${unwrapped}/opt/compass/compass.desktop $out/share/applications/compass.desktop
    install -Dm644 ${unwrapped}/opt/compass/product_logo_256.png \
      $out/share/icons/hicolor/256x256/apps/compass.png

    # The shipped desktop file uses a bare Exec=compass; point it at the wrapper.
    substituteInPlace $out/share/applications/compass.desktop \
      --replace-fail 'Exec=compass' "Exec=$out/bin/compass"
  '';

  passthru = { inherit unwrapped; };

  meta = {
    description = "Open-source Arc alternative built on Chromium";
    homepage = "https://compassbrowser.org";
    license = lib.licenses.bsd3;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "compass";
  };
}
