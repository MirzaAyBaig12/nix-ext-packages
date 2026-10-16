{
  lib,
  appimageTools,
  fetchurl,
}:

let
  pname = "hydra-launcher";
  version = "4.2.0";

  src = fetchurl {
    url = "https://github.com/hydralauncher/hydra/releases/download/v${version}/hydralauncher-${version}.AppImage";
    hash = "sha256-p/97sPEx00DWhXR2WfkoNxEkBC7FKl94l8apD7zv3gc=";
  };

  appimageContents = appimageTools.extract {
    inherit pname version src;
  };
in
appimageTools.wrapType2 {
  inherit pname version src;

  extraInstallCommands = ''
    install -Dm644 \
      ${appimageContents}/hydralauncher.desktop \
      $out/share/applications/Hydra-Launcher.desktop

    substituteInPlace $out/share/applications/Hydra-Launcher.desktop \
      --replace-fail 'Name=Hydra' 'Name=Hydra Launcher' \
      --replace-fail 'Exec=AppRun --no-sandbox %U' 'Exec=hydra-launcher %U'
  '';

  postInstall = ''
    ln -s $out/bin/hydralauncher $out/bin/hydra-launcher
  '';

  meta = {
    name = "Hydra Launcher";
    description = "Game launcher";
    homepage = "https://github.com/hydralauncher/hydra";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "hydra-launcher";
  };
}