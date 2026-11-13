/*
  OpenIDEA (open-source IntelliJ IDEA-style IDE, Rust + Tauri) from the official .deb.

  The deb is a single dynamically linked Tauri binary (/usr/bin/openidea: ELF
  interpreter /lib64/ld-linux-x86-64.so.2, needs GTK3 + WebKitGTK 4.1 + libsoup3).
  It is run unpatched inside an FHS env instead of autoPatchelf, so the language
  servers, JDKs and other generic Linux binaries the IDE downloads at runtime
  (Settings > Language Servers, "Download JDK", ...) can find /lib64, /usr/lib etc.

  For scripts/update.sh to auto-bump it, keep `version`, `url` and `hash` as plain
  strings and the url on the GitHub release pattern below (tags are `v<version>`).

  OpenIDEA has a self-updater ("Check for Updates"); it can't replace anything in the
  read-only store, so update this package instead.
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
  pname = "openidea";
  version = "0.1.44";

  src = fetchurl {
    url = "https://github.com/l0ng-ai/openidea/releases/download/v${version}/OpenIDEA_${version}_amd64.deb";
    hash = "sha256-/mXowAT7fSGMOdPpVBed562Hs+lOG5G5xuofwsj1TBE=";
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
      # what the IDE downloads / shells out to at runtime (LSP servers, JDKs, git, ssh, ...)
      git
      openssh
      curl
      unzip
      zip
      xdg-utils
      openssl
      zlib
      icu
      stdenv.cc.cc.lib
    ];

  runScript = writeShellScript "openidea-run" ''
    # libsoup needs glib-networking's GIO modules for https
    export GIO_EXTRA_MODULES=/usr/lib/gio/modules
    # GTK file dialogs abort without the gtk3 / desktop gsettings schemas
    export XDG_DATA_DIRS="${gtk3}/share/gsettings-schemas/${gtk3.name}:${gsettings-desktop-schemas}/share/gsettings-schemas/${gsettings-desktop-schemas.name}:/usr/share:''${XDG_DATA_DIRS:-}"
    exec ${unwrapped}/usr/bin/openidea "$@"
  '';

  extraInstallCommands = ''
    mkdir -p $out/share/icons
    cp -r ${unwrapped}/usr/share/icons/hicolor $out/share/icons/

    # absolute Exec: some compositors (kwin) don't resolve a bare Exec via PATH
    mkdir -p $out/share/applications
    cat > $out/share/applications/openidea.desktop <<EOF
    [Desktop Entry]
    Type=Application
    Name=OpenIDEA
    Comment=An open-source IDE inspired by IntelliJ IDEA
    Exec=$out/bin/openidea
    Icon=openidea
    Terminal=false
    Categories=Development;IDE;
    Keywords=IDE;IntelliJ;Java;Kotlin;Rust;
    StartupWMClass=openidea
    EOF
  '';

  passthru = { inherit unwrapped; };

  meta = {
    description = "Open-source IDE inspired by IntelliJ IDEA, rebuilt in Rust";
    homepage = "https://github.com/l0ng-ai/openidea";
    license = lib.licenses.asl20;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "openidea";
  };
}
