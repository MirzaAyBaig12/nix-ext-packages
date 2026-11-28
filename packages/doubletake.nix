{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  glib,
  gst_all_1,
}:

# AirPlay sender for Linux (X11 & Wayland), github.com/omarroth/doubletake.
# Upstream ships a tarball with a dynamically linked x86_64 binary (GStreamer
# is used for video); `doubletake ctl` is part of the main binary since 0.7.0.
let
  version = "0.7.0";

  src = fetchurl {
    url = "https://github.com/omarroth/doubletake/releases/download/v${version}/doubletake-v${version}-linux-x86_64.tar.gz";
    hash = "sha256-xjfRaChFWiEUaRFN4668DDLQdAA492U0j4EjEC1NSbw=";
  };
in
stdenv.mkDerivation {
  pname = "doubletake";
  inherit version;

  inherit src;

  nativeBuildInputs = [ autoPatchelfHook ];

  buildInputs = [
    glib
    gst_all_1.gstreamer
    gst_all_1.gst-plugins-base
  ];

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out
    tar -xzf $src -C $out --strip-components=1

    runHook postInstall
  '';

  meta = {
    description = "AirPlay sender implementation for Linux (X11 & Wayland)";
    homepage = "https://github.com/omarroth/doubletake";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "doubletake";
  };
}
