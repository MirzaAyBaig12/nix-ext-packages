/*
  DriveDeck for OneDrive (Rust + Slint) from the official .deb.

  DriveDeck is a tray icon and settings window for the OneDrive Client for Linux
  by abraunegg. It deliberately does not bundle the client: it looks for
  `onedrive` on PATH (or $DRIVEDECK_CLIENT), so the client keeps getting updates
  from its own package. This package wraps the app with nixpkgs' `onedrive` on
  PATH and in $DRIVEDECK_CLIENT, so it works out of the box.

  The deb's binary is a normal dynamically linked ELF (interpreter
  /lib64/ld-linux-x86-64.so.2) that also dlopens the EGL/Wayland/X11/xkbcommon
  libraries. Instead of an FHS env (which would break the app's frequent
  self-re-exec for --tray/--popup/--settings and its generated autostart file),
  autoPatchelf bakes the Nix store RPATHs into the binary and a small wrapper
  adds the client and helper tools to PATH.

  The app's "Install it for me" button only knows apt/dnf/zypper/pacman, so on
  NixOS it isn't offered; install the client with `onedrive` (this package
  already puts it on the wrapper's PATH) or the app's manual instructions.

  The Qt6/KF6 Dolphin overlay-icon plugin is installed under
  $out/lib/qt6/plugins/kf6/overlayicon. Add $out/lib/qt6/plugins to
  QT_PLUGIN_PATH if you want the badges in Dolphin; the main app doesn't need it.

  For scripts/update.sh to auto-bump it, keep `version`, `url` and `hash` as
  plain strings and the url on the GitHub release pattern below (tags are
  `v<version>`).
*/
{
  lib,
  stdenv,
  fetchurl,
  dpkg,
  autoPatchelfHook,
  makeWrapper,
  fontconfig,
  freetype,
  libglvnd,
  mesa,
  wayland,
  libxkbcommon,
  libx11,
  libxcursor,
  libxrandr,
  libxi,
  libxext,
  libxfixes,
  libxrender,
  libxcb,
  dbus,
  glib,
  zlib,
  qt6,
  kdePackages,
  onedrive,
  systemd,
  util-linux,
  coreutils,
  xdg-utils,
  xdg-user-dirs,
  zenity,
}:

let
  pname = "drivedeck";
  version = "1.6.2";

  src = fetchurl {
    url = "https://github.com/sweatshopking/DriveDeck/releases/download/v${version}/drivedeck_${version}_amd64.deb";
    hash = "sha256-KSP2UEKVpj5d56pwJuiI2LoVVXPsd4q8S0lTkKxyhlU=";
  };

  # Everything the binary dlopens at runtime (the deb's Depends:, plus the
  # toolkit libraries Slint's winit backend picks from the host).
  runtimeLibs = [
    fontconfig.lib
    freetype
    libglvnd
    mesa
    wayland
    libxkbcommon
    libx11
    libxcursor
    libxrandr
    libxi
    libxext
    libxfixes
    libxrender
    libxcb
    dbus
    glib.out
    zlib
  ];

  # Programs the app shells out to. `onedrive` is the sync engine itself.
  runtimeBins = [
    onedrive
    systemd
    util-linux
    coreutils
    xdg-utils
    xdg-user-dirs
    zenity
  ];
in
stdenv.mkDerivation {
  inherit pname version src;

  nativeBuildInputs = [
    dpkg
    autoPatchelfHook
    makeWrapper
  ];

  # autoPatchelf needs the linked libs, and runtimeDependencies adds their /lib
  # to the RPATH so the dlopened ones are found too.
  buildInputs = runtimeLibs ++ [
    qt6.qtbase
    kdePackages.kio
  ];
  runtimeDependencies = runtimeLibs ++ [
    qt6.qtbase
    kdePackages.kio
  ];

  dontConfigure = true;
  dontBuild = true;
  # Qt is only there for the optional Dolphin plugin, not the app itself.
  dontWrapQtApps = true;

  unpackPhase = ''
    runHook preUnpack
    dpkg-deb -x $src .
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out
    cp -r usr/. $out/

    # Keep the real binary out of bin/ so the wrapper can own bin/drivedeck.
    mkdir -p $out/libexec/drivedeck
    mv $out/bin/drivedeck $out/libexec/drivedeck/drivedeck
    ln -sfn ../libexec/drivedeck/drivedeck $out/bin/drivedeck
    ln -sfn drivedeck $out/bin/linux-onedrive-gui

    # The deb puts the Dolphin plugin under the multiarch Qt path; use the
    # layout Nix users expect instead.
    mkdir -p $out/lib/qt6/plugins/kf6/overlayicon
    mv $out/lib/x86_64-linux-gnu/qt6/plugins/kf6/overlayicon/drivedeck-badges.so \
      $out/lib/qt6/plugins/kf6/overlayicon/
    rm -rf $out/lib/x86_64-linux-gnu

    # Some compositors don't resolve a bare Exec via PATH.
    substituteInPlace $out/share/applications/drivedeck.desktop \
      --replace-fail 'Exec=drivedeck' "Exec=$out/bin/drivedeck"

    # Point the polkit action at the helper in the store (the app itself falls
    # back to running the script through pkexec when /usr/libexec is absent).
    substituteInPlace $out/share/polkit-1/actions/io.github.sweatshopking.DriveDeck.policy \
      --replace-fail '/usr/libexec/drivedeck/install-client' \
      "$out/libexec/drivedeck/install-client"

    runHook postInstall
  '';

  postFixup = ''
    wrapProgram $out/bin/drivedeck \
      --prefix PATH : ${lib.makeBinPath runtimeBins} \
      --set DRIVEDECK_CLIENT ${onedrive}/bin/onedrive
  '';

  meta = {
    description = "DriveDeck for OneDrive: a friendly front end for the OneDrive Client for Linux";
    homepage = "https://github.com/sweatshopking/DriveDeck";
    license = lib.licenses.gpl3Plus;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "drivedeck";
  };
}
