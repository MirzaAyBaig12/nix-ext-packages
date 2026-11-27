/*
  Ardia browser from the official .deb (Chromium engine + Ardia's UI, built
  with Helium's patches).

  The deb ships a complete /usr/lib/ardia tree next to its launcher script.
  The browser needs the usual Chromium runtime libs and an ELF interpreter at
  /lib64/ld-linux-x86-64.so.2, so it is run unpatched in an FHS env, like the
  other prebuilt browsers here.

  The deb's chrome-sandbox is setuid root after install, which a read-only Nix
  store can't provide: the launcher falls back to unprivileged user namespaces
  (the NixOS default). Pass --no-sandbox explicitly if those are disabled.

  For scripts/update.sh to auto-bump it, keep version/url/hash as plain strings
  on the GitHub release URL below.
*/
{
  lib,
  stdenvNoCC,
  fetchurl,
  dpkg,
  buildFHSEnv,
  writeShellScript,
  gtk3,
  gsettings-desktop-schemas,
}:

let
  pname = "ardia";
  version = "0.2.49";

  src = fetchurl {
    url = "https://github.com/ardia-browser/ardia/releases/download/v${version}/Ardia-${version}-linux-x64.deb";
    hash = "sha256-HxoMa4VolP3tvl45/yOmb2rVehB6k3Yt72kGlM4/ODQ=";
  };

  # The deb's payload, untouched apart from dropping the setuid bit.
  unwrapped = stdenvNoCC.mkDerivation {
    pname = "${pname}-unwrapped";
    inherit version src;

    nativeBuildInputs = [ dpkg ];

    dontConfigure = true;
    dontBuild = true;
    dontFixup = true;

    unpackPhase = ''
      runHook preUnpack
      mkdir -p source
      # dpkg-deb -x tries to recreate the setuid chrome-sandbox and fails as
      # a build user; ignore stored modes/owners (we drop setuid below).
      dpkg-deb --fsys-tarfile "$src" | tar -xf - -C source \
        --no-same-owner --no-same-permissions
      runHook postUnpack
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p $out/usr
      cp -r source/usr/lib $out/usr/
      cp -r source/usr/share $out/usr/
      chmod u-s $out/usr/lib/ardia/chrome-sandbox
      runHook postInstall
    '';
  };
in
buildFHSEnv {
  inherit pname version;

  targetPkgs =
    pkgs: with pkgs; [
      # the deb's Depends, minus libc/glibc which the FHS env provides
      nspr
      nss
      glib
      glib-networking
      atk
      at-spi2-atk
      at-spi2-core
      dbus
      cups
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
      libsecret
      polkit
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

  runScript = writeShellScript "ardia-run" ''
    # libsoup needs glib-networking's GIO modules for https
    export GIO_EXTRA_MODULES=/usr/lib/gio/modules
    # GTK file dialogs abort without the gtk3 / desktop gsettings schemas
    export XDG_DATA_DIRS="${gtk3}/share/gsettings-schemas/${gtk3.name}:${gsettings-desktop-schemas}/share/gsettings-schemas/${gsettings-desktop-schemas.name}:/usr/share:''${XDG_DATA_DIRS:-}"
    exec ${unwrapped}/usr/lib/ardia/ardia-launch "$@"
  '';

  extraInstallCommands = ''
    mkdir -p $out/share
    cp -r ${unwrapped}/usr/share/applications ${unwrapped}/usr/share/icons $out/share/

    # The shipped desktop files point at /usr/bin/ardia; use the FHS wrapper.
    substituteInPlace $out/share/applications/*.desktop \
      --replace-fail '/usr/bin/ardia' "$out/bin/ardia"
  '';

  passthru = { inherit unwrapped; };

  meta = {
    description = "Chromium-based web browser with Ardia's sidebar UI and Helium patches";
    homepage = "https://ardia.dev";
    license = lib.licenses.gpl3Only;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "ardia";
  };
}
