{
  lib,
  appimageTools,
  buildFHSEnv,
  fetchurl,
  writeShellScript,
}:

let
  pname = "hydra-launcher";
  version = "4.1.6";

  src = fetchurl {
    url = "https://github.com/hydralauncher/hydra/releases/download/v${version}/hydralauncher-${version}.AppImage";
    hash = "sha256-yX4FsqFS3udMAlokRPk5YbzmmOjnkNIxfCs7en2cv8I=";
  };

  appimageContents = appimageTools.extract {
    inherit pname version src;
  };

  fhsArgs = appimageTools.defaultFhsEnvArgs;
in
buildFHSEnv {
  inherit pname version;

  # same base lib set as wrapType2, plus what umu-run / ludusavi / games want
  targetPkgs =
    pkgs:
    (fhsArgs.targetPkgs pkgs)
    ++ (with pkgs; [
      python3
      zstd
      cabextract
      libusb1
      libpulseaudio
      libGL
      vulkan-loader
      udev
    ]);

  multiPkgs =
    pkgs:
    (fhsArgs.multiPkgs pkgs)
    ++ (with pkgs; [
      libGL
      vulkan-loader
      libpulseaudio
    ]);

  runScript = writeShellScript "hydra-launcher-run" ''
    exec ${appimageContents}/hydralauncher --no-sandbox "$@"
  '';

  extraInstallCommands = ''
    install -Dm644 \
      ${appimageContents}/hydralauncher.desktop \
      $out/share/applications/Hydra-Launcher.desktop

    substituteInPlace $out/share/applications/Hydra-Launcher.desktop \
      --replace-fail 'Name=Hydra' 'Name=Hydra Launcher' \
      --replace-fail 'Exec=AppRun --no-sandbox %U' 'Exec=hydra-launcher %U'

    install -Dm644 \
      ${appimageContents}/hydralauncher.png \
      $out/share/icons/hicolor/512x512/apps/hydralauncher.png

    ln -s $out/bin/hydra-launcher $out/bin/hydralauncher
  '';

  meta = {
    description = "Game launcher";
    homepage = "https://github.com/hydralauncher/hydra";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "hydra-launcher";
  };
}
