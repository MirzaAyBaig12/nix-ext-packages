/*
  Euro-Office (open-source office suite, a fork of ONLYOFFICE DesktopEditors)
  from the official .deb.

  The deb is a self-contained linuxdeploy-style bundle in /opt/euro-office/euro-office:
  it ships Qt6, CEF, ffmpeg and the document engine, found through $ORIGIN rpaths.
  It still expects host GTK3 / X11 / GStreamer / ALSA / NSS libraries, so the payload
  is unpacked untouched and the upstream launcher is run inside an FHS env. The
  launcher hardcodes /opt/euro-office/euro-office (also for --new-document-templates),
  so the payload is installed at that path by exposing the `unwrapped` package to the
  FHS env instead of rewriting the bundle.

  For scripts/update.sh to auto-bump it, keep `version`, `url` and `hash` as plain
  strings and the url on the GitHub release pattern below (tags are `v<version>`).
  Upstream assets always carry a `-0` build suffix, e.g.
  euro-office-euro-office_9.3.8-0_amd64.deb; the tag is v9.3.8.
*/
{
  lib,
  stdenvNoCC,
  fetchurl,
  dpkg,
  buildFHSEnv,
  writeShellScript,
  writeText,
  carlito,
  dejavu_fonts,
  liberation_ttf,
}:

let
  pname = "euro-office";
  version = "9.3.8";

  src = fetchurl {
    url = "https://github.com/Euro-Office/DesktopEditors/releases/download/v${version}/euro-office-euro-office_${version}-0_amd64.deb";
    hash = "sha256-GBbEzV1YBrdXRow9xX7HbCOs0eoIUtRB5Q1qVJ0hfaE=";
  };

  # The bundle ships its own (older) libfontconfig, which can't parse the config files
  # of the fontconfig in the FHS env or on the host (xsi:nil, newer constants), spams
  # errors and can end up with no usable fonts. Point it at a minimal config using only
  # syntax old fontconfig understands, and list the font dirs explicitly instead of
  # including the host's conf.d.
  fontsConf = writeText "euro-office-fonts.conf" ''
    <?xml version="1.0"?>
    <!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
    <fontconfig>
      <dir>${carlito}/share/fonts</dir>
      <dir>${dejavu_fonts}/share/fonts</dir>
      <dir>${liberation_ttf}/share/fonts</dir>
      <dir>/run/current-system/sw/share/X11/fonts</dir>
      <dir>/usr/share/fonts</dir>
      <dir prefix="xdg">fonts</dir>
      <dir>~/.fonts</dir>
      <cachedir prefix="xdg">fontconfig</cachedir>
      <alias>
        <family>sans-serif</family>
        <prefer><family>Noto Sans</family><family>DejaVu Sans</family></prefer>
      </alias>
      <alias>
        <family>serif</family>
        <prefer><family>Noto Serif</family><family>DejaVu Serif</family></prefer>
      </alias>
      <alias>
        <family>monospace</family>
        <prefer><family>DejaVu Sans Mono</family></prefer>
      </alias>
    </fontconfig>
  '';

  # The deb's payload, untouched: no patchelf, no stripping, no shebang rewrite.
  unwrapped = stdenvNoCC.mkDerivation {
    pname = "${pname}-unwrapped";
    inherit version src;

    nativeBuildInputs = [ dpkg ];

    dontConfigure = true;
    dontBuild = true;
    dontFixup = true;

    unpackPhase = ''
      runHook preUnpack
      dpkg-deb -x $src .
      runHook postUnpack
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p $out
      cp -r opt usr $out/
      runHook postInstall
    '';
  };
in
buildFHSEnv {
  inherit pname version;

  targetPkgs =
    pkgs: with pkgs; [
      # The bundle itself: /opt/euro-office/euro-office + /usr/bin/euro-office-euro-office
      unwrapped

      # what the deb's Depends: lists (the parts the bundle doesn't carry)
      alsa-lib
      atk
      at-spi2-atk
      cairo
      cups
      curl
      dbus
      desktop-file-utils
      gdk-pixbuf
      glib
      gtk3
      harfbuzz
      libnotify
      libpulseaudio
      pipewire
      libxkbcommon
      libxscrnsaver
      nss
      nspr
      pango
      stdenv.cc.cc.lib
      xdg-utils
      xdg-user-dirs

      # GStreamer (gstreamer1.0-libav / -plugins-ugly in the deb)
      gst_all_1.gstreamer
      gst_all_1.gst-plugins-base
      gst_all_1.gst-plugins-good
      gst_all_1.gst-plugins-ugly
      gst_all_1.gst-libav

      # fonts the deb pulls in
      carlito
      dejavu_fonts
      liberation_ttf
      fontconfig
      freetype

      # GL / video / Wayland
      libGL
      libglvnd
      libgbm
      mesa
      libdrm
      libva
      libvdpau
      wayland

      # X11 / xcb (the bundled Qt only has the xcb platform plugin)
      libx11
      libxau
      libxcb
      libxcb-cursor
      libxcb-image
      libxcb-keysyms
      libxcb-render-util
      libxcb-util
      libxcb-wm
      libxcomposite
      libxcursor
      libxdamage
      libxdmcp
      libxext
      libxfixes
      libxi
      libxinerama
      libxrandr
      libxrender
      libxshmfence
      libxtst
      libxxf86vm

      # misc runtime bits CEF / Qt load at runtime
      brotli
      cacert
      expat
      hicolor-icon-theme
      adwaita-icon-theme
      icu
      libgcrypt
      libgpg-error
      libjpeg
      libkrb5
      libpng
      libsecret
      libtiff
      libwebp
      libxml2
      openssl
      shared-mime-info
      systemdLibs # CEF dlopens libudev.so.1 and crashes if it is absent
      zlib
      zstd
    ];

  runScript = writeShellScript "euro-office-run" ''
    # The upstream launcher sets LD_LIBRARY_PATH/LD_PRELOAD and execs
    # /opt/euro-office/euro-office/DesktopEditors. Keep using it as shipped;
    # only /opt is merged into the FHS root, so call it from the store path.
    # The bundled Qt has no kvantum style / qt5ct platform theme plugin; the global
    # QT_STYLE_OVERRIDE=kvantum / QT_QPA_PLATFORMTHEME=qt5ct only produce warnings.
    unset QT_STYLE_OVERRIDE QT_QPA_PLATFORMTHEME
    export FONTCONFIG_FILE=${fontsConf}
    exec ${unwrapped}/usr/bin/euro-office-euro-office "$@"
  '';

  extraInstallCommands = ''
    # Absolute Exec: some compositors (kwin) don't resolve a bare Exec via PATH.
    install -Dm644 ${unwrapped}/usr/share/applications/euro-office-euro-office.desktop \
      $out/share/applications/euro-office.desktop
    substituteInPlace $out/share/applications/euro-office.desktop \
      --replace-fail '/usr/bin/euro-office-euro-office' "$out/bin/euro-office"

    mkdir -p $out/share/icons
    cp -r ${unwrapped}/usr/share/icons/hicolor $out/share/icons/

    ln -s euro-office $out/bin/desktopeditors
  '';

  passthru = { inherit unwrapped; };

  meta = {
    description = "Euro-Office, an open-source office suite for documents, spreadsheets, presentations and PDFs";
    homepage = "https://github.com/Euro-Office/DesktopEditors";
    license = lib.licenses.agpl3Plus;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "euro-office";
  };
}
