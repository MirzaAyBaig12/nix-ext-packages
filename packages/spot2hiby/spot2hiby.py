#!/usr/bin/env python3
"""spot2hiby: paste Spotify links, get tagged FLACs on your HiBy.

Metadata and cover art come from Spotify's public pages (no API key needed).
Spotify audio is DRM'd, so the actual audio is matched on YouTube Music and
converted to FLAC. YouTube Music is also the fallback for anything Spotify
doesn't know (album, track number, year, cover), and only for those fields.

Result on the device:  /run/mount/ayaan_mirza/<device>/Music/<Album>/<NN - Title>.flac
"""

from __future__ import annotations

import argparse
import html
import json
import os
import re
import shutil
import sys
import tempfile
import time
import unicodedata
from dataclasses import dataclass, field
from difflib import SequenceMatcher
from pathlib import Path

try:
    import readline  # noqa: F401  (line editing for the URL prompt)
except ImportError:
    pass

import requests
from mutagen.flac import FLAC, Picture
from rich import box
from rich.console import Console, Group
from rich.live import Live
from rich.panel import Panel
from rich.progress import BarColumn, Progress, TaskProgressColumn, TextColumn, TimeElapsedColumn
from rich.spinner import Spinner
from rich.table import Table
from rich.text import Text

__version__ = "0.1.0"

# Catppuccin Mocha, to match the rest of Axiom.
MAUVE, TEXT, SUB, DIM = "#cba6f7", "#cdd6f4", "#a6adc8", "#6c7086"
SURFACE, BASE = "#313244", "#1e1e2e"
GREEN, RED, YELLOW = "#a6e3a1", "#f38ba8", "#f9e2af"

console = Console(highlight=False)


class PipelineError(Exception):
    pass


class SpotifyError(PipelineError):
    pass


# --------------------------------------------------------------------------- #
# small helpers
# --------------------------------------------------------------------------- #

def fmt_bytes(n: float) -> str:
    n = float(n or 0)
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if n < 1024 or unit == "TB":
            return f"{n:.0f} {unit}" if unit == "B" else f"{n:.1f} {unit}"
        n /= 1024
    return f"{n:.1f} TB"


def fmt_time(seconds: float) -> str:
    seconds = int(seconds)
    return f"{seconds // 60}:{seconds % 60:02d}"


_BAD_CHARS = re.compile(r'[<>"|?*\x00-\x1f]')


def safe_name(name: str, fallback: str = "Unknown", maxlen: int = 110) -> str:
    """Make a string safe for FAT32/exFAT file and folder names."""
    name = name.replace("/", "-").replace("\\", "-").replace(":", " -")
    name = _BAD_CHARS.sub("_", name)
    name = re.sub(r"\s+", " ", name).strip()
    name = name[:maxlen].strip(" .")
    return name or fallback


_BRACKETS = re.compile(r"[\(\[].*?[\)\]]")


def norm(s: str) -> str:
    """Normalise a title/artist for fuzzy comparison (keeps non-Latin scripts)."""
    base = unicodedata.normalize("NFKC", s or "").casefold()
    stripped = _BRACKETS.sub(" ", base)
    stripped = re.sub(r"\s-\s.*$", " ", stripped)
    out = re.sub(r"[\W_]+", " ", stripped).strip()
    return out or re.sub(r"[\W_]+", " ", base).strip()


# --------------------------------------------------------------------------- #
# the device
# --------------------------------------------------------------------------- #

@dataclass
class Device:
    name: str
    root: Path
    music_dir: str

    @property
    def path(self) -> Path:
        return self.root / self.name

    @property
    def library(self) -> Path:
        return self.path / self.music_dir

    def present(self) -> bool:
        return self.path.is_dir() and os.access(self.path, os.W_OK | os.X_OK)

    def usage(self):
        try:
            return shutil.disk_usage(self.path)
        except OSError:
            return None


def banner(dev: Device) -> Panel:
    ok = dev.present()
    grid = Table.grid(padding=(0, 2))
    grid.add_column(style=DIM, justify="right")
    grid.add_column()
    grid.add_row(
        "device",
        Text.assemble(("● " if ok else "○ ", GREEN if ok else RED), (dev.name, f"bold {TEXT}")),
    )
    grid.add_row("folder", Text(str(dev.library), style=SUB))
    usage = dev.usage() if ok else None
    if usage:
        width = 22
        filled = round(usage.used / usage.total * width) if usage.total else 0
        bar = Text("▰" * filled, style=MAUVE) + Text("▱" * (width - filled), style=DIM)
        grid.add_row(
            "space",
            Text.assemble(bar, (f"  {fmt_bytes(usage.free)} free of {fmt_bytes(usage.total)}", SUB)),
        )
    title = Text.assemble(("♫ ", MAUVE), ("spot2hiby", f"bold {MAUVE}"), ("  v" + __version__, DIM))
    return Panel(
        Group(Text("Spotify → FLAC → your player", style=SUB), Text(""), grid),
        title=title,
        title_align="left",
        border_style=MAUVE,
        box=box.ROUNDED,
        padding=(1, 2),
    )


def wait_for_device(dev: Device) -> None:
    while not dev.present():
        try:
            mounted = sorted(p.name for p in dev.root.iterdir() if p.is_dir())
        except OSError:
            mounted = []
        body = Text()
        body.append(f"Can't find “{dev.name}”\n", style=f"bold {RED}")
        body.append(f"looked in {dev.path}\n\n", style=SUB)
        if mounted:
            body.append("mounted right now: ", style=DIM)
            body.append(", ".join(mounted), style=TEXT)
        else:
            body.append("nothing is mounted under ", style=DIM)
            body.append(str(dev.root), style=TEXT)
        console.print(Panel(body, border_style=RED, box=box.ROUNDED, padding=(1, 2)))
        if not sys.stdin.isatty():
            raise SystemExit(1)
        try:
            ans = console.input(Text("  mount it, then press enter to retry (q to quit) ", style=SUB))
        except (EOFError, KeyboardInterrupt):
            console.print()
            raise SystemExit(1)
        if ans.strip().lower() in ("q", "quit", "exit"):
            raise SystemExit(1)


# --------------------------------------------------------------------------- #
# Spotify (public pages only)
# --------------------------------------------------------------------------- #

# Deliberately NOT a full browser UA: Spotify serves a bare SPA shell to those, and
# the server-rendered <meta> tags (album, track number, cover) to plain clients.
UA = "Mozilla/5.0"
http = requests.Session()
http.headers.update({"User-Agent": UA, "Accept-Language": "en-US,en;q=0.9"})

SPOTIFY_LINK = re.compile(
    r"open\.spotify\.com/(?:intl-[a-zA-Z-]+/)?(?:embed/)?(track|album|playlist)/([A-Za-z0-9]{22})"
)
SPOTIFY_URI = re.compile(r"spotify:(track|album|playlist):([A-Za-z0-9]{22})")


def parse_spotify(token: str):
    m = SPOTIFY_LINK.search(token) or SPOTIFY_URI.search(token)
    return (m.group(1), m.group(2)) if m else None


def get(url: str) -> requests.Response:
    last: Exception | None = None
    for attempt in range(3):
        try:
            r = http.get(url, timeout=20)
            r.raise_for_status()
            return r
        except requests.RequestException as e:
            last = e
            time.sleep(1 + attempt)
    raise PipelineError(f"network error: {last}")


def meta_tags(page: str) -> list[tuple[str, str]]:
    out = []
    for tag in re.findall(r"<meta\b[^>]*>", page, re.I):
        key = re.search(r'\b(?:name|property)="([^"]+)"', tag)
        val = re.search(r'\bcontent="([^"]*)"', tag)
        if key and val:
            out.append((key.group(1), html.unescape(val.group(1))))
    return out


def embed_entity(kind: str, sid: str) -> dict:
    page = get(f"https://open.spotify.com/embed/{kind}/{sid}").text
    m = re.search(r'<script id="__NEXT_DATA__" type="application/json">(.*?)</script>', page, re.S)
    if not m:
        raise SpotifyError("Spotify embed page had no data (did Spotify change it?)")
    try:
        return json.loads(m.group(1))["props"]["pageProps"]["state"]["data"]["entity"]
    except (KeyError, ValueError) as e:
        raise SpotifyError("couldn't parse Spotify embed data") from e


@dataclass
class Album:
    id: str
    name: str = ""
    artist: str = ""
    date: str = ""
    cover: str = ""
    tracks: list = field(default_factory=list)  # (track_id, disc, number)


_albums: dict[str, Album] = {}


def spotify_album(aid: str) -> Album:
    if aid in _albums:
        return _albums[aid]
    a = Album(aid)
    try:
        ent = embed_entity("album", aid)
        a.name = ent.get("name") or ent.get("title") or ""
        a.artist = ent.get("subtitle") or ""
        for n, item in enumerate(ent.get("trackList") or [], 1):
            m = re.match(r"spotify:track:([A-Za-z0-9]{22})", item.get("uri", ""))
            if m:
                a.tracks.append((m.group(1), 1, n))
    except PipelineError:
        pass
    try:
        tags = meta_tags(get(f"https://open.spotify.com/album/{aid}").text)
        first: dict[str, str] = {}
        for k, v in tags:
            first.setdefault(k, v)
        a.date = first.get("music:release_date", "")
        a.cover = first.get("og:image", "")
        songs: list[list] = []
        for k, v in tags:
            if k == "music:song":
                m = re.search(r"/track/([A-Za-z0-9]{22})", v)
                songs.append([m.group(1) if m else "", 1, len(songs) + 1])
            elif k == "music:song:disc" and songs and v.isdigit():
                songs[-1][1] = int(v)
            elif k == "music:song:track" and songs and v.isdigit():
                songs[-1][2] = int(v)
        if songs:  # the page knows disc numbers, so prefer it over the embed order
            a.tracks = [tuple(s) for s in songs if s[0]]
        if not a.name:
            m = re.match(r"Listen to (.*) - Album by .* \| Spotify", first.get("og:title", ""))
            a.name = m.group(1) if m else ""
    except PipelineError:
        pass
    _albums[aid] = a
    return a


@dataclass
class Track:
    id: str
    title: str = ""
    artists: list = field(default_factory=list)
    album: str = ""
    album_artist: str = ""
    album_id: str = ""
    track_no: int = 0
    track_total: int = 0
    disc_no: int = 0
    disc_total: int = 0
    date: str = ""
    duration_ms: int = 0
    cover_url: str = ""


def spotify_track(sid: str) -> Track:
    t = Track(sid)
    first: dict[str, str] = {}
    for k, v in meta_tags(get(f"https://open.spotify.com/track/{sid}").text):
        first.setdefault(k, v)
    t.title = first.get("og:title", "")
    t.cover_url = first.get("og:image", "")
    t.date = first.get("music:release_date", "")
    if first.get("music:duration", "").isdigit():
        t.duration_ms = int(first["music:duration"]) * 1000
    if first.get("music:album:track", "").isdigit():
        t.track_no = int(first["music:album:track"])
    m = re.search(r"/album/([A-Za-z0-9]{22})", first.get("music:album", ""))
    t.album_id = m.group(1) if m else ""

    try:
        ent = embed_entity("track", sid)
        t.artists = [a["name"] for a in ent.get("artists") or [] if a.get("name")]
        t.title = t.title or ent.get("title") or ent.get("name") or ""
        if not t.duration_ms:
            t.duration_ms = int(ent.get("duration") or 0)
        if not t.date:
            t.date = ((ent.get("releaseDate") or {}).get("isoString") or "")[:10]
    except PipelineError:
        pass
    if not t.artists and first.get("music:musician_description"):
        t.artists = [first["music:musician_description"]]
    if not t.title or not t.artists:
        raise SpotifyError("couldn't read title/artist from Spotify (removed or region-locked?)")

    if t.album_id:
        al = spotify_album(t.album_id)
        t.album, t.album_artist = al.name, al.artist
        for tid, disc, no in al.tracks:
            if tid == sid:
                t.disc_no, t.track_no = disc, no or t.track_no
        if t.disc_no:
            t.track_total = sum(1 for _, d, _ in al.tracks if d == t.disc_no)
            t.disc_total = max(d for _, d, _ in al.tracks)
        t.date = t.date or al.date
        t.cover_url = t.cover_url or al.cover
    return t


def expand(kind: str, sid: str) -> tuple[str, list[str]]:
    """Turn a track/album/playlist link into (label, [track ids])."""
    if kind == "track":
        return "", [sid]
    if kind == "album":
        al = spotify_album(sid)
        return al.name or sid, [tid for tid, _, _ in al.tracks]
    ent = embed_entity("playlist", sid)
    ids = []
    for item in ent.get("trackList") or []:
        m = re.match(r"spotify:track:([A-Za-z0-9]{22})", item.get("uri", ""))
        if m:
            ids.append(m.group(1))
    return ent.get("name") or ent.get("title") or sid, ids


# --------------------------------------------------------------------------- #
# YouTube Music: audio source + fallback metadata
# --------------------------------------------------------------------------- #

JUNK_WORDS = (
    "karaoke", "instrumental", "cover", "remix", "live", "sped up", "slowed",
    "reverb", "nightcore", "8d", "tribute", "lullaby", "piano version",
)
MIN_SCORE = 4.5


def score_hit(t: Track, hit: dict) -> float:
    cand_title = hit.get("title", "")
    score = SequenceMatcher(None, norm(t.title), norm(cand_title)).ratio() * 4

    names = [norm(a.get("name", "")) for a in hit.get("artists") or []]
    blob = " ".join(names) + " " + norm(cand_title)
    wanted = [norm(a) for a in t.artists]
    score += 2.5 if any(w and (w in names or w in blob) for w in wanted) else -2

    dur = hit.get("duration_seconds")
    if dur and t.duration_ms:
        d = abs(dur - t.duration_ms / 1000)
        score += 3 if d <= 2 else 2 if d <= 5 else 0.5 if d <= 10 else -1.5 if d <= 30 else -3

    album = (hit.get("album") or {}).get("name")
    if album and t.album and norm(album) == norm(t.album):
        score += 1
    if hit.get("resultType") == "song":
        score += 0.5

    a, b = t.title.casefold(), cand_title.casefold()
    for w in JUNK_WORDS:
        pat = rf"\b{re.escape(w)}\b"
        if re.search(pat, b) and not re.search(pat, a):
            score -= 3
    return score


def find_match(yt, t: Track):
    query = f"{t.artists[0]} {t.title}"
    best, best_score = None, -99.0
    for flt in ("songs", "videos"):
        try:
            results = yt.search(query, filter=flt, limit=10)
        except Exception as e:  # ytmusicapi raises a zoo of exceptions
            raise PipelineError(f"YT Music search failed: {e}") from e
        for hit in results:
            if hit.get("videoId"):
                s = score_hit(t, hit)
                if s > best_score:
                    best, best_score = hit, s
        if best and best_score >= MIN_SCORE:
            break
    return best if best and best_score >= MIN_SCORE else None


def upscale_thumb(url: str) -> str:
    return re.sub(r"=w\d+-h\d+.*$", "=w640-h640-l90-rj", url)


def fill_gaps(yt, t: Track, hit: dict) -> list[str]:
    """Fill ONLY what Spotify didn't give us. Returns what came from YT Music."""
    used: list[str] = []
    alb = hit.get("album") or {}
    if not t.album and alb.get("name"):
        t.album = alb["name"]
        used.append("album")

    need_no = not t.track_no or not t.track_total
    detail = None
    if alb.get("id") and (need_no or not t.date):
        try:
            detail = yt.get_album(alb["id"])
        except Exception:
            detail = None
    if detail:
        tracks = detail.get("tracks") or []
        if need_no and tracks:
            idx = next((i for i, x in enumerate(tracks) if x.get("videoId") == hit["videoId"]), None)
            if idx is None:
                want = norm(t.title)
                idx = next((i for i, x in enumerate(tracks) if norm(x.get("title", "")) == want), None)
            if idx is not None:
                if not t.track_no:
                    t.track_no = idx + 1
                    used.append("track #")
                if not t.track_total:
                    t.track_total = len(tracks)
        if not t.date and detail.get("year"):
            t.date = str(detail["year"])
            used.append("year")
    if not t.date and hit.get("year"):
        t.date = str(hit["year"])
        used.append("year")
    if not t.cover_url and hit.get("thumbnails"):
        t.cover_url = upscale_thumb(hit["thumbnails"][-1]["url"])
        used.append("cover")
    if not t.album_artist:
        t.album_artist = t.artists[0]
    return used


def js_runtimes() -> dict:
    """yt-dlp needs a JS runtime to solve YouTube's challenges."""
    for name in ("deno", "node", "bun"):
        if shutil.which(name):
            return {name: {}}
    return {}


def clean_error(e: Exception) -> str:
    return re.sub(r"\x1b\[[0-9;]*m", "", str(e)).replace("ERROR: ", "").strip()


def download_flac(video_id: str, workdir: Path, job: "Job") -> Path:
    import yt_dlp

    def on_progress(d):
        if d["status"] == "downloading":
            job.dl = (
                d.get("downloaded_bytes") or 0,
                d.get("total_bytes") or d.get("total_bytes_estimate") or 0,
                d.get("speed") or 0,
            )
        elif d["status"] == "finished":
            job.set("dl", "done", f"{fmt_bytes(job.dl[1] or job.dl[0])} from YT Music")
            job.set("flac", "active", "ffmpeg → FLAC")

    opts = {
        "format": "bestaudio/best",
        "outtmpl": str(workdir / "audio.%(ext)s"),
        "quiet": True,
        "no_warnings": True,
        "noprogress": True,
        "noplaylist": True,
        "retries": 5,
        "fragment_retries": 5,
        "progress_hooks": [on_progress],
        "postprocessors": [{"key": "FFmpegExtractAudio", "preferredcodec": "flac"}],
        "js_runtimes": js_runtimes(),
    }
    try:
        with yt_dlp.YoutubeDL(opts) as ydl:
            ydl.download([f"https://music.youtube.com/watch?v={video_id}"])
    except yt_dlp.utils.DownloadError as e:
        raise PipelineError(f"download failed: {clean_error(e)}") from e
    out = workdir / "audio.flac"
    if not out.exists():
        raise PipelineError("ffmpeg didn't produce a FLAC (is ffmpeg working?)")
    return out


def fetch_cover(url: str) -> bytes:
    data = get(url).content
    if not (data.startswith(b"\xff\xd8") or data.startswith(b"\x89PNG")):
        raise PipelineError("cover wasn't a JPEG/PNG")
    return data


def tag_flac(path: Path, t: Track, cover: bytes | None) -> None:
    f = FLAC(path)
    f.clear()
    f.clear_pictures()
    f["TITLE"] = t.title
    f["ARTIST"] = ", ".join(t.artists)
    f["ALBUMARTIST"] = t.album_artist or t.artists[0]
    if t.album:
        f["ALBUM"] = t.album
    if t.track_no:
        f["TRACKNUMBER"] = str(t.track_no)
    if t.track_total:
        f["TRACKTOTAL"] = str(t.track_total)
        f["TOTALTRACKS"] = str(t.track_total)
    if t.disc_no:
        f["DISCNUMBER"] = str(t.disc_no)
    if t.disc_total:
        f["DISCTOTAL"] = str(t.disc_total)
    if t.date:
        f["DATE"] = t.date
    f["COMMENT"] = f"https://open.spotify.com/track/{t.id}"
    if cover:
        pic = Picture()
        pic.type = 3  # front cover
        pic.mime = "image/png" if cover.startswith(b"\x89PNG") else "image/jpeg"
        pic.desc = "Cover"
        pic.data = cover
        f.add_picture(pic)
    f.save()


def target_path(dev: Device, t: Track) -> Path:
    album = safe_name(t.album, "Unknown Album")
    title = safe_name(t.title, "Track")
    if t.track_no:
        prefix = f"{t.disc_no}-{t.track_no:02d}" if t.disc_total > 1 else f"{t.track_no:02d}"
        name = f"{prefix} - {title}.flac"
    else:
        name = f"{title}.flac"
    return dev.library / album / name


# --------------------------------------------------------------------------- #
# pipeline + TUI
# --------------------------------------------------------------------------- #

STEPS = [
    ("meta", "Spotify metadata"),
    ("match", "YT Music match"),
    ("dl", "Download audio"),
    ("flac", "Convert to FLAC"),
    ("tag", "Tag + cover art"),
    ("copy", "Copy to device"),
]


class Job:
    def __init__(self, idx: int, total: int, sid: str):
        self.idx, self.total, self.sid = idx, total, sid
        self.title = f"spotify:track:{sid}"
        self.steps = {k: ("pending", "") for k, _ in STEPS}
        self.dl = (0, 0, 0.0)

    def set(self, key: str, status: str, detail="") -> None:
        self.steps[key] = (status, detail)


@dataclass
class Result:
    status: str  # ok | skip | fail
    label: str
    folder: str = ""
    note: str = ""
    size: int = 0


def process_track(job: Job, dev: Device, yt, workdir: Path) -> Result:
    # 1. Spotify metadata -------------------------------------------------
    job.set("meta", "active")
    t = spotify_track(job.sid)
    job.title = f"{', '.join(t.artists)} — {t.title}"
    year = f" ({t.date[:4]})" if t.date else ""
    meta_detail = f"{t.album or 'no album listed'}{year}"
    job.set("meta", "done", meta_detail)

    def already_there() -> Path | None:
        if t.album and t.track_no:
            p = target_path(dev, t)
            return p if p.exists() else None
        return None

    def skipped(p: Path) -> Result:
        for k in ("match", "dl", "flac", "tag", "copy"):
            job.set(k, "skip")
        return Result("skip", job.title, p.parent.name, "already on device")

    if (p := already_there()) is not None:
        return skipped(p)

    # 2. YT Music match + gap filling ---------------------------------------
    job.set("match", "active")
    hit = find_match(yt, t)
    if not hit:
        raise PipelineError("no confident match on YT Music")
    artists = ", ".join(a["name"] for a in hit.get("artists") or [] if a.get("name"))
    dur = f" · {fmt_time(hit['duration_seconds'])}" if hit.get("duration_seconds") else ""
    job.set("match", "done", f"{hit.get('title', '')} — {artists}{dur}")

    used = fill_gaps(yt, t, hit)
    if used:
        job.set(
            "meta", "done",
            Text.assemble((meta_detail, SUB), ("   ↳ from YT Music: " + ", ".join(used), YELLOW)),
        )
    if (p := already_there()) is not None:
        return skipped(p)

    # 3+4. download + FLAC ---------------------------------------------------
    job.set("dl", "active")
    audio = download_flac(hit["videoId"], workdir, job)
    job.set("flac", "done", fmt_bytes(audio.stat().st_size))

    # 5. tag + cover -----------------------------------------------------------
    job.set("tag", "active")
    cover, cover_note = None, ""
    if t.cover_url:
        try:
            cover = fetch_cover(t.cover_url)
        except PipelineError:
            cover = None
    if cover is None and hit.get("thumbnails"):
        try:
            cover = fetch_cover(upscale_thumb(hit["thumbnails"][-1]["url"]))
            cover_note = "   ↳ cover from YT Music"
        except PipelineError:
            cover = None
    tag_flac(audio, t, cover)
    job.set(
        "tag", "done",
        Text.assemble(
            (f"cover {fmt_bytes(len(cover))}" if cover else "no cover found", SUB),
            (cover_note, YELLOW),
        ),
    )

    # 6. copy ------------------------------------------------------------------
    job.set("copy", "active")
    dest = target_path(dev, t)
    size = audio.stat().st_size
    if not dev.present():
        raise PipelineError("device went away")
    usage = dev.usage()
    if usage and usage.free < size + 5 * 1024 * 1024:
        raise PipelineError("not enough space on the device")
    dest.parent.mkdir(parents=True, exist_ok=True)
    part = dest.with_name("." + dest.name + ".part")
    try:
        shutil.copyfile(audio, part)
        os.replace(part, dest)
    except OSError as e:
        part.unlink(missing_ok=True)
        keep = Path.home() / ".cache" / "spot2hiby" / "pending"
        keep.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(audio, keep / dest.name)
        raise PipelineError(f"copy failed ({e.strerror}); kept at {keep / dest.name}") from e
    job.set("copy", "done", f"{dest.parent.name}/{dest.name}")
    note = "from YT Music: " + ", ".join(used) if used else ""
    return Result("ok", job.title, dest.parent.name, note, size)


class Screen:
    def __init__(self, dev: Device, total: int):
        self.dev = dev
        self.job: Job | None = None
        self.results: list[Result] = []
        self.progress = Progress(
            TextColumn("[bold]overall[/]"),
            BarColumn(bar_width=None, style=SURFACE, complete_style=MAUVE, finished_style=GREEN),
            TaskProgressColumn(),
            TextColumn("{task.completed}/{task.total}"),
            TimeElapsedColumn(),
            console=console,
            expand=True,
        )
        self.task = self.progress.add_task("", total=total)
        self.spinners = {k: Spinner("dots", style=MAUVE) for k, _ in STEPS}

    def dl_bar(self, job: Job) -> Text:
        done, total, speed = job.dl
        width = 26
        frac = min(done / total, 1) if total else 0
        filled = int(frac * width)
        bar = Text("━" * filled, style=MAUVE) + Text("━" * (width - filled), style=SURFACE)
        info = f"  {frac * 100:3.0f}%  {fmt_bytes(done)} / {fmt_bytes(total)}"
        if speed:
            info += f"  {fmt_bytes(speed)}/s"
        if not total:
            info = f"  {fmt_bytes(done)}"
        return bar + Text(info, style=SUB)

    def job_panel(self) -> Panel:
        job = self.job
        grid = Table.grid(padding=(0, 1))
        grid.add_column(width=2)
        grid.add_column(min_width=17)
        grid.add_column(ratio=1, no_wrap=True, overflow="ellipsis")
        for key, label in STEPS:
            status, detail = job.steps[key]
            if status == "done":
                icon = Text("✓", style=GREEN)
            elif status == "active":
                icon = self.spinners[key]
            elif status == "fail":
                icon = Text("✗", style=RED)
            elif status == "skip":
                icon = Text("↷", style=YELLOW)
            else:
                icon = Text("○", style=DIM)
            lab = Text(label, style=TEXT if status in ("done", "active") else DIM)
            if key == "dl" and status == "active":
                det = self.dl_bar(job)
            elif isinstance(detail, Text):
                det = detail
            else:
                det = Text(detail, style=RED if status == "fail" else SUB)
            grid.add_row(icon, lab, det)
        title = Text.assemble(
            (f" {job.idx}/{job.total} ", f"bold {BASE} on {MAUVE}"),
            ("  ♪ ", MAUVE),
            (job.title, f"bold {TEXT}"),
        )
        return Panel(grid, title=title, title_align="left", border_style=MAUVE, box=box.ROUNDED, padding=(1, 2))

    def recent(self):
        if not self.results:
            return Text("")
        table = Table(box=box.SIMPLE_HEAD, border_style=SURFACE, header_style=DIM, expand=True, pad_edge=False)
        table.add_column("", width=2)
        table.add_column("track", ratio=3, no_wrap=True, overflow="ellipsis")
        table.add_column("album folder", ratio=2, no_wrap=True, overflow="ellipsis")
        table.add_column("note", ratio=2, no_wrap=True, overflow="ellipsis")
        for r in self.results[-6:]:
            icon, style = {"ok": ("✓", GREEN), "skip": ("↷", YELLOW), "fail": ("✗", RED)}[r.status]
            table.add_row(
                Text(icon, style=style),
                Text(r.label, style=TEXT if r.status != "skip" else DIM),
                Text(r.folder, style=SUB),
                Text(r.note, style=RED if r.status == "fail" else DIM),
            )
        return table

    def __call__(self):
        parts = [banner(self.dev), self.progress]
        if self.job:
            parts.append(self.job_panel())
        parts.append(self.recent())
        return Group(*parts)


def summary(results: list[Result], elapsed: float, interrupted: bool) -> Panel:
    ok = [r for r in results if r.status == "ok"]
    skipped = [r for r in results if r.status == "skip"]
    failed = [r for r in results if r.status == "fail"]
    line = Text()
    line.append(f"✓ {len(ok)} copied", style=f"bold {GREEN}")
    if skipped:
        line.append(f"   ↷ {len(skipped)} already there", style=YELLOW)
    if failed:
        line.append(f"   ✗ {len(failed)} failed", style=f"bold {RED}")
    line.append(f"   · {fmt_bytes(sum(r.size for r in ok))} in {fmt_time(elapsed)}", style=DIM)
    body: list = [line]
    if interrupted:
        body.append(Text("stopped early (ctrl-c)", style=YELLOW))
    if failed:
        body.append(Text(""))
        for r in failed:
            body.append(Text.assemble(("✗ ", RED), (r.label, TEXT), ("\n   " + r.note, DIM)))
    if ok:
        body.append(Text(""))
        body.append(
            Text(
                "Writes are flushed. If new songs don't show on the R1, run a Library Rescan in Music Settings.",
                style=DIM,
            )
        )
    colour = RED if failed and not ok else YELLOW if failed or interrupted else GREEN
    return Panel(
        Group(*body),
        title=Text(" done ", style=f"bold {BASE} on {colour}"),
        title_align="left",
        border_style=colour,
        box=box.ROUNDED,
        padding=(1, 2),
    )


def collect_urls() -> list[tuple[str, str]]:
    console.print(
        Text.assemble(
            ("\n  Paste Spotify links", f"bold {TEXT}"),
            (" (track, album or playlist), one per line.\n  Type ", SUB),
            ("done", f"bold {MAUVE}"),
            (" when you're finished.\n", SUB),
        )
    )
    items: list[tuple[str, str]] = []
    seen: set[tuple[str, str]] = set()
    prompt = Text("  ❯ ", style=f"bold {MAUVE}")
    while True:
        try:
            line = console.input(prompt)
        except EOFError:
            return items
        except KeyboardInterrupt:
            console.print()
            raise SystemExit(130)
        for token in line.split():
            low = token.lower()
            if low in ("done", "go"):
                return items
            if low in ("q", "quit", "exit"):
                raise SystemExit(0)
            parsed = parse_spotify(token)
            if not parsed:
                console.print(Text(f"  ✗ not a Spotify track/album/playlist link: {token[:60]}", style=RED))
            elif parsed in seen:
                console.print(Text("  ↷ already added", style=YELLOW))
            else:
                seen.add(parsed)
                items.append(parsed)
                console.print(
                    Text.assemble(
                        ("  ✓ ", GREEN),
                        (parsed[0].ljust(9), TEXT),
                        (parsed[1], DIM),
                        (f"   {len(items)} queued", DIM),
                    )
                )


def expand_all(items: list[tuple[str, str]]) -> list[str]:
    ids: list[str] = []
    for kind, sid in items:
        with console.status(Text(f"reading {kind} {sid}…", style=SUB), spinner="dots", spinner_style=MAUVE):
            try:
                label, found = expand(kind, sid)
            except PipelineError as e:
                console.print(Text(f"  ✗ {kind} {sid}: {e}", style=RED))
                continue
        if not found:
            console.print(Text(f"  ✗ {kind} {sid}: no tracks found", style=RED))
            continue
        if kind != "track":
            console.print(Text.assemble(("  ✓ ", GREEN), (f"{kind} “{label}”", TEXT), (f"  {len(found)} tracks", DIM)))
        ids.extend(found)
    return list(dict.fromkeys(ids))


def run_queue(dev: Device, ids: list[str]) -> None:
    from ytmusicapi import YTMusic

    yt = YTMusic()
    screen = Screen(dev, len(ids))
    started = time.time()
    interrupted = False
    with Live(get_renderable=screen, console=console, refresh_per_second=12, transient=True):
        try:
            for i, sid in enumerate(ids, 1):
                job = Job(i, len(ids), sid)
                screen.job = job
                with tempfile.TemporaryDirectory(prefix="spot2hiby-") as tmp:
                    try:
                        res = process_track(job, dev, yt, Path(tmp))
                    except PipelineError as e:
                        res = Result("fail", job.title, "", str(e))
                    except Exception as e:  # keep the queue going no matter what
                        res = Result("fail", job.title, "", f"{type(e).__name__}: {e}")
                if res.status == "fail":
                    for key, (status, _) in job.steps.items():
                        if status == "active":
                            job.set(key, "fail", res.note)
                screen.results.append(res)
                screen.progress.advance(screen.task)
                if not console.is_terminal:
                    mark = {"ok": "ok  ", "skip": "skip", "fail": "FAIL"}[res.status]
                    console.print(f"[{i}/{len(ids)}] {mark} {res.label} {res.folder} {res.note}", highlight=False)
        except KeyboardInterrupt:
            interrupted = True
    with console.status(Text("flushing writes to the device…", style=SUB), spinner="dots", spinner_style=MAUVE):
        os.sync()
    console.print(summary(screen.results, time.time() - started, interrupted))
    if any(r.status == "fail" for r in screen.results):
        raise SystemExit(1)


def main() -> None:
    p = argparse.ArgumentParser(
        prog="spotify-downloader",
        description="Spotify links in, tagged FLACs in /run/mount/ayaan_mirza/<device>/Music/<Album>/ out.",
    )
    p.add_argument("urls", nargs="*", help="Spotify links (skips the interactive prompt)")
    p.add_argument(
        "-d", "--device",
        default=os.environ.get("SPOT2HIBY_DEVICE", "HiBy R1 SD"),
        help="mounted device name (default: %(default)s, or $SPOT2HIBY_DEVICE)",
    )
    p.add_argument(
        "--mount-root",
        default=os.environ.get("SPOT2HIBY_MOUNT_ROOT") or "/run/mount/ayaan_mirza",
        help="where removable media is mounted (default: %(default)s)",
    )
    p.add_argument(
        "--music-dir",
        default=os.environ.get("SPOT2HIBY_MUSIC_DIR", "Music"),
        help="folder on the device that holds the albums (default: %(default)s)",
    )
    p.add_argument("--version", action="version", version=f"spotify-downloader {__version__}")
    args = p.parse_args()

    if not shutil.which("ffmpeg"):
        console.print(Text("ffmpeg not found in PATH", style=RED))
        raise SystemExit(1)

    dev = Device(args.device, Path(args.mount_root), args.music_dir)
    console.print(banner(dev))
    wait_for_device(dev)

    items = [pr for tok in args.urls if (pr := parse_spotify(tok))] if args.urls else collect_urls()
    if not items:
        console.print(Text("  nothing queued, bye.", style=DIM))
        return
    console.print()
    ids = expand_all(items)
    if not ids:
        console.print(Text("  no tracks to fetch.", style=RED))
        raise SystemExit(1)
    console.print(Text(f"\n  fetching {len(ids)} track{'s' if len(ids) != 1 else ''}…\n", style=SUB))
    run_queue(dev, ids)


if __name__ == "__main__":
    main()
