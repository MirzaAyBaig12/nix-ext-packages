
{
  lib,
  appimageTools,
  fetchurl,
}:

let
  pname = "modrinth";
  version = "0.22.1";

  src = fetchurl {
    url = "https://github.com/modrinth/code/releases/download/v${version}/Modrinth.App_${version}_amd64.AppImage";
    hash = "sha256-qBU1xV6V6iYzXVxkjd7Ps56Kv5s/pr8n2PoAwWz38WE=";
  };

  appimageContents = appimageTools.extract {
    inherit pname version src;
  };
in
appimageTools.wrapType2 {
  inherit pname version src;

  extraInstallCommands = ''
    install -Dm644 \
      "${appimageContents}/Modrinth App.desktop" \
      $out/share/applications/modrinth.desktop

    install -Dm644 \
      "${appimageContents}/usr/share/icons/hicolor/128x128/apps/ModrinthApp.png" \
      $out/share/icons/hicolor/128x128/apps/ModrinthApp.png

    install -Dm644 \
      "${appimageContents}/usr/share/icons/hicolor/256x256@2/apps/ModrinthApp.png" \
      $out/share/icons/hicolor/512x512/apps/ModrinthApp.png

    substituteInPlace $out/share/applications/modrinth.desktop \
      --replace-fail 'Exec=ModrinthApp' 'Exec=modrinth %U'
  '';

  meta = {
    description = "Modrinth App - Minecraft launcher and mod manager";
    homepage = "https://modrinth.com/app";
    license = lib.licenses.gpl3Only;
    platforms = [ "x86_64-linux" ];
    mainProgram = "modrinth";
  };
}
