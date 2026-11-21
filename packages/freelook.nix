/*
  Freelook (Outlook Web wrapper) from the official .deb.

  The deb is a Tauri app that needs GTK3, libappindicator-gtk3, nss, libsecret.
  It is run inside an FHS env so the binary can find its dependencies at runtime.

  For scripts/update.sh to auto-bump it, keep `version`, `url` and `hash` as plain
  strings and the url on the GitHub release pattern below (tags are `v<version>`).
*/
{
  lib,
  stdenv,
  fetchurl,
  dpkg,
  buildFHSEnv,
  writeShellScript,
  gtk3,
  libappindicator-gtk3,
  nss,
  libsecret,
  glib-networking,
  gsettings-desktop-schemas,
  adwaita-icon-theme,
  hicolor-icon-theme,
}:

let
  pname = "freelook";
  version = "2.0.3";

  src = fetchurl {
    url = "https://github.com/eNkru/freelook/releases/download/v${version}/Freelook_${version}_amd64.deb";
    hash = "sha256-r5+TL34UwsDVb48RgI+bUDU6ds+SoNVLO6QXGYebfWE=";
  };

  # The deb's payload, untouched.
  unwrapped = stdenv.mkDerivation {
    pname = "${pname}-unwrapped";
    inherit version src;

    nativeBuildInputs = [ dpkg ];

    dontConfigure = true;
    dontBuild = true;
    # Run as shipped inside the FHS env: no patchelf, no stripping.
    dontFixup = true;

    unpackPhase = ''
      runHook preUnpack
      dpkg-deb -x $src .
      runHook postUnpack
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p $out
      cp -r usr $out/
      runHook postInstall
    '';
  };

in
buildFHSEnv {
  inherit pname version;

  targetPkgs =
    pkgs: with pkgs; [
      # What the binary links against (the deb's Depends)
      gtk3
      webkitgtk_4_1
      libsoup_3
      libappindicator-gtk3
      nss
      libsecret
      openssl
      glib
      cairo
      gdk-pixbuf
      pango
      dbus
      glib-networking
      libGL
      libglvnd
      mesa
      libxkbcommon
      wayland
      fontconfig
      freetype
      adwaita-icon-theme
      hicolor-icon-theme
      shared-mime-info
      cacert
    ];

  runScript = writeShellScript "freelook-run" ''
    # GTK file dialogs abort without the gtk3 / desktop gsettings schemas
    export XDG_DATA_DIRS="${gtk3}/share/gsettings-schemas/${gtk3.name}:${gsettings-desktop-schemas}/share/gsettings-schemas/${gsettings-desktop-schemas.name}:/usr/share:''${XDG_DATA_DIRS:-}"
    # WebKitGTK needs glib-networking's GIO modules for TLS/HTTPS support
    export GIO_EXTRA_MODULES="${glib-networking}/lib/gio/modules"
    exec ${unwrapped}/usr/bin/freelook "$@"
  '';

  extraInstallCommands = ''
    mkdir -p $out/share/icons
    cp -r ${unwrapped}/usr/share/icons/hicolor $out/share/icons/

    # absolute Exec: some compositors (kwin) don't resolve a bare Exec via PATH
    mkdir -p $out/share/applications
    cat > $out/share/applications/freelook.desktop <<EOF
    [Desktop Entry]
    Type=Application
    Name=Freelook
    Comment=Outlook Web wrapper with system tray, notifications, and ad blocking
    Exec=$out/bin/freelook
    Icon=freelook
    Terminal=false
    Categories=Network;Email;
    Keywords=Outlook;Email;Web;
    StartupWMClass=freelook
    EOF
  '';

  meta = {
    description = "Outlook Web wrapper with system tray, notifications, and ad blocking";
    homepage = "https://github.com/eNkru/freelook";
    license = lib.licenses.mit;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "freelook";
  };
}