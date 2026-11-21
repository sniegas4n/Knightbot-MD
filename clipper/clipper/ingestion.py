"""Étape 1 : lister les vidéos d'une URL et les télécharger en meilleure qualité, une seule fois."""

from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any

import yt_dlp

from clipper.config import Config
from clipper.journal import journal

log = journal("ingestion")

# Extensions de fichiers annexes qui ne sont pas la vidéo elle-même.
_ANNEXES = {".json", ".part", ".ytdl", ".webp", ".jpg", ".png", ".vtt", ".srt", ".ogg"}


class ErreurIngestion(Exception):
    pass


class _JournalYtDlp:
    """Redirige les messages de yt-dlp vers notre journal (en détail seulement)."""

    def debug(self, msg: str) -> None:
        log.debug(msg)

    def info(self, msg: str) -> None:
        log.debug(msg)

    def warning(self, msg: str) -> None:
        log.debug("yt-dlp : %s", msg)

    def error(self, msg: str) -> None:
        log.debug("yt-dlp : %s", msg)  # l'erreur remonte en exception, journalisée une seule fois


def _options_base(cfg: Config) -> dict[str, Any]:
    opts: dict[str, Any] = {
        "quiet": True,
        "no_warnings": True,
        "noprogress": True,
        "logger": _JournalYtDlp(),
        "js_runtimes": {nom: {} for nom in cfg.get("ingestion.js_runtimes", ["deno"])},
    }
    # Cookies YouTube, si YouTube demande de « confirmer que vous n'êtes pas un robot ».
    navigateur = cfg.get("ingestion.cookies_navigateur")
    fichier = cfg.get("ingestion.fichier_cookies")
    if navigateur:
        opts["cookiesfrombrowser"] = (navigateur,)
    elif fichier:
        opts["cookiefile"] = str(cfg.racine / fichier)
    return opts


def url_video(video_id: str) -> str:
    return f"https://www.youtube.com/watch?v={video_id}"


# URL d'une vidéo seule (watch, youtu.be, shorts, live, embed), sans paramètre de playlist.
_URL_VIDEO = re.compile(
    r"^(?:https?://)?(?:www\.|m\.)?(?:youtube\.com/(?:watch\?(?:.*&)?v=|shorts/|live/|embed/)|youtu\.be/)"
    r"([A-Za-z0-9_-]{11})(?:[?&#].*)?$"
)


def id_video_direct(url: str) -> str | None:
    """Identifiant d'une URL de vidéo seule, ou None (playlist, chaîne, autre)."""
    m = _URL_VIDEO.match(url.strip())
    if not m or "list=" in url:
        return None
    return m.group(1)


def lister_videos(url: str, cfg: Config) -> list[dict[str, str]]:
    """Retourne les vidéos d'une URL (vidéo seule, playlist ou chaîne), sans rien télécharger."""
    direct = id_video_direct(url)
    if direct:
        return [{"id": direct, "titre": ""}]  # pas besoin du réseau : le titre arrive au téléchargement
    limite = int(cfg.get("ingestion.limite_playlist", 0) or 0)
    opts = {**_options_base(cfg), "extract_flat": "in_playlist", "skip_download": True}
    trouvees: dict[str, dict[str, str]] = {}

    def parcourir(u: str, profondeur: int) -> None:
        with yt_dlp.YoutubeDL(opts) as ydl:
            info = ydl.extract_info(u, download=False)
        _collecter(info, profondeur)

    def _collecter(info: dict[str, Any], profondeur: int) -> None:
        if limite and len(trouvees) >= limite:
            return
        entrees = info.get("entries")
        if entrees is None:
            # Une vidéo seule.
            if info.get("id"):
                trouvees.setdefault(info["id"], {"id": info["id"], "titre": info.get("title") or ""})
            return
        for e in entrees:
            if not e or (limite and len(trouvees) >= limite):
                continue
            # Une chaîne contient des onglets (Vidéos, Lives...) qui sont eux-mêmes des playlists.
            est_playlist = e.get("_type") == "playlist" or e.get("ie_key") == "YoutubeTab"
            if est_playlist and profondeur < 2:
                if e.get("entries") is not None:
                    _collecter(e, profondeur + 1)
                elif e.get("url"):
                    parcourir(e["url"], profondeur + 1)
                continue
            if e.get("id") and e.get("ie_key", "Youtube") == "Youtube":
                trouvees.setdefault(e["id"], {"id": e["id"], "titre": e.get("title") or ""})

    try:
        parcourir(url, 0)
    except yt_dlp.utils.DownloadError as exc:
        raise ErreurIngestion(f"Impossible de lire {url} : {exc}") from exc
    return list(trouvees.values())


def fichier_existant(video_id: str, dossier: Path) -> Path | None:
    """Cherche une vidéo déjà téléchargée (fichier final, pas un .part)."""
    for p in sorted(dossier.glob(f"{video_id}.*")):
        if p.suffix.lower() not in _ANNEXES and p.stat().st_size > 0:
            return p
    return None


def telecharger(video_id: str, cfg: Config) -> tuple[Path, dict[str, Any]]:
    """Télécharge la vidéo (si pas déjà fait) et retourne son chemin et ses métadonnées."""
    dossier = cfg.sous_dossier("videos")
    chemin_info = dossier / f"{video_id}.info.json"
    existant = fichier_existant(video_id, dossier)
    if existant and chemin_info.exists():
        log.info("Vidéo %s déjà téléchargée, rien à faire.", video_id)
        return existant, json.loads(chemin_info.read_text(encoding="utf-8"))

    opts = {
        **_options_base(cfg),
        "format": cfg.get("ingestion.format", "bv*+ba/b"),
        "merge_output_format": cfg.get("ingestion.conteneur", "mkv"),
        "outtmpl": str(dossier / "%(id)s.%(ext)s"),
        "continuedl": True,  # reprend un téléchargement interrompu
        "overwrites": False,
        "retries": 5,
    }
    log.info("Téléchargement de %s...", video_id)
    try:
        with yt_dlp.YoutubeDL(opts) as ydl:
            info = ydl.extract_info(url_video(video_id), download=True)
            info = ydl.sanitize_info(info)
    except yt_dlp.utils.DownloadError as exc:
        raise ErreurIngestion(f"Échec du téléchargement de {video_id} : {exc}") from exc

    chemin = fichier_existant(video_id, dossier)
    if not chemin:
        raise ErreurIngestion(f"Téléchargement terminé mais fichier introuvable pour {video_id}.")
    chemin_info.write_text(json.dumps(info, ensure_ascii=False), encoding="utf-8")
    log.info("Vidéo %s téléchargée : %s (%.0f Mo)", video_id, chemin.name, chemin.stat().st_size / 1e6)
    return chemin, info


def metadonnees_utiles(info: dict[str, Any]) -> dict[str, Any]:
    """Champs de métadonnées gardés dans la base (le JSON complet reste sur disque)."""
    return {
        "titre": info.get("title"),
        "chaine": info.get("channel") or info.get("uploader"),
        "duree": info.get("duration"),
        "date_publication": info.get("upload_date"),
    }
