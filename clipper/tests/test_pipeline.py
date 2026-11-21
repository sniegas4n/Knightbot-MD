"""Pipeline complet simulé : idempotence, reprise après crash, une vidéo en échec ne bloque pas les autres."""

import json

import pytest

from clipper import ingestion, pipeline, selection, transcription


@pytest.fixture
def faux_services(cfg, monkeypatch):
    """Remplace YouTube, Deepgram et Claude par des fonctions locales qui comptent leurs appels."""
    appels = {"telechargement": 0, "deepgram": 0, "claude": 0}
    en_panne = set()

    def faux_telecharger(video_id, cfg_, url=None):
        if video_id in en_panne:
            raise ingestion.ErreurIngestion("vidéo indisponible")
        appels["telechargement"] += 1
        chemin = cfg_.sous_dossier("videos") / f"{video_id}.mkv"
        chemin.write_bytes(b"video")
        return chemin, {"title": f"Titre {video_id}", "channel": "Chaîne", "duration": 900}

    def faux_audio(video, dossier):
        return video

    def faux_deepgram(audio, cfg_):
        appels["deepgram"] += 1
        mots = [{"word": f"m{i}", "punctuated_word": f"m{i}.", "start": i, "end": i + 0.5, "speaker": 0}
                for i in range(900)]
        return {"metadata": {"duration": 900}, "results": {"channels": [{"alternatives": [{"words": mots}]}]}}

    def faux_claude(client, systeme, message, cfg_):
        appels["claude"] += 1
        return json.dumps({"candidats": [
            {"debut": 10, "fin": 160, "sujet": "Un", "note": 80, "raison": "r"},
            {"debut": 400, "fin": 600, "sujet": "Deux", "note": 70, "raison": "r"},
        ]}), 0.05

    monkeypatch.setattr(ingestion, "telecharger", faux_telecharger)
    monkeypatch.setattr(transcription, "extraire_audio", faux_audio)
    monkeypatch.setattr(transcription, "_transcrire_deepgram", faux_deepgram)
    monkeypatch.setattr(selection, "appeler_claude", faux_claude)
    monkeypatch.setattr(selection.anthropic, "Anthropic", lambda **kw: object())
    monkeypatch.setenv("ANTHROPIC_API_KEY", "test")
    return appels, en_panne


def test_pipeline_complet_puis_rien_a_refaire(base, cfg, faux_services):
    appels, _ = faux_services
    base.ajouter_video("vid00000001", "u")
    assert pipeline.run(base, cfg) == (1, 0)
    v = base.video("vid00000001")
    assert v["statut"] == "selectionnee" and v["titre"] == "Titre vid00000001" and v["duree"] == 900
    assert base.nb_clips("vid00000001") == 2
    assert base.cout_video("vid00000001") > 0.05  # transcription + sélection

    # Deuxième passage : aucun service payant rappelé.
    assert pipeline.run(base, cfg) == (0, 0)
    pipeline.traiter_video(base, cfg, "vid00000001")
    assert appels == {"telechargement": 1, "deepgram": 1, "claude": 1}


def test_echec_d_une_video_ne_bloque_pas_les_autres(base, cfg, faux_services):
    _, en_panne = faux_services
    base.ajouter_video("cassee00001", "u")
    base.ajouter_video("bonne000001", "u")
    en_panne.add("cassee00001")
    assert pipeline.run(base, cfg) == (1, 1)
    assert base.video("bonne000001")["statut"] == "selectionnee"
    cassee = base.video("cassee00001")
    assert cassee["statut"] == "en_attente" and "indisponible" in cassee["erreur"] and cassee["tentatives"] == 1

    # La vidéo est réparée : le run suivant la reprend, et seulement elle.
    en_panne.clear()
    assert pipeline.run(base, cfg) == (1, 0)
    assert base.video("cassee00001")["erreur"] is None


def test_reprise_apres_crash_pendant_la_selection(base, cfg, faux_services, monkeypatch):
    appels, _ = faux_services
    base.ajouter_video("vid00000002", "u")

    def crash(*a, **kw):
        raise RuntimeError("coupure réseau")

    original = selection.appeler_claude
    monkeypatch.setattr(selection, "appeler_claude", crash)
    assert pipeline.run(base, cfg) == (0, 1)
    assert base.video("vid00000002")["statut"] == "transcrite"

    monkeypatch.setattr(selection, "appeler_claude", original)
    assert pipeline.run(base, cfg) == (1, 0)
    # La transcription n'a pas été refaite.
    assert appels["deepgram"] == 1 and appels["telechargement"] == 1


def test_reselection_remplace_les_candidats(base, cfg, faux_services):
    appels, _ = faux_services
    base.ajouter_video("vid00000003", "u")
    pipeline.run(base, cfg)
    pipeline.run(base, cfg, reselection=True)
    assert base.nb_clips("vid00000003") == 2 and appels["claude"] == 2 and appels["deepgram"] == 1


@pytest.mark.parametrize("url, attendu", [
    ("https://www.youtube.com/watch?v=jNQXAC9IVRw", "jNQXAC9IVRw"),
    ("https://youtu.be/jNQXAC9IVRw?t=12", "jNQXAC9IVRw"),
    ("https://www.youtube.com/shorts/jNQXAC9IVRw", "jNQXAC9IVRw"),
    ("https://www.youtube.com/watch?v=jNQXAC9IVRw&list=PL123", None),
    ("https://www.youtube.com/@chaine", None),
    ("https://www.youtube.com/playlist?list=PL123", None),
])
def test_id_video_direct(url, attendu):
    assert ingestion.id_video_direct(url) == attendu


def test_import_fichier_local_sans_reseau(base, cfg, tmp_path):
    import subprocess
    source = tmp_path / "Mon épisode.mp4"
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "lavfi", "-i", "sine=frequency=440",
                    "-t", "3", str(source)], check=True)
    v = ingestion.importer_fichier(source, cfg)
    assert ingestion.importer_fichier(source, cfg)["id"] == v["id"]  # même fichier = même identifiant
    base.ajouter_video(v["id"], v["url"], v["titre"])
    chemin, info = ingestion.telecharger(v["id"], cfg, v["url"])  # déjà présent : aucun téléchargement
    assert chemin.exists() and info["title"] == "Mon épisode" and 2.5 < info["duration"] < 3.5
