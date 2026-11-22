{
  lib,
  stdenvNoCC,
  python3,
  ffmpeg,
  nodejs,
  makeWrapper,
  # Name of the music device as it appears once mounted, i.e. the folder
  # /run/mount/ayaan_mirza/<musicDevice>. The programs.spotify-downloader
  # module sets this from its `musicDevice` option. Per run you can also use
  # `spotify-downloader --device NAME` or $SPOT2HIBY_DEVICE.
  musicDevice ? "HiBy R1 SD",
  # Where removable media gets mounted on this machine.
  mountRoot ? "/run/mount/ayaan_mirza",
  # Folder on the device the album folders go into.
  musicDir ? "Music",
}:

# spot2hiby: paste Spotify links, get tagged FLACs in <device>/Music/<Album>/.
# Pure script package, nothing is fetched at build time (so update.sh skips it).
#   - Spotify metadata + cover: scraped from Spotify's public pages (no API key)
#   - audio: matched on YouTube Music, downloaded with yt-dlp, converted by ffmpeg
#   - YT Music also fills fields Spotify doesn't know, and only those
let
  pythonEnv = python3.withPackages (ps: [
    ps.mutagen
    ps.requests
    ps.rich
    ps.yt-dlp
    ps.ytmusicapi
  ]);
in
stdenvNoCC.mkDerivation {
  pname = "spot2hiby";
  version = "0.1.0";

  src = ./spot2hiby;

  dontBuild = true;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    install -Dm644 spot2hiby.py $out/share/spot2hiby/spot2hiby.py

    # nodejs is yt-dlp's JS runtime for YouTube's challenges.
    makeWrapper ${pythonEnv}/bin/python3 $out/bin/spotify-downloader \
      --add-flags $out/share/spot2hiby/spot2hiby.py \
      --prefix PATH : ${lib.makeBinPath [ ffmpeg nodejs ]} \
      --set-default SPOT2HIBY_DEVICE ${lib.escapeShellArg musicDevice} \
      --set-default SPOT2HIBY_MUSIC_DIR ${lib.escapeShellArg musicDir} \
      --set-default SPOT2HIBY_MOUNT_ROOT ${lib.escapeShellArg mountRoot}

    # Short alias, kept from the original spot2hiby name.
    ln -s spotify-downloader $out/bin/spot2hiby

    runHook postInstall
  '';

  meta = {
    description = "Spotify links in, tagged FLACs with cover art on your HiBy out (terminal UI)";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "spotify-downloader";
  };
}
