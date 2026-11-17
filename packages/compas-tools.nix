{
  lib,
  appimageTools,
  fetchurl,
}:

let
  pname = "compas-tools";
  version = "0.1.5";

  src = fetchurl {
    url = "https://github.com/Starnished66/compas-tools/releases/download/v${version}/Compas.Tools_${version}_amd64.AppImage";
    hash = "sha256-wuqXCJHGGxpbL/rrqIeIDGqPBLutggS/rxoEM7gz2MQ=";
  };

  appimageContents = appimageTools.extract {
    inherit pname version src;
  };
in
appimageTools.wrapType2 {
  inherit pname version src;

  extraInstallCommands = ''
    desktopFile=$(find ${appimageContents} -type f -name '*.desktop' -print -quit)
    test -n "$desktopFile"
    install -Dm644 "$desktopFile" $out/share/applications/compas-tools.desktop

    sed -i 's|^Exec=.*|Exec=compas-tools %U|' \
      $out/share/applications/compas-tools.desktop
  '';

  meta = {
    description = "Desktop companion for Compás music players";
    homepage = "https://github.com/Starnished66/compas-tools";
    license = lib.licenses.gpl3Only;
    platforms = [ "x86_64-linux" ];
    mainProgram = pname;
  };
}
