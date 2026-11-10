/*
  iloader (user-friendly iOS sideloader, Rust + Tauri) from the official .deb.

  The deb is a single dynamically linked Tauri binary (/usr/bin/iloader: ELF
  interpreter /lib64/ld-linux-x86-64.so.2, needs GTK3 + WebKitGTK 4.1 + libsoup3).
  It is run unpatched inside an FHS env instead of autoPatchelf so it finds
  /lib64, /usr/lib etc. like on a regular distro.

  Device access: iloader doesn't link libimobiledevice/libusb, it talks to the usbmuxd
  daemon over /var/run/usbmuxd (-> /run/usbmuxd) with the Rust idevice crate. The FHS
  env keeps /run from the host, so that socket is visible as long as the daemon runs.
  Needs this on the NixOS side (not part of this package):
    services.usbmuxd.enable = true;   # daemon + the udev rules for Apple devices

  For scripts/update.sh to auto-bump it, keep `version`, `url` and `hash` as plain
  strings and the url on the GitHub release pattern below (tags are `v<version>`).

  iloader has a self-updater; it can't replace anything in the read-only store, so
  update this package instead.
*/
{
  lib,
  stdenvNoCC,
  fetchurl,
  dpkg,
  buildFHSEnv,
  writeShellScript,
  gtk3,
  gsettings-desktop-schemas,
}:

let
  pname = "iloader";
  version = "2.4.1";

  src = fetchurl {
    url = "https://github.com/nab138/iloader/releases/download/v${version}/iloader-linux-amd64.deb";
    hash = "sha256-k/HmbBc6R5JXBMR1fBN+dm/6UTOuwfQXbYMf94Up6Xk=";
  };

  # The deb's payload, untouched.
  unwrapped = stdenvNoCC.mkDerivation {
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
      # what the binary links against (the deb's Depends: webkit2gtk-4.1, gtk-3)
      gtk3
      webkitgtk_4_1
      libsoup_3
      glib
      cairo
      gdk-pixbuf
      pango
      dbus
      # TLS for libsoup (loaded as a GIO module, see GIO_EXTRA_MODULES below)
      glib-networking
      # webview rendering, fonts, icons
      libGL
      libglvnd
      mesa
      libxkbcommon
      wayland
      fontconfig
      freetype
      dejavu_fonts
      adwaita-icon-theme
      shared-mime-info
      cacert
      # Apple ID / developer-portal HTTPS, libusb for anything that talks USB directly
      openssl
      libusb1
      zlib
      stdenv.cc.cc.lib
      # handy for debugging device detection from inside the env
      usbmuxd
      libimobiledevice
      usbutils
    ];

  runScript = writeShellScript "iloader-run" ''
    # libsoup needs glib-networking's GIO modules for https
    export GIO_EXTRA_MODULES=/usr/lib/gio/modules
    # GTK file dialogs (pick IPA / save pairing file) abort without the gtk3 / desktop gsettings schemas
    export XDG_DATA_DIRS="${gtk3}/share/gsettings-schemas/${gtk3.name}:${gsettings-desktop-schemas}/share/gsettings-schemas/${gsettings-desktop-schemas.name}:/usr/share:''${XDG_DATA_DIRS:-}"
    exec ${unwrapped}/usr/bin/iloader "$@"
  '';

  extraInstallCommands = ''
    mkdir -p $out/share/icons
    cp -r ${unwrapped}/usr/share/icons/hicolor $out/share/icons/

    # absolute Exec: some compositors (kwin) don't resolve a bare Exec via PATH
    mkdir -p $out/share/applications
    cat > $out/share/applications/iloader.desktop <<EOF
    [Desktop Entry]
    Type=Application
    Name=iloader
    Comment=User-friendly sideloader
    Exec=$out/bin/iloader
    Icon=iloader
    Terminal=false
    Categories=Utility;
    Keywords=iOS;iPhone;iPad;sideload;IPA;
    StartupWMClass=iloader
    EOF
  '';

  passthru = { inherit unwrapped; };

  meta = {
    description = "User-friendly iOS sideloader";
    homepage = "https://iloader.app";
    license = lib.licenses.mit;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "iloader";
  };
}
