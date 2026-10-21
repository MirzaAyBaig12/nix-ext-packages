{
  lib,
  appimageTools,
  fetchurl,
}:

let
  pname = "sklauncher";
  version = "4.0.55";

  src = fetchurl {
    url = "https://github.com/sklauncher/binaries/releases/download/v${version}/SKlauncher-${version}-x86_64.AppImage";
    hash = "sha256-M/j5BgnQ8TZaF+eLfZyEUm+1yhAG/dtOlDf2+8+P7jc=";
  };

  appimageContents = appimageTools.extract {
    inherit pname version src;
  };
in
appimageTools.wrapType2 {
  inherit pname version src;

  extraInstallCommands = ''
    install -Dm644 \
      ${appimageContents}/pl.skmedix.sklauncher.desktop \
      $out/share/applications/SKLauncher.desktop

    install -Dm644 \
      ${appimageContents}/usr/share/icons/hicolor/512x512/apps/sklauncher.png \
      $out/share/icons/hicolor/512x512/apps/sklauncher.png

    substituteInPlace $out/share/applications/SKLauncher.desktop \
      --replace-fail 'Name=SKlauncher' 'Name=SKLauncher' \
      --replace-fail 'Exec=AppRun --no-sandbox %U' 'Exec=sklauncher %U'
  '';

  meta = {
    description = "Minecraft launcher";
    homepage = "https://skmedix.pl";
    license = lib.licenses.gpl3Only;
    platforms = [ "x86_64-linux" ];
    mainProgram = "sklauncher";
  };
}