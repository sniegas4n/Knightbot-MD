"""Doublons : ni vidéo ni clip ajouté deux fois, chevauchements filtrés."""

from clipper.selection import filtrer_chevauchements, taux_chevauchement


def test_video_ajoutee_deux_fois(base):
    assert base.ajouter_video("abc123", "https://youtu.be/abc123") is True
    assert base.ajouter_video("abc123", "https://youtu.be/abc123") is False
    assert len(base.videos()) == 1


def test_clip_identique_non_duplique(base):
    base.ajouter_video("v1", "u")
    clip = {"debut": 10.0, "fin": 200.0, "sujet": "s", "note": 50, "raison": "r"}
    assert base.ajouter_clips("v1", [clip]) == 1
    assert base.ajouter_clips("v1", [clip, clip]) == 0
    assert base.nb_clips("v1") == 1


def test_reselection_garde_les_clips_deja_revus(base):
    base.ajouter_video("v1", "u")
    base.ajouter_clips("v1", [{"debut": 0, "fin": 150, "sujet": "a", "note": 50},
                              {"debut": 300, "fin": 450, "sujet": "b", "note": 60}])
    base.cx.execute("UPDATE clips SET statut = 'valide' WHERE sujet = 'b'")
    assert base.supprimer_candidats("v1") == 1
    assert [c["sujet"] for c in base.clips("v1")] == ["b"]


def _c(debut, fin, note):
    return {"debut": debut, "fin": fin, "note": note, "sujet": "s"}


def test_taux_chevauchement():
    assert taux_chevauchement(_c(0, 100, 1), _c(100, 200, 1)) == 0
    assert taux_chevauchement(_c(0, 100, 1), _c(50, 250, 1)) == 0.5
    assert taux_chevauchement(_c(0, 300, 1), _c(100, 200, 1)) == 1.0


def test_chevauchement_fort_garde_le_mieux_note():
    gardes = filtrer_chevauchements([_c(0, 200, 60), _c(100, 300, 80)], 0.2)
    assert gardes == [_c(100, 300, 80)]


def test_chevauchement_faible_garde_les_deux():
    # 10 % de recouvrement : sous le seuil de 20 %.
    gardes = filtrer_chevauchements([_c(0, 200, 60), _c(180, 380, 80)], 0.2)
    assert len(gardes) == 2 and gardes[0]["debut"] == 0


def test_doublon_issu_du_recouvrement_des_blocs():
    # Le même clip proposé par deux blocs, avec des bornes légèrement différentes.
    gardes = filtrer_chevauchements([_c(5000, 5200, 70), _c(5002, 5198, 72)], 0.2)
    assert len(gardes) == 1 and gardes[0]["note"] == 72
