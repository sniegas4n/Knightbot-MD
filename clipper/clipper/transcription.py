"""Étape 2 : transcription horodatée au mot, avec locuteurs. Mise en cache : jamais deux fois."""

from __future__ import annotations

import json
import subprocess
from pathlib import Path
from typing import Any

import requests

from clipper.config import Config
from clipper.journal import journal

log = journal("transcription")

URL_DEEPGRAM = "https://api.deepgram.com/v1/listen"


class ErreurTranscription(Exception):
    pass


def extraire_audio(video: Path, dossier: Path) -> Path:
    """Extrait une piste audio légère (mono 16 kHz, Opus) pour l'envoi à la transcription."""
    sortie = dossier / f"{video.stem}.ogg"
    if sortie.exists() and sortie.stat().st_size > 0:
        return sortie
    temporaire = sortie.with_suffix(".tmp.ogg")
    cmd = [
        "ffmpeg", "-y", "-loglevel", "error", "-i", str(video),
        "-vn", "-ac", "1", "-ar", "16000", "-c:a", "libopus", "-b:a", "32k", str(temporaire),
    ]
    resultat = subprocess.run(cmd, capture_output=True, text=True)
    if resultat.returncode != 0:
        raise ErreurTranscription(f"ffmpeg n'a pas pu extraire l'audio : {resultat.stderr.strip()[-500:]}")
    temporaire.rename(sortie)  # renommage en dernier : un crash ne laisse pas de fichier à moitié écrit
    return sortie


def normaliser_deepgram(reponse: dict[str, Any]) -> dict[str, Any]:
    """Convertit la réponse Deepgram dans notre format : une liste de mots {w, s, e, spk}."""
    try:
        alternative = reponse["results"]["channels"][0]["alternatives"][0]
    except (KeyError, IndexError) as exc:
        raise ErreurTranscription("Réponse Deepgram inattendue : pas de transcription.") from exc
    mots = [
        {
            "w": m.get("punctuated_word") or m["word"],
            "s": round(float(m["start"]), 3),
            "e": round(float(m["end"]), 3),
            "spk": int(m.get("speaker", 0)),
        }
        for m in alternative.get("words", [])
    ]
    duree = reponse.get("metadata", {}).get("duration") or (mots[-1]["e"] if mots else 0.0)
    return {"fournisseur": "deepgram", "duree": float(duree), "mots": mots}


def _transcrire_deepgram(audio: Path, cfg: Config) -> dict[str, Any]:
    cle = cfg.secret("DEEPGRAM_API_KEY")
    params = {
        "model": cfg.get("transcription.deepgram.modele", "nova-3"),
        "language": cfg.get("transcription.langue", "fr"),
        "diarize": "true",
        "punctuate": "true",
        "smart_format": "true",
    }
    log.info("Envoi de %s à Deepgram (%.1f Mo)...", audio.name, audio.stat().st_size / 1e6)
    with audio.open("rb") as f:
        r = requests.post(
            URL_DEEPGRAM,
            params=params,
            headers={"Authorization": f"Token {cle}", "Content-Type": "audio/ogg"},
            data=f,
            timeout=(30, 3600),
        )
    if r.status_code != 200:
        raise ErreurTranscription(f"Deepgram a répondu {r.status_code} : {r.text[:300]}")
    return r.json()


def transcrire(video_id: str, fichier_video: Path, cfg: Config) -> tuple[dict[str, Any], float, bool]:
    """Retourne (transcription, coût en dollars, nouvelle ?). Utilise le cache si la vidéo est déjà transcrite."""
    dossier = cfg.sous_dossier("transcriptions")
    chemin = dossier / f"{video_id}.json"
    if chemin.exists():
        log.info("Transcription de %s déjà en cache.", video_id)
        return json.loads(chemin.read_text(encoding="utf-8")), 0.0, False

    fournisseur = cfg.get("transcription.fournisseur", "deepgram")
    if fournisseur != "deepgram":
        raise ErreurTranscription(f"Fournisseur de transcription inconnu : {fournisseur}")

    audio = extraire_audio(fichier_video, cfg.sous_dossier("audio"))
    brut = _transcrire_deepgram(audio, cfg)
    # La réponse brute est gardée : si notre format évolue, on renormalise sans repayer.
    (dossier / f"{video_id}.deepgram.json").write_text(json.dumps(brut, ensure_ascii=False), encoding="utf-8")
    transcription = normaliser_deepgram(brut)
    transcription["langue"] = cfg.get("transcription.langue", "fr")
    chemin.write_text(json.dumps(transcription, ensure_ascii=False), encoding="utf-8")

    cout = transcription["duree"] / 60 * float(cfg.get("transcription.deepgram.prix_par_minute", 0))
    log.info(
        "Transcription de %s terminée : %d mots, %d locuteurs, coût estimé %.3f $.",
        video_id, len(transcription["mots"]), len({m["spk"] for m in transcription["mots"]}), cout,
    )
    return transcription, cout, True
