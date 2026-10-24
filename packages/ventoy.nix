/*
  Ventoy (CLI + web UI + GTK3 GUI) from the upstream release tarball.

  Why this isn't just nixpkgs' `ventoy-full-gtk`: autoPatchelfHook/patchelf corrupts
  the prebuilt tool/x86_64/Ventoy2Disk.gtk3 (it ends up with overlapping LOAD
  segments and ld.so segfaults before main()). So that one binary is left
  untouched and started through the glibc loader with an explicit library path
  instead. Everything else (V2DServer, VentoyGUI launcher, ...) is patched normally.

  Binaries: ventoy, ventoy-web, ventoy-gui (+ ventoy-persistent,
  ventoy-extend-persistent, ventoy-plugson).

  For scripts/update.sh to auto-bump it, keep `version`, the GitHub-release
  `url` and `hash` as plain strings.
*/
{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  copyDesktopItems,
  makeDesktopItem,
  runtimeShell,
  # runtime tools for the scripts (PATH of every wrapper)
  bash,
  coreutils,
  cryptsetup,
  dosfstools,
  e2fsprogs,
  exfat,
  gawk,
  gnugrep,
  gnused,
  hexdump,
  ntfs3g,
  parted,
  procps,
  util-linux,
  which,
  xfsprogs,
  xz,
  # libs for the GTK3 GUI binary
  gtk3,
  glib,
  pango,
  cairo,
  gdk-pixbuf,
  at-spi2-core,
}:

let
  pname = "ventoy";
  version = "1.1.18";

  src = fetchurl {
    url = "https://github.com/ventoy/Ventoy/releases/download/v${version}/ventoy-${version}-linux.tar.gz";
    hash = "sha256-2G/53mPZTIuPH2sU0jxVr0uI6CB78ok4kIkqapexrVQ=";
  };

  runtimeTools = [
    bash
    coreutils
    cryptsetup
    dosfstools
    e2fsprogs
    exfat
    gawk
    gnugrep
    gnused
    hexdump
    ntfs3g
    parted
    procps
    util-linux
    which
    xfsprogs
    xz
  ];

  guiLibs = [
    gtk3
    glib
    pango
    cairo
    gdk-pixbuf
    at-spi2-core
  ];
in
stdenv.mkDerivation {
  inherit pname version src;

  patches = [ ../patches/ventoy-nixos-sanitization.patch ];

  postPatch = ''
    # Fix permissions.
    find -type f -name \*.sh -exec chmod a+x '{}' \;

    # Fix path to log.
    sed -i 's:log\.txt:/var/log/ventoy\.log:g' \
        WebUI/static/js/languages.js tool/languages.json
  '';

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
    copyDesktopItems
  ];

  buildInputs = runtimeTools;

  strictDeps = true;

  # Patched by hand in postFixup: Ventoy2Disk.gtk3 must NOT go through patchelf.
  dontAutoPatchelf = true;

  desktopItems = [
    (makeDesktopItem {
      name = "Ventoy";
      desktopName = "Ventoy";
      comment = "Tool to create bootable USB drive for ISO/WIM/IMG/VHD(x)/EFI files";
      icon = "VentoyLogo";
      # absolute path: some launchers/compositors don't resolve bare Exec via PATH
      exec = "${placeholder "out"}/bin/ventoy-gui";
      terminal = false;
      categories = [ "Utility" ];
      startupNotify = true;
    })
  ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    local VENTOY_PATH="$out"/share/ventoy

    # Prepare: unpack the xz-compressed helper tools (the nixos patch removes the
    # runtime decompression step from Ventoy2Disk.sh).
    cd tool/x86_64
    rm ash* hexdump* mkexfatfs* mount.exfat-fuse* xzcat*
    for archive in *.xz; do
        xzcat "$archive" > "''${archive%.xz}"
        rm "$archive"
    done
    chmod a+x *
    cd -

    # Cleanup: x86_64 + gtk3 only.
    rm -r {tool/,VentoyGUI.}{i386,aarch64,mips64el}
    rm README
    rm tool/x86_64/Ventoy2Disk.gtk2 tool/x86_64/Ventoy2Disk.qt5

    mkdir -p "$out"/bin "$VENTOY_PATH"
    cp -r . "$VENTOY_PATH"

    # Keep the pristine GUI binary and put a loader-launching wrapper in its place.
    mv "$VENTOY_PATH"/tool/x86_64/Ventoy2Disk.gtk3 "$VENTOY_PATH"/tool/x86_64/Ventoy2Disk.gtk3.real
    cat > "$VENTOY_PATH"/tool/x86_64/Ventoy2Disk.gtk3 <<EOF
    #!${runtimeShell}
    exec ${stdenv.cc.bintools.dynamicLinker} --library-path ${lib.makeLibraryPath guiLibs} "$VENTOY_PATH/tool/x86_64/Ventoy2Disk.gtk3.real" "\$@"
    EOF
    chmod a+x "$VENTOY_PATH"/tool/x86_64/Ventoy2Disk.gtk3

    # VentoyGUI uses the `ventoy_gui_type` file to pick the GUI binary.
    echo gtk3 > "$VENTOY_PATH/ventoy_gui_type"

    for f in Ventoy2Disk.sh_ventoy VentoyWeb.sh_ventoy-web \
             CreatePersistentImg.sh_ventoy-persistent \
             ExtendPersistentImg.sh_ventoy-extend-persistent \
             VentoyPlugson.sh_ventoy-plugson VentoyGUI.x86_64_ventoy-gui; do
        local bin="''${f%_*}" wrapper="''${f##*_}"
        makeWrapper "$VENTOY_PATH/$bin" "$out/bin/$wrapper" \
                    --prefix PATH : "${lib.makeBinPath runtimeTools}" \
                    --chdir "$VENTOY_PATH"
    done

    mkdir -p "$out"/share/pixmaps
    ln -s "$VENTOY_PATH"/WebUI/static/img/VentoyLogo.png "$out"/share/pixmaps/

    runHook postInstall
  '';

  postFixup = ''
    # Everything except the GUI binary gets the normal autoPatchelf treatment.
    autoPatchelf -- \
      "$out/share/ventoy/VentoyGUI.x86_64" \
      "$out/share/ventoy/tool/x86_64/V2DServer" \
      "$out/share/ventoy/tool/x86_64/Plugson" \
      "$out/share/ventoy/tool/x86_64/vlnk" \
      "$out/share/ventoy/tool/x86_64/vtoycli" \
      "$out/share/ventoy/tool/x86_64/vtoygpt"
  '';

  meta = {
    description = "Tool to create bootable USB drives for ISO/WIM/IMG/VHD(x)/EFI files (CLI, web UI and GTK3 GUI)";
    homepage = "https://www.ventoy.net";
    changelog = "https://www.ventoy.net/doc_news.html";
    license = lib.licenses.gpl3Only;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "ventoy";
  };
}
