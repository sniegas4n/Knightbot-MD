"""Ligne de commande : clipper add | run | review | publish | status | stats."""

from __future__ import annotations

import argparse
import sys

from clipper import ingestion, pipeline
from clipper.config import ErreurConfig, charger_config
from clipper.db import Base
from clipper.journal import configurer, journal

log = journal("cli")


def cmd_add(base: Base, cfg, args) -> int:
    total_nouvelles = total_connues = 0
    for url in args.urls:
        try:
            videos = ingestion.lister_videos(url, cfg)
        except ingestion.ErreurIngestion as exc:
            log.error("%s", exc)
            continue
        nouvelles = sum(base.ajouter_video(v["id"], ingestion.url_video(v["id"]), v["titre"] or None) for v in videos)
        total_nouvelles += nouvelles
        total_connues += len(videos) - nouvelles
        log.info("%s : %d vidéo(s) trouvée(s), %d nouvelle(s).", url, len(videos), nouvelles)
    log.info("Ajout terminé : %d nouvelle(s), %d déjà connue(s). Lance « clipper run » pour les traiter.",
             total_nouvelles, total_connues)
    return 0


def cmd_run(base: Base, cfg, args) -> int:
    _, echecs = pipeline.run(base, cfg, ids=args.video or None, reselection=args.reselection)
    return 1 if echecs else 0


def cmd_status(base: Base, cfg, args) -> int:
    videos = base.videos()
    if not videos:
        print("Aucune vidéo. Commence par « clipper add URL ».")
        return 0
    print(f"{'Vidéo':<12} {'Statut':<13} {'Clips':>5} {'Coût':>8}  Titre")
    for v in videos:
        titre = (v["titre"] or "")[:50]
        print(f"{v['id']:<12} {v['statut']:<13} {base.nb_clips(v['id']):>5} {base.cout_video(v['id']):>7.3f}$  {titre}")
        if v["erreur"]:
            print(f"{'':<12} ↳ dernière erreur ({v['tentatives']} tentative(s)) : {v['erreur'][:120]}")
    print(f"\nCoût cumulé estimé : {base.cout_total():.3f} $")
    return 0


def cmd_clips(base: Base, cfg, args) -> int:
    """Affiche les candidats d'une vidéo (en attendant la page de revue de la phase 2)."""
    clips = base.clips(args.video)
    if not clips:
        print("Aucun clip pour cette vidéo.")
        return 0
    for c in clips:
        duree = c["fin"] - c["debut"]
        print(f"[{c['note']:>3}/100] {_hms(c['debut'])} → {_hms(c['fin'])} ({duree / 60:.1f} min)  {c['sujet']}")
        print(f"          {c['raison']}")
        print(f"          https://youtu.be/{c['video_id']}?t={int(c['debut'])}")
    return 0


def _hms(s: float) -> str:
    s = int(s)
    return f"{s // 3600}:{s % 3600 // 60:02d}:{s % 60:02d}"


def cmd_a_venir(phase: int):
    def _cmd(base, cfg, args) -> int:
        print(f"Cette commande arrive en phase {phase}.")
        return 0
    return _cmd


def construire_parseur() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="clipper", description="Transforme des vidéos YouTube longues en clips.")
    p.add_argument("--config", help="chemin de config.yaml (défaut : ./config.yaml)")
    p.add_argument("-v", "--verbeux", action="store_true", help="affiche les messages détaillés")
    sous = p.add_subparsers(dest="commande", required=True)

    a = sous.add_parser("add", help="ajoute une vidéo, une playlist ou une chaîne")
    a.add_argument("urls", nargs="+")
    a.set_defaults(fonction=cmd_add)

    r = sous.add_parser("run", help="traite les vidéos en attente (reprend après un crash)")
    r.add_argument("--video", action="append", help="ne traiter que cette vidéo (répétable)")
    r.add_argument("--reselection", action="store_true", help="refait la sélection (les candidats non revus sont remplacés)")
    r.set_defaults(fonction=cmd_run)

    s = sous.add_parser("status", help="état des vidéos et coûts")
    s.set_defaults(fonction=cmd_status)

    c = sous.add_parser("clips", help="liste les clips candidats d'une vidéo")
    c.add_argument("video")
    c.set_defaults(fonction=cmd_clips)

    for nom, phase, aide in (("review", 2, "page de revue locale"), ("publish", 3, "publication programmée"),
                             ("stats", 4, "suivi des performances")):
        x = sous.add_parser(nom, help=f"{aide} (phase {phase})")
        x.set_defaults(fonction=cmd_a_venir(phase))
    return p


def main(argv: list[str] | None = None) -> int:
    args = construire_parseur().parse_args(argv)
    try:
        cfg = charger_config(args.config)
    except ErreurConfig as exc:
        print(f"Erreur : {exc}", file=sys.stderr)
        return 2
    configurer(cfg.dossier_donnees / "clipper.log", args.verbeux)
    base = Base(cfg.chemin_base)
    try:
        return args.fonction(base, cfg, args)
    except ErreurConfig as exc:
        log.error("%s", exc)
        return 2
    except KeyboardInterrupt:
        return 130
    finally:
        base.fermer()
