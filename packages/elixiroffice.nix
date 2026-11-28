{
  lib,
  appimageTools,
  fetchurl,
}:

let
  pname = "elixiroffice";
  version = "0.9.5";

  src = fetchurl {
    url = "https://github.com/leag1234/ElixirOffice/releases/download/v${version}/ElixirOffice-${version}-x86_64.AppImage";
    hash = "sha256-f/2oRTTdafZGFlRrFl+qgutWmtaHyc6IIOWI1LqEpFw=";
  };

  appimageContents = appimageTools.extract {
    inherit pname version src;
  };
in
appimageTools.wrapType2 {
  inherit pname version src;

  extraInstallCommands = ''
    # Desktop entry + icons straight from the AppImage.
    desktop="$(find ${appimageContents} -maxdepth 1 -name '*.desktop' | head -n1)"
    install -Dm644 "$desktop" $out/share/applications/elixiroffice.desktop

    if [ -d ${appimageContents}/usr/share/icons ]; then
      mkdir -p $out/share
      cp -r ${appimageContents}/usr/share/icons $out/share/
    fi

    if [ -d ${appimageContents}/usr/share/licenses ]; then
      mkdir -p $out/share
      cp -r ${appimageContents}/usr/share/licenses $out/share/
    fi

    substituteInPlace $out/share/applications/elixiroffice.desktop \
      --replace-quiet 'Exec=AppRun' 'Exec=elixiroffice'
  '';

  meta = {
    description = "ElixirOffice, an open source office suite with a Microsoft Office-style ribbon (desktop beta, AppImage)";
    homepage = "https://github.com/leag1234/ElixirOffice";
    license = lib.licenses.agpl3Only;
    platforms = [ "x86_64-linux" ];
    mainProgram = "elixiroffice";
  };
}
