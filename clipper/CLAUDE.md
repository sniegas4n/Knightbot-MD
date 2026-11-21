# Clipper

## But
Transformer des vidéos YouTube longues (podcasts, interviews, formations) en clips horizontaux de 2 à 5 min.
Chaque clip reçoit une note, des titres et une miniature, passe par une revue en un clic, puis est publié
sur une chaîne YouTube de clips via une file programmée. L'utilisateur a les droits sur toutes les sources.
Tout tourne en local, sans cloud, en v1.

## Stack
- Python ≥ 3.10, SQLite (`data/clipper.db`), CLI en `argparse`.
- yt-dlp (téléchargement), Deepgram nova-3 en HTTP direct via `requests` (transcription au mot + locuteurs).
- SDK `anthropic` : modèle `claude-opus-5-5`, sorties JSON structurées, repli serveur `fallbacks="default"`.
- ffmpeg (audio, et en phase 2 la découpe). Phase 2 : FastAPI + HTML simple, Pillow. Phase 3 : YouTube Data v3 (OAuth).

## Commandes
```bash
pip install -e ".[dev]"      # installation (depuis clipper/)
python -m pytest -q          # tests
clipper add URL [URL...]     # vidéo, playlist ou chaîne → file d'attente
clipper run [--video ID] [--reselection]
clipper status               # état, erreurs, coût par vidéo et cumul
clipper clips ID             # candidats d'une vidéo (en attendant la revue web)
```

## Architecture
- `clipper/cli.py` : commandes. `pipeline.py` : enchaîne les étapes et reprend après un crash.
- `ingestion.py` → `transcription.py` → `selection.py` : une étape par module.
- `db.py` : schéma et accès SQLite. Le statut d'une vidéo = dernière étape réussie (`db.ETAPES`).
- `prompts/*.md` : prompts modifiables sans toucher au code (variables `{{nom}}`).
- `config.yaml` : réglages. `.env` : clés (`ANTHROPIC_API_KEY`, `DEEPGRAM_API_KEY`).
- `data/` (ignoré par git) : `videos/`, `audio/`, `transcriptions/` (JSON normalisé + réponse brute), `clipper.log`.

## Conventions
- Code, commentaires, logs et messages en français.
- Idempotence : chaque étape vérifie d'abord si son résultat existe déjà (fichier ou base). Jamais de retéléchargement
  ni de retranscription. Écrire dans un fichier temporaire puis renommer.
- Une vidéo en échec : `base.noter_erreur`, puis on passe à la suivante. Seule une `ErreurConfig` arrête tout.
- Chaque appel payant enregistre son coût estimé dans la table `couts`.
- Format de transcription interne : `{"fournisseur", "langue", "duree", "mots": [{"w", "s", "e", "spk"}]}`.
- Aucune nouvelle dépendance sans raison. Tests dans `tests/`, sans réseau (services simulés par monkeypatch).

## Avancement
- [x] Phase 1 : ingestion, transcription, sélection (+ tests parsing, doublons, reprise)
- [ ] Phase 2 : bornes, découpe, miniatures, titres, revue
- [ ] Phase 3 : publication et quota
- [ ] Phase 4 : suivi (vues, durée moyenne à J+2 et J+7, export CSV)

## Choix faits (à revoir si besoin)
- Deepgram plutôt que WhisperX : pas de GPU requis, locuteurs inclus. WhisperX pourra s'ajouter derrière `transcription.fournisseur`.
- Vidéo source fusionnée en mkv (accepte VP9/AV1/Opus sans réencodage).
- Audio envoyé à Deepgram en Opus mono 16 kHz 32 kb/s (fichier ~15 Mo/h).
- La sélection découpe en blocs de 120 min avec 10 min de recouvrement. Les doublons sont fusionnés par chevauchement < 20 %.
- Une URL de vidéo seule est reconnue sans appel réseau. Le titre arrive au téléchargement.
