{
  lib,
  stdenvNoCC,
  fetchurl,
}:

# AirPlay sender for Linux (X11 & Wayland), github.com/omarroth/doubletake.
# Upstream ships fully static x86_64 binaries, so they are installed as-is.
let
  version = "0.6.0";

  doubletake = fetchurl {
    url = "https://github.com/omarroth/doubletake/releases/download/v${version}/doubletake";
    hash = "sha256-Aftse53m871pOmKeJI/mHOt68GNTyPPyHMKYeNH59d4=";
  };
  doubletake-ctl = fetchurl {
    url = "https://github.com/omarroth/doubletake/releases/download/v${version}/doubletake-ctl";
    hash = "sha256-5UGMFzBnfT+PZIDAxftLS2ioWkCLNtnSnDDE8BBgirQ=";
  };
  manpages = fetchurl {
    url = "https://github.com/omarroth/doubletake/releases/download/v${version}/doubletake-manpages.tar.gz";
    hash = "sha256-n734uR3qS1ELVHYC9QTHiljeLOD40fs8wAbepfDBGdw=";
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
