{
  lib,
  appimageTools,
  fetchurl,
}:

let
  pname = "sklauncher";
  version = "4.0.54";

  src = fetchurl {
    url = "https://github.com/sklauncher/binaries/releases/download/v${version}/SKlauncher-${version}-x86_64.AppImage";
    hash = lib.fakeHash;
  };

  appimageContents = appimageTools.extract {
    inherit pname version src;
  };
in
appimageTools.wrapType2 {
  inherit pname version src;

  extraInstallCommands = ''
    if [ -f ${appimageContents}/sklauncher.desktop ]; then
      install -Dm644 \
        ${appimageContents}/sklauncher.desktop \
        $out/share/applications/SKLauncher.desktop
    fi
  '';

  meta = {
    description = "Minecraft launcher";
    homepage = "https://skmedix.pl";
    license = lib.licenses.gpl3Only;
    platforms = [ "x86_64-linux" ];
    mainProgram = "sklauncher";
  };
}