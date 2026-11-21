"""Enchaînement des étapes pour chaque vidéo. Reprend là où on s'était arrêté."""

from __future__ import annotations

from pathlib import Path

from clipper import ingestion, selection, transcription
from clipper.config import Config, ErreurConfig
from clipper.db import Base, etape_atteinte
from clipper.journal import journal

log = journal("pipeline")


def traiter_video(base: Base, cfg: Config, video_id: str, reselection: bool = False) -> None:
    """Fait avancer une vidéo d'étape en étape. Chaque étape déjà faite est sautée."""
    v = base.video(video_id)
    if v is None:
        raise ValueError(f"Vidéo inconnue : {video_id}")

    # 1. Ingestion
    fichier = Path(v["fichier"]) if v["fichier"] else None
    if not etape_atteinte(v["statut"], "telechargee") or not (fichier and fichier.exists()):
        fichier, info = ingestion.telecharger(video_id, cfg, v["url"])
        base.maj_video(video_id, fichier=str(fichier), statut=max_statut(v["statut"], "telechargee"),
                       **ingestion.metadonnees_utiles(info))
        v = base.video(video_id)

    # 2. Transcription
    if not etape_atteinte(v["statut"], "transcrite") or base.transcription(video_id) is None:
        t, cout, nouvelle = transcription.transcrire(video_id, fichier, cfg)
        if nouvelle:
            base.ajouter_cout(video_id, "transcription", cout, f"{t['duree'] / 60:.1f} min")
        chemin = cfg.sous_dossier("transcriptions") / f"{video_id}.json"
        base.enregistrer_transcription(video_id, t["fournisseur"], t.get("langue", ""), str(chemin), len(t["mots"]))
        base.maj_video(video_id, statut=max_statut(v["statut"], "transcrite"))
        v = base.video(video_id)
    else:
        t, _, _ = transcription.transcrire(video_id, fichier, cfg)

    # 3. Sélection
    if reselection:
        n = base.supprimer_candidats(video_id)
        log.info("%s : %d anciens candidats supprimés, nouvelle sélection.", video_id, n)
    elif etape_atteinte(v["statut"], "selectionnee"):
        log.info("%s : sélection déjà faite (%d clips).", video_id, base.nb_clips(video_id))
        return
    candidats, cout = selection.selectionner(dict(v), t, cfg)
    base.ajouter_cout(video_id, "selection", cout, cfg.get("selection.modele", ""))
    ajoutes = base.ajouter_clips(video_id, candidats)
    base.maj_video(video_id, statut="selectionnee", erreur=None)
    log.info("%s : %d clips candidats enregistrés.", video_id, ajoutes)


def max_statut(actuel: str, nouveau: str) -> str:
    """Ne fait jamais reculer un statut."""
    return actuel if etape_atteinte(actuel, nouveau) else nouveau


def run(base: Base, cfg: Config, ids: list[str] | None = None, reselection: bool = False) -> tuple[int, int]:
    """Traite toutes les vidéos non terminées (ou celles demandées). Une erreur n'arrête pas les autres."""
    if ids:
        a_traiter = ids
    else:
        a_traiter = [v["id"] for v in base.videos() if v["statut"] != "selectionnee" or reselection]
    if not a_traiter:
        log.info("Rien à traiter : toutes les vidéos sont à jour.")
        return 0, 0

    ok = echecs = 0
    for i, video_id in enumerate(a_traiter, 1):
        log.info("— Vidéo %d/%d : %s", i, len(a_traiter), video_id)
        try:
            traiter_video(base, cfg, video_id, reselection=reselection)
            base.maj_video(video_id, erreur=None)
            ok += 1
        except KeyboardInterrupt:
            log.warning("Interruption demandée : l'état est sauvegardé, relance « clipper run » pour reprendre.")
            raise
        except ErreurConfig:
            raise  # clé manquante : inutile d'essayer les autres vidéos
        except Exception as exc:  # une vidéo en échec ne bloque pas les suivantes
            echecs += 1
            base.noter_erreur(video_id, str(exc))
            log.error("%s : échec (%s). On passe à la suivante.", video_id, exc)
            log.debug("Détail de l'erreur pour %s", video_id, exc_info=True)
    log.info("Terminé : %d vidéo(s) traitée(s), %d en échec.", ok, echecs)
    return ok, echecs
