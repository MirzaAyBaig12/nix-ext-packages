/*
  Prospect Mail (Outlook Web wrapper) from the official .deb.

  The deb is an Electron app that needs standard Electron dependencies.
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
  nss,
  libsecret,
  glib-networking,
  gsettings-desktop-schemas,
  adwaita-icon-theme,
  hicolor-icon-theme,
  libappindicator-gtk3,
}:

let
  pname = "prospect-mail";
  version = "1.3.2";

  src = fetchurl {
    url = "https://github.com/julian-alarcon/prospect-mail/releases/download/v${version}/prospect-mail_${version}_amd64.deb";
    hash = "sha256-/Muw1VFLnXgjKuayHBwFGlhB5OFqV822U0NwIYOf/C0=";
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
      cp -r opt $out/
      runHook postInstall
    '';
  };

in
buildFHSEnv {
  inherit pname version;

  targetPkgs =
    pkgs: with pkgs; [
      # Electron app dependencies
      gtk3
      nss
      libsecret
      libappindicator-gtk3
      nspr
      libX11
      libXcomposite
      libXdamage
      libXext
      libXfixes
      libXrandr
      libXrender
      libgbm
      expat
      libxcb
      systemd
      alsa-lib
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
      libnotify
      at-spi2-core
      cups
      libxscrnsaver
      libxtst
    ];

  runScript = writeShellScript "prospect-mail-run" ''
    # GTK file dialogs abort without the gtk3 / desktop gsettings schemas
    export XDG_DATA_DIRS="${gtk3}/share/gsettings-schemas/${gtk3.name}:${gsettings-desktop-schemas}/share/gsettings-schemas/${gsettings-desktop-schemas.name}:/usr/share:''${XDG_DATA_DIRS:-}"
    # WebKitGTK needs glib-networking's GIO modules for TLS/HTTPS support
    export GIO_EXTRA_MODULES="${glib-networking}/lib/gio/modules"
    exec ${unwrapped}/opt/Prospect\ Mail/prospect-mail "$@"
  '';

  extraInstallCommands = ''
    mkdir -p $out/share/icons
    cp -r ${unwrapped}/usr/share/icons/hicolor $out/share/icons/

    # absolute Exec: some compositors (kwin) don't resolve a bare Exec via PATH
    mkdir -p $out/share/applications
    cat > $out/share/applications/prospect-mail.desktop <<EOF
    [Desktop Entry]
    Type=Application
    Name=Prospect Mail
    Comment=Outlook Web wrapper with system tray, notifications, and unread count
    Exec=$out/bin/prospect-mail
    Icon=prospect-mail
    Terminal=false
    Categories=Network;Email;
    Keywords=Outlook;Email;Web;
    StartupWMClass=prospect-mail
    EOF
  '';

  meta = {
    description = "Outlook Web wrapper with system tray, notifications, and unread count";
    homepage = "https://github.com/julian-alarcon/prospect-mail";
    license = lib.licenses.mit;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "prospect-mail";
  };
}