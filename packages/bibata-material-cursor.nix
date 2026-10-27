/*
  Bibata Material cursor themes (Ayaan's Material Design 3 fork of Bibata).
  nixpkgs' bibata-cursors has no Material variants, so this is packaged from the
  prebuilt release tarball (dark variants only, under share/icons, e.g. Bibata-Material-Lilac).
  Upstream split the release into dark/light tarballs after 1.2.1; this packages the dark one.

  scripts/update.sh bumps this automatically, so keep:
    - `version = "x.y.z";` as a plain string
    - `url = "https://github.com/<owner>/<repo>/releases/download/v${version}/..."`
    - `hash = "...";` right next to the url
*/
{
  lib,
  stdenvNoCC,
  fetchurl,
}:

let
  version = "1.5.0";
in
stdenvNoCC.mkDerivation {
  pname = "bibata-material-cursor";
  inherit version;

  src = fetchurl {
    url = "https://github.com/SakibShahariar/material-bibata-cursor/releases/download/v${version}/bibata-material-dark-v${version}.tar.gz";
    hash = "sha256-igz93WB4fGWgeM5JS1cIwdaPPldhGP3gcBlJ7bQMugQ=";
  };

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/icons
    cp -r Bibata-Material-* $out/share/icons/
    runHook postInstall
  '';

  meta = {
    description = "Bibata cursor themes (dark variants) using Material Design 3's tonal system (Ayaan's fork)";
    homepage = "https://github.com/SakibShahariar/material-bibata-cursor";
    license = lib.licenses.gpl3Only;
    platforms = lib.platforms.all;
  };
}
