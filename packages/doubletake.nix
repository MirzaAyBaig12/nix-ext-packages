{
  lib,
  stdenvNoCC,
  fetchurl,
}:

# AirPlay sender for Linux (X11 & Wayland), github.com/omarroth/doubletake.
# Upstream ships fully static x86_64 binaries, so they are installed as-is.
let
  version = "0.5.0";
  base = "https://github.com/omarroth/doubletake/releases/download/v${version}";

  doubletake = fetchurl {
    url = "${base}/doubletake";
    hash = "sha256-WQJ0VbuETxURkjJgBWmt7XISAycQAVkaCvxaDQfAa1w=";
  };
  doubletake-ctl = fetchurl {
    url = "${base}/doubletake-ctl";
    hash = "sha256-HPQBlfg+9MH4hTkuG5DSzgdycLk5GjinF1mBcMsapOs=";
  };
  manpages = fetchurl {
    url = "${base}/doubletake-manpages.tar.gz";
    hash = "sha256-aIrFGxDgCuq0ogMGAyThu4v5KJLBz9slj71rfOAUdd0=";
  };
in
stdenvNoCC.mkDerivation {
  pname = "doubletake";
  inherit version;

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 ${doubletake} $out/bin/doubletake
    install -Dm755 ${doubletake-ctl} $out/bin/doubletake-ctl

    mkdir -p $out/share/man
    tar -xzf ${manpages} -C $out/share/man

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
