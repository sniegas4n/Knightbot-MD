"""Normalisation Deepgram, regroupement en phrases, découpage en blocs, sélection simulée."""

import json
from types import SimpleNamespace

from clipper import selection
from clipper.selection import decouper_en_blocs, formater, phrases
from clipper.transcription import normaliser_deepgram


def _mot(w, s, e, spk=0):
    return {"w": w, "s": s, "e": e, "spk": spk}


def test_normaliser_deepgram():
    brut = {
        "metadata": {"duration": 12.5},
        "results": {"channels": [{"alternatives": [{"words": [
            {"word": "bonjour", "punctuated_word": "Bonjour,", "start": 0.1, "end": 0.5, "speaker": 0},
            {"word": "salut", "start": 1.0, "end": 1.3, "speaker": 1},
        ]}]}]},
    }
    t = normaliser_deepgram(brut)
    assert t["duree"] == 12.5
    assert t["mots"] == [_mot("Bonjour,", 0.1, 0.5, 0), _mot("salut", 1.0, 1.3, 1)]


def test_phrases_coupees_sur_ponctuation_locuteur_et_silence():
    mots = [
        _mot("Bonjour", 0, 0.4), _mot("à", 0.5, 0.6), _mot("tous.", 0.7, 1.0),
        _mot("On", 1.1, 1.2), _mot("commence", 1.3, 1.8),
        _mot("Oui", 1.9, 2.1, spk=1),
        _mot("après", 6.0, 6.4, spk=1), _mot("silence", 6.5, 7.0, spk=1),
    ]
    p = phrases(mots)
    assert [x["texte"] for x in p] == ["Bonjour à tous.", "On commence", "Oui", "après silence"]
    assert p[0]["s"] == 0 and p[0]["e"] == 1.0
    assert formater(p[:1]) == "[0.0–1.0] S0 : Bonjour à tous."


def test_decoupage_en_blocs_qui_se_recouvrent():
    liste = [{"s": float(t), "e": t + 9.0, "spk": 0, "texte": "x"} for t in range(0, 1000, 10)]
    blocs = decouper_en_blocs(liste, bloc_s=400, recouvrement_s=100)
    assert len(blocs) == 3
    assert blocs[0][0]["s"] == 0 and blocs[1][0]["s"] == 300
    # Le recouvrement : la fin du bloc 1 se retrouve au début du bloc 2.
    assert blocs[0][-1]["s"] > blocs[1][0]["s"]
    # Aucune phrase perdue.
    assert {p["s"] for b in blocs for p in b} == {p["s"] for p in liste}


def test_transcription_courte_en_un_seul_bloc():
    liste = [{"s": 0.0, "e": 50.0, "spk": 0, "texte": "x"}]
    assert decouper_en_blocs(liste, 7200, 600) == [liste]


def test_selectionner_avec_claude_simule(cfg, monkeypatch):
    """Toute la chaîne de sélection, sans appel réseau."""
    reponse = json.dumps({"candidats": [
        {"debut": 0, "fin": 150, "sujet": "A", "note": 70, "raison": "r"},
        {"debut": 10, "fin": 160, "sujet": "A bis", "note": 60, "raison": "r"},  # doublon de A
        {"debut": 300, "fin": 500, "sujet": "B", "note": 85, "raison": "r"},
        {"debut": 900, "fin": 800, "sujet": "invalide", "note": 50, "raison": "r"},
    ]})
    appels = []

    def faux_appel(client, systeme, message, cfg):
        appels.append((systeme, message))
        return reponse, 0.12

    monkeypatch.setattr(selection, "appeler_claude", faux_appel)
    mots = [_mot(f"mot{i}.", i * 1.0, i * 1.0 + 0.5) for i in range(600)]
    retenus, cout = selection.selectionner(
        {"id": "v1", "titre": "Test", "duree": 600}, {"mots": mots}, cfg, client=SimpleNamespace()
    )
    assert [c["sujet"] for c in retenus] == ["A", "B"]
    assert cout == 0.12
    assert "entre 5 et 15 candidats" in appels[0][0]  # variables du prompt remplacées
    assert "{{" not in appels[0][0]
    assert "[0.0–0.5] S0 : mot0." in appels[0][1]
