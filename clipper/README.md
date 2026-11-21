# Clipper

Clipper transforme des vidéos YouTube longues (podcasts, interviews, formations) en clips horizontaux de 2 à 5 minutes, prêts à publier sur une chaîne de clips.

> **État : phase 1.** Ingestion, transcription et sélection des clips candidats fonctionnent.
> La découpe, les miniatures et la page de revue arrivent en phase 2, la publication en phase 3.

## Installation pas à pas

### 1. Prérequis
- **Python 3.10 ou plus** : `python3 --version`
- **ffmpeg** : `ffmpeg -version`
  - macOS : `brew install ffmpeg`
  - Ubuntu/Debian : `sudo apt install ffmpeg`
  - Windows : `winget install ffmpeg`
- **Deno** (recommandé, YouTube l'exige pour yt-dlp) : https://deno.com, ou **Node.js** s'il est déjà installé.

### 2. Installer Clipper
```bash
cd clipper
python3 -m venv .venv
source .venv/bin/activate          # Windows : .venv\Scripts\activate
pip install -e ".[dev]"
```

### 3. Les clés API
```bash
cp .env.example .env
```
Ouvre `.env` et remplis :
- `ANTHROPIC_API_KEY` : crée une clé sur https://console.anthropic.com/settings/keys
- `DEEPGRAM_API_KEY` : crée un compte sur https://console.deepgram.com (crédit offert à l'inscription), puis *API Keys → Create a New API Key*.

### 4. Vérifier
```bash
python -m pytest -q      # tous les tests doivent passer
clipper status           # « Aucune vidéo. »
```

### 5. OAuth YouTube (phase 3)
La procédure (projet Google Cloud, API YouTube Data v3, écran de consentement, identifiants « Application de bureau ») sera détaillée ici en phase 3.

## Utilisation
```bash
clipper add "https://www.youtube.com/watch?v=XXXXXXXXXXX"   # une vidéo
clipper add "https://www.youtube.com/playlist?list=PL..."    # une playlist
clipper add "https://www.youtube.com/@MaChaine"              # une chaîne entière
clipper run          # télécharge, transcrit, sélectionne (reprend où ça s'est arrêté)
clipper status       # état de chaque vidéo, erreurs, coût estimé
clipper clips ID     # les clips candidats d'une vidéo, avec note et lien horodaté
```

- Les commandes sont **idempotentes** : relancer `add` ou `run` ne refait jamais un téléchargement ni une transcription.
- **Reprise après crash** : relance `clipper run`, chaque vidéo repart de sa dernière étape réussie.
- Une vidéo qui échoue est notée dans `status` et n'empêche pas les autres d'avancer.
- `clipper run --video ID --reselection` refait la sélection d'une vidéo (après une modification du prompt, par exemple). Les clips déjà revus sont conservés.

## Réglages
- `config.yaml` : tous les réglages, commentés (nombre de clips, durées, modèle, tarifs...).
- `prompts/selection.md` : le prompt de sélection, modifiable sans toucher au code.

## Dépannage
- **« Sign in to confirm you're not a bot »** : YouTube bloque ton adresse IP. Dans `config.yaml`, mets `cookies_navigateur: firefox` (ou `chrome`, `edge`...) avec un navigateur où tu es connecté à YouTube. Tu peux aussi exporter un `cookies.txt` et renseigner `fichier_cookies`.
- **« La variable … est vide »** : la clé manque dans `.env`.
- Le journal complet se trouve dans `data/clipper.log`. Lance une commande avec `-v` pour voir le détail à l'écran.

## Coûts estimés (par heure de vidéo)
- Transcription Deepgram : environ 0,40 $.
- Sélection Claude Opus 5.5 : environ 0,10 à 0,30 $ (≈ 15 000 jetons en entrée, plus la réflexion et la réponse).

`clipper status` affiche le coût estimé de chaque vidéo et le cumul.
