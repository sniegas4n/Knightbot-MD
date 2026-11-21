"""État de Clipper dans SQLite : vidéos, transcriptions, clips, coûts."""

from __future__ import annotations

import sqlite3
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable

# Étapes d'une vidéo, dans l'ordre. Le statut indique la dernière étape réussie.
ETAPES = ("en_attente", "telechargee", "transcrite", "selectionnee")

SCHEMA = """
CREATE TABLE IF NOT EXISTS videos (
    id               TEXT PRIMARY KEY,          -- identifiant YouTube
    url              TEXT NOT NULL,
    titre            TEXT,
    chaine           TEXT,
    duree            REAL,                      -- secondes
    date_publication TEXT,
    fichier          TEXT,                      -- chemin de la vidéo téléchargée
    statut           TEXT NOT NULL DEFAULT 'en_attente',
    erreur           TEXT,                      -- dernière erreur, vide si tout va bien
    tentatives       INTEGER NOT NULL DEFAULT 0,
    ajoutee_le       TEXT NOT NULL,
    maj_le           TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS transcriptions (
    video_id    TEXT PRIMARY KEY REFERENCES videos(id),
    fournisseur TEXT NOT NULL,
    langue      TEXT,
    fichier     TEXT NOT NULL,                  -- JSON normalisé des mots
    nb_mots     INTEGER,
    creee_le    TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS clips (
    id       INTEGER PRIMARY KEY AUTOINCREMENT,
    video_id TEXT NOT NULL REFERENCES videos(id),
    debut    REAL NOT NULL,
    fin      REAL NOT NULL,
    sujet    TEXT NOT NULL,
    note     INTEGER NOT NULL,
    raison   TEXT,
    statut   TEXT NOT NULL DEFAULT 'candidat',
    cree_le  TEXT NOT NULL,
    UNIQUE (video_id, debut, fin)
);

CREATE TABLE IF NOT EXISTS couts (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    video_id    TEXT,
    etape       TEXT NOT NULL,
    detail      TEXT,
    montant_usd REAL NOT NULL,
    cree_le     TEXT NOT NULL
);
"""


def maintenant() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


class Base:
    def __init__(self, chemin: Path | str):
        self.cx = sqlite3.connect(str(chemin))
        self.cx.row_factory = sqlite3.Row
        self.cx.execute("PRAGMA foreign_keys = ON")
        self.cx.execute("PRAGMA journal_mode = WAL")
        self.cx.executescript(SCHEMA)

    def fermer(self) -> None:
        self.cx.close()

    # --- Vidéos ---------------------------------------------------------

    def ajouter_video(self, video_id: str, url: str, titre: str | None = None) -> bool:
        """Ajoute une vidéo. Retourne False si elle était déjà connue (aucun doublon)."""
        t = maintenant()
        cur = self.cx.execute(
            "INSERT OR IGNORE INTO videos (id, url, titre, ajoutee_le, maj_le) VALUES (?, ?, ?, ?, ?)",
            (video_id, url, titre, t, t),
        )
        self.cx.commit()
        return cur.rowcount == 1

    def video(self, video_id: str) -> sqlite3.Row | None:
        return self.cx.execute("SELECT * FROM videos WHERE id = ?", (video_id,)).fetchone()

    def videos(self) -> list[sqlite3.Row]:
        return self.cx.execute("SELECT * FROM videos ORDER BY ajoutee_le, id").fetchall()

    def maj_video(self, video_id: str, **champs: Any) -> None:
        champs["maj_le"] = maintenant()
        colonnes = ", ".join(f"{c} = ?" for c in champs)
        self.cx.execute(f"UPDATE videos SET {colonnes} WHERE id = ?", (*champs.values(), video_id))
        self.cx.commit()

    def noter_erreur(self, video_id: str, message: str) -> None:
        self.cx.execute(
            "UPDATE videos SET erreur = ?, tentatives = tentatives + 1, maj_le = ? WHERE id = ?",
            (message, maintenant(), video_id),
        )
        self.cx.commit()

    # --- Transcriptions -------------------------------------------------

    def enregistrer_transcription(
        self, video_id: str, fournisseur: str, langue: str, fichier: str, nb_mots: int
    ) -> None:
        self.cx.execute(
            "INSERT OR REPLACE INTO transcriptions VALUES (?, ?, ?, ?, ?, ?)",
            (video_id, fournisseur, langue, fichier, nb_mots, maintenant()),
        )
        self.cx.commit()

    def transcription(self, video_id: str) -> sqlite3.Row | None:
        return self.cx.execute("SELECT * FROM transcriptions WHERE video_id = ?", (video_id,)).fetchone()

    # --- Clips ----------------------------------------------------------

    def ajouter_clips(self, video_id: str, candidats: Iterable[dict[str, Any]]) -> int:
        """Insère les candidats. Un clip identique (même vidéo, début, fin) n'est jamais dupliqué."""
        t = maintenant()
        n = 0
        for c in candidats:
            cur = self.cx.execute(
                "INSERT OR IGNORE INTO clips (video_id, debut, fin, sujet, note, raison, cree_le)"
                " VALUES (?, ?, ?, ?, ?, ?, ?)",
                (video_id, c["debut"], c["fin"], c["sujet"], c["note"], c.get("raison"), t),
            )
            n += cur.rowcount
        self.cx.commit()
        return n

    def supprimer_candidats(self, video_id: str) -> int:
        """Supprime les clips encore au stade « candidat » (avant revue), pour relancer la sélection."""
        cur = self.cx.execute("DELETE FROM clips WHERE video_id = ? AND statut = 'candidat'", (video_id,))
        self.cx.commit()
        return cur.rowcount

    def clips(self, video_id: str) -> list[sqlite3.Row]:
        return self.cx.execute(
            "SELECT * FROM clips WHERE video_id = ? ORDER BY note DESC, debut", (video_id,)
        ).fetchall()

    def nb_clips(self, video_id: str) -> int:
        return self.cx.execute("SELECT COUNT(*) FROM clips WHERE video_id = ?", (video_id,)).fetchone()[0]

    # --- Coûts ----------------------------------------------------------

    def ajouter_cout(self, video_id: str | None, etape: str, montant_usd: float, detail: str = "") -> None:
        self.cx.execute(
            "INSERT INTO couts (video_id, etape, detail, montant_usd, cree_le) VALUES (?, ?, ?, ?, ?)",
            (video_id, etape, detail, montant_usd, maintenant()),
        )
        self.cx.commit()

    def cout_video(self, video_id: str) -> float:
        r = self.cx.execute("SELECT COALESCE(SUM(montant_usd), 0) FROM couts WHERE video_id = ?", (video_id,))
        return float(r.fetchone()[0])

    def cout_total(self) -> float:
        return float(self.cx.execute("SELECT COALESCE(SUM(montant_usd), 0) FROM couts").fetchone()[0])


def etape_atteinte(statut: str, etape: str) -> bool:
    """Vrai si la vidéo a déjà franchi l'étape donnée."""
    return ETAPES.index(statut) >= ETAPES.index(etape)
