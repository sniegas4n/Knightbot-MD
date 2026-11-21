"""Journalisation en français, à l'écran et dans data/clipper.log."""

from __future__ import annotations

import logging
from pathlib import Path

_NIVEAUX = {
    logging.DEBUG: "détail",
    logging.INFO: "info",
    logging.WARNING: "attention",
    logging.ERROR: "erreur",
    logging.CRITICAL: "critique",
}


def configurer(fichier: Path, verbeux: bool = False) -> None:
    for niveau, nom in _NIVEAUX.items():
        logging.addLevelName(niveau, nom)

    racine = logging.getLogger("clipper")
    racine.setLevel(logging.DEBUG)
    racine.handlers.clear()

    ecran = logging.StreamHandler()
    ecran.setLevel(logging.DEBUG if verbeux else logging.INFO)
    ecran.setFormatter(logging.Formatter("%(asctime)s %(levelname)-9s %(message)s", "%H:%M:%S"))
    racine.addHandler(ecran)

    disque = logging.FileHandler(fichier, encoding="utf-8")
    disque.setLevel(logging.DEBUG)
    disque.setFormatter(logging.Formatter("%(asctime)s %(levelname)-9s [%(name)s] %(message)s"))
    racine.addHandler(disque)


def journal(nom: str) -> logging.Logger:
    return logging.getLogger(f"clipper.{nom}")
