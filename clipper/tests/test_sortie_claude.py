"""Parsing et validation de la réponse de Claude."""

import json

import pytest

from clipper.selection import ErreurSelection, analyser_reponse


def _cand(**kw):
    c = {"debut": 100.0, "fin": 280.0, "sujet": "Pourquoi X", "note": 75, "raison": "Accroche forte."}
    c.update(kw)
    return c


def test_json_valide():
    texte = json.dumps({"candidats": [_cand(), _cand(debut=400, fin=600, note=90)]})
    candidats, rejets = analyser_reponse(texte, 3600)
    assert len(candidats) == 2 and rejets == []
    assert candidats[1]["note"] == 90


def test_json_dans_un_bloc_de_code_et_texte_autour():
    texte = "Voici mes choix :\n```json\n" + json.dumps({"candidats": [_cand()]}) + "\n```\nBonne journée"
    candidats, _ = analyser_reponse(texte)
    assert len(candidats) == 1


def test_objet_entoure_de_texte_sans_bloc():
    texte = "Résultat : " + json.dumps({"candidats": [_cand()]}) + " fin."
    assert len(analyser_reponse(texte)[0]) == 1


def test_liste_nue_acceptee():
    assert len(analyser_reponse(json.dumps([_cand()]))[0]) == 1


def test_note_texte_convertie_et_arrondie():
    candidats, _ = analyser_reponse(json.dumps({"candidats": [_cand(note="82.6")]}))
    assert candidats[0]["note"] == 83


@pytest.mark.parametrize(
    "mauvais, motif",
    [
        (_cand(fin=50), "bornes"),
        (_cand(debut=-5), "bornes"),
        (_cand(note=150), "note"),
        (_cand(sujet="  "), "sujet"),
        (_cand(debut="abc"), "numérique"),
        ({"fin": 200, "sujet": "x", "note": 50}, "début"),
        (_cand(fin=5000), "après la fin"),
        ("pas un objet", "objet"),
    ],
)
def test_candidats_invalides_rejetes_avec_motif(mauvais, motif):
    texte = json.dumps({"candidats": [_cand(), mauvais]})
    candidats, rejets = analyser_reponse(texte, 3600)
    assert len(candidats) == 1
    assert len(rejets) == 1 and motif in rejets[0]


def test_reponse_non_json():
    with pytest.raises(ErreurSelection):
        analyser_reponse("Je ne peux pas faire ça.")


def test_cle_candidats_absente():
    with pytest.raises(ErreurSelection):
        analyser_reponse(json.dumps({"clips": []}))
