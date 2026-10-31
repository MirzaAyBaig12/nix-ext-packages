/*
  3uTools (Apple device management tool) from the official Linux .deb.

  The deb is a linuxdeployqt bundle: it ships its own Ubuntu glibc 2.35 (+ ld.so as
  the ELF interpreter via a *relative* path `./lib/ld-linux-x86-64.so.2`), Qt5
  WebEngine, ffmpeg, libimobiledevice, etc., all found through $ORIGIN rpaths. So
  nothing is patched (autoPatchelf would only break it): the deb is unpacked
  as-is and started with the app directory as cwd inside an FHS env that provides
  the host-side bits it still expects (/usr/lib, /etc/ssl, fonts, GL, ...).

  For scripts/update.sh to auto-bump it, keep `version`, `url` and `hash` as plain
  strings (update.sh scrapes https://www.3u.com/download for the latest deb, 3uTools
  has no public GitHub releases).

  Device access needs two things on the NixOS side (not part of this package):
    services.usbmuxd.enable = true;
    services.udev.packages = [ inputs.nix-ext-packages.packages.${system}."3utools" ];
  (the udev rules are the ones the deb's preinst writes to 38-3uTools.rules).
*/
{
  lib,
  stdenvNoCC,
  fetchurl,
  dpkg,
  buildFHSEnv,
  writeShellScript,
}:

let
  pname = "3utools";
  version = "9.03.003";

  src = fetchurl {
    url = "https://dl.3u.com/update/v900/dl/linux/x64/com.3u.3utools_${version}_amd64.deb";
    hash = "sha256-NDHpflst3gwfg2XvXgwV15oRVy1Y3AI2Apd3p2tZb+8=";
  };

  # The deb's payload, untouched.
  unwrapped = stdenvNoCC.mkDerivation {
    pname = "${pname}-unwrapped";
    inherit version src;

    nativeBuildInputs = [ dpkg ];

    dontConfigure = true;
    dontBuild = true;
    # It's a self-contained bundle: no patchelf, no stripping, no shebang rewrite.
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

      mkdir -p $out/lib/udev/rules.d
      cat > $out/lib/udev/rules.d/38-3uTools.rules <<'EOF'
      SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ENV{PRODUCT}=="5ac/128[0-9]/*|5ac/122[0-9]/*|5ac/f014/*|5ac/1881/*", TAG+="systemd"
      SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ENV{PRODUCT}=="5ac/128[0-9]/*|5ac/122[0-9]/*|5ac/f014/*|5ac/1881/*", MODE="0666"
      SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ENV{PRODUCT}=="5ac/12[9a][0-9a-f]/*|5ac/8600/*", TAG+="systemd"
      EOF
      runHook postInstall
    '';
  };

  appDir = "${unwrapped}/opt/apps/com.3u.3utools";
in
buildFHSEnv {
  inherit pname version;

  targetPkgs =
    pkgs: with pkgs; [
      # host-side things the bundle doesn't carry
      cacert
      fontconfig
      freetype
      dejavu_fonts
      dbus
      glib
      libGL
      libglvnd
      mesa
      alsa-lib
      libpulseaudio
      libusb1
      libxkbcommon
      openssl
      zlib
      stdenv.cc.cc.lib
      # X11 / xcb (the bundled Qt only has the xcb platform plugin)
      libx11
      libxcomposite
      libxcursor
      libxdamage
      libxext
      libxfixes
      libxi
      libxrandr
      libxrender
      libxtst
      libxcb
      libxcb-image
      libxcb-keysyms
      libxcb-render-util
      libxcb-wm
      # device access helpers the app shells out to
      usbmuxd
      libimobiledevice
      usbutils
    ];

  runScript = writeShellScript "3utools-run" ''
    # The bundle's ELF interpreter is the relative path ./lib/ld-linux-x86-64.so.2,
    # so it must be started from its own directory (this is what run.sh does too).
    cd ${appDir}
    export QT_AUTO_SCREEN_SCALE_FACTOR=0
    export QT_XCB_GL_INTEGRATION=none
    export QT_QPA_PLATFORM=xcb
    exec ./3uTools "$@"
  '';

  extraInstallCommands = ''
    install -Dm644 ${unwrapped}/usr/share/icons/hicolor/scalable/apps/com.3u.3utools.svg \
      $out/share/icons/hicolor/scalable/apps/3utools.svg
    install -Dm644 ${unwrapped}/lib/udev/rules.d/38-3uTools.rules \
      $out/lib/udev/rules.d/38-3uTools.rules

    mkdir -p $out/share/applications
    cat > $out/share/applications/3utools.desktop <<EOF
    [Desktop Entry]
    Type=Application
    Name=3uTools
    Comment=Apple Device Management Tool
    Exec=$out/bin/3utools
    Icon=3utools
    Terminal=false
    Categories=Utility;
    Keywords=3uTools;3u;iPhone;iOS;
    StartupWMClass=3uTools
    EOF
  '';

  passthru = { inherit unwrapped; };

  meta = {
    description = "3uTools - Apple device (iPhone/iPad) management tool";
    homepage = "https://www.3u.com";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "3utools";
  };
}
