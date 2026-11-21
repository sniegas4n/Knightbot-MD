"""Chargement de config.yaml et du .env."""

from __future__ import annotations

import os
from pathlib import Path
from typing import Any

import yaml
from dotenv import load_dotenv


class ErreurConfig(Exception):
    """Réglage manquant ou invalide."""


class Config:
    """Accès aux réglages, avec les chemins résolus par rapport au dossier de config.yaml."""

    def __init__(self, donnees: dict[str, Any], racine: Path):
        self.donnees = donnees
        self.racine = racine

    def get(self, chemin: str, defaut: Any = None) -> Any:
        """Lit une valeur par chemin pointé, ex. « selection.modele »."""
        valeur: Any = self.donnees
        for cle in chemin.split("."):
            if not isinstance(valeur, dict) or cle not in valeur:
                return defaut
            valeur = valeur[cle]
        return valeur

    @property
    def dossier_donnees(self) -> Path:
        dossier = self.racine / self.get("dossier_donnees", "data")
        dossier.mkdir(parents=True, exist_ok=True)
        return dossier

    def sous_dossier(self, nom: str) -> Path:
        dossier = self.dossier_donnees / nom
        dossier.mkdir(parents=True, exist_ok=True)
        return dossier

    @property
    def chemin_base(self) -> Path:
        return self.dossier_donnees / "clipper.db"

    @property
    def dossier_prompts(self) -> Path:
        return self.racine / "prompts"

    @staticmethod
    def secret(nom: str) -> str:
        """Lit une clé dans l'environnement (alimenté par .env), avec un message clair si elle manque."""
        valeur = os.environ.get(nom, "").strip()
        if not valeur:
            raise ErreurConfig(f"La variable {nom} est vide : renseigne-la dans le fichier .env.")
        return valeur


def charger_config(chemin: str | Path | None = None) -> Config:
    """Charge config.yaml (dossier courant par défaut, ou CLIPPER_CONFIG) et le .env voisin."""
    chemin = Path(chemin or os.environ.get("CLIPPER_CONFIG") or "config.yaml").resolve()
    if not chemin.exists():
        raise ErreurConfig(f"Fichier de configuration introuvable : {chemin}")
    racine = chemin.parent
    load_dotenv(racine / ".env")
    with chemin.open(encoding="utf-8") as f:
        donnees = yaml.safe_load(f) or {}
    return Config(donnees, racine)
