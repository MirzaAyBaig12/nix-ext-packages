/*
  Ladybird browser from the official Fedora RPM (the deb releases are Ubuntu
  LTS-only, the RPM is not).

  The RPM installs a complete /opt/ladybird tree: the Ladybird/WebDriver
  binaries, libexec helpers, and bundled copies of ICU, ffmpeg, dbus, etc.
  Both the binaries and the helpers use RUNPATH $ORIGIN:$ORIGIN/../lib64, so
  the tree is copied verbatim and run unpatched inside an FHS env. That keeps
  the helpers finding the same bundled libraries and lets Qt find its platform
  plugins the usual way.

  Not on GitHub releases: scripts/update.sh reads the yum repodata at
  rpm.ladybird.org and bumps the version/hash (and the -N.fcXX release) when a
  newer x86_64 RPM appears.
*/
{
  lib,
  stdenvNoCC,
  fetchurl,
  rpm,
  cpio,
  buildFHSEnv,
  writeShellScript,
}:

let
  pname = "ladybird";
  version = "2026.48.0";

  src = fetchurl {
    url = "https://rpm.ladybird.org/packages/ladybird-${version}-1.fc44.x86_64.rpm";
    hash = "sha256-3RDQ/bB1aFtA0aZ5xFKiNc+XFR13Y+a/e8b+0oBAfbQ=";
  };

  # The RPM payload, untouched.
  unwrapped = stdenvNoCC.mkDerivation {
    pname = "${pname}-unwrapped";
    inherit version src;

    nativeBuildInputs = [ rpm cpio ];

    dontConfigure = true;
    dontBuild = true;
    # Keep the binaries and their $ORIGIN runpaths exactly as shipped.
    dontFixup = true;

    unpackPhase = ''
      runHook preUnpack
      mkdir -p source
      cd source
      rpm2cpio "$src" | cpio -idm --quiet
      cd ..
      runHook postUnpack
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p $out
      cp -r source/opt $out/
      cp -r source/usr/share $out/
      runHook postInstall
    '';
  };
in
buildFHSEnv {
  inherit pname version;

  targetPkgs =
    pkgs: with pkgs; [
      # what the binaries link against outside the bundled lib64
      qt6.qtbase
      qt6.qtpositioning
      qt6.qtwayland
      libglvnd
      libdrm # needed by the bundled FFmpeg libs
      vulkan-loader
      wayland
      xcbutil
      libxcb
      libxcb-wm # libxcb-icccm.so.4
      glib
      dbus
      # the RPM's Requires: liberation-(mono|sans|-serif)-fonts
      liberation_ttf
      dejavu_fonts
      fontconfig
      freetype
      adwaita-icon-theme
      shared-mime-info
      cacert
      pulseaudio
      xdg-utils
      stdenv.cc.cc.lib
    ];

  runScript = writeShellScript "ladybird-run" ''
    exec ${unwrapped}/opt/ladybird/bin/Ladybird "$@"
  '';

  extraInstallCommands = ''
    mkdir -p $out/share
    cp -r ${unwrapped}/share/applications ${unwrapped}/share/icons \
      ${unwrapped}/share/metainfo $out/share/

    # The shipped desktop file points at /opt/ladybird/bin/Ladybird; point its
    # main Exec and the "New Window" action at the FHS wrapper instead.
    substituteInPlace $out/share/applications/org.ladybird.Ladybird.desktop \
      --replace-fail '/opt/ladybird/bin/Ladybird' "$out/bin/ladybird"
  '';

  passthru = { inherit unwrapped; };

  meta = {
    description = "Independent web browser with its own engine, built from the official RPM";
    homepage = "https://ladybird.org";
    license = lib.licenses.bsd2;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "ladybird";
  };
}
