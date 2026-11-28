/*
  Mocktail (Android Roblox compatibility runtime) from the official x86_64
  .deb release. Unlike the .deb bundles in this repo (iloader, openidea), its
  binaries link against normal distro libraries rather than carrying their own
  libc/CEF, so autoPatchelfHook works and avoids an FHS env (Mocktail re-execs
  itself and helper binaries). The bundled Bionic/SDL shims in
  lib/x86_64-linux-gnu/mocktail/ are kept as shipped.

  The shipped libvulkan.so asks for Ubuntu 26.04's libplacebo.so.360, while
  nixpkgs has the ABI-compatible 7.387 as libplacebo.so.387; preFixup adds a
  soname symlink in the bundled lib dir so autoPatchelf can resolve it.

  Keep `version`, the GitHub-release `url` and `hash` as plain strings so
  scripts/update.sh can bump them.
*/
{
  lib,
  stdenv,
  fetchurl,
  dpkg,
  autoPatchelfHook,
  sdl3,
  sdl3-ttf,
  libplacebo,
  capstone,
  minizip,
  utf8proc,
  libsecret,
  webkitgtk_6_0,
  libadwaita,
  gtk4,
  libsoup_3,
  curl,
  openssl,
  zlib,
  libyaml,
  libpng,
  libelf,
  fontconfig,
  glib,
}:

let
  pname = "mocktail";
  version = "1.0.5";

  src = fetchurl {
    url = "https://github.com/komaruworld/mocktail/releases/download/${version}/mocktail_${version}_amd64.deb";
    hash = "sha256-PSJ9e5fUt791IRfXrbi6e9l9tHjMOuchW7iyyk5KskQ=";
  };
in
stdenv.mkDerivation {
  inherit pname version src;

  nativeBuildInputs = [ dpkg autoPatchelfHook ];

  buildInputs = [
    sdl3
    sdl3-ttf
    libplacebo
    capstone
    minizip
    utf8proc
    libsecret
    webkitgtk_6_0
    libadwaita
    gtk4
    libsoup_3
    curl
    openssl
    zlib
    libyaml
    libpng
    libelf
    fontconfig
    glib
  ];

  unpackPhase = ''
    runHook preUnpack
    dpkg-deb -x $src .
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp -a usr/. $out/
    runHook postInstall
  '';

  preFixup = ''
    mkdir -p $out/lib/x86_64-linux-gnu/mocktail
    ln -s ${libplacebo}/lib/libplacebo.so.387 \
      $out/lib/x86_64-linux-gnu/mocktail/libplacebo.so.360
    addAutoPatchelfSearchPath "$out/lib/x86_64-linux-gnu/mocktail"
  '';

  meta = {
    description = "Android Roblox compatibility runtime for Linux";
    homepage = "https://github.com/komaruworld/mocktail";
    license = lib.licenses.asl20;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "mocktail";
  };
}
