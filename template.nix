/*
  Template for a new AppImage package.

  1. Copy this to packages/<name>.nix
  2. Fill in pname, owner/repo, the AppImage filename, and meta
  3. Add it to flake.nix:
       <name> = pkgs.callPackage ./packages/<name>.nix { };
  4. Run ./scripts/update.sh to fill in the real hash (or `nix build` and copy
     the hash from the error)

  For scripts/update.sh to auto-bump it, keep:
    - `version = "x.y.z";` as a plain string
    - `url = "https://github.com/<owner>/<repo>/releases/download/<tag-prefix>${version}/..."`
    - `hash = "...";` right next to the url
*/
{
  lib,
  appimageTools,
  fetchurl,
}:

let
  pname = "changeme";
  version = "0.0.0";

  src = fetchurl {
    url = "https://github.com/OWNER/REPO/releases/download/v${version}/APPNAME-${version}.AppImage";
    hash = lib.fakeHash;
  };

  appimageContents = appimageTools.extract {
    inherit pname version src;
  };
in
appimageTools.wrapType2 {
  inherit pname version src;

  extraInstallCommands = ''
    # Check the real file names with: nix build, then ls the extracted contents
    install -Dm644 \
      ${appimageContents}/APPNAME.desktop \
      $out/share/applications/APPNAME.desktop

    # Optional: icon
    # install -Dm644 \
    #   ${appimageContents}/usr/share/icons/hicolor/512x512/apps/APPNAME.png \
    #   $out/share/icons/hicolor/512x512/apps/APPNAME.png

    substituteInPlace $out/share/applications/APPNAME.desktop \
      --replace-fail 'Exec=AppRun --no-sandbox %U' 'Exec=${pname} %U'
  '';

  meta = {
    description = "CHANGEME";
    homepage = "https://github.com/OWNER/REPO";
    license = lib.licenses.unfree; # change me
    platforms = [ "x86_64-linux" ];
    mainProgram = pname;
  };
}
