# RAPHAËL — Personal Intelligence System

Assistant IA personnel : conversation écrite et vocale, mémoire persistante, synchronisation
multi-appareils, modules stratégiques. PWA installable (iPhone, iPad, Android, Windows, macOS).

- [Architecture](docs/ARCHITECTURE.md) · [Système de design](docs/DESIGN.md) · [Plan de développement](docs/ROADMAP.md)

## Structure
```
raphael/
├── docs/                    Architecture, design, roadmap
├── docker-compose.yml       PostgreSQL 16 + pgvector (dev)
└── apps/
    ├── api/                 FastAPI (Python 3.12+)
    │   ├── app/core/        config, base de données, en-têtes de sécurité
    │   ├── app/modules/     un dossier par module (health, auth, puis conversation, voice, memory…)
    │   ├── migrations/      SQL versionné (001 schéma complet, 002 authentification)
    │   ├── scripts/         migrate.py
    │   └── tests/
    └── web/                 Next.js 15 + TypeScript + Tailwind 4 + Framer Motion
        ├── app/             /login, (app)/ = 8 sections protégées, /design, manifest PWA
        ├── components/      core/, nav/, shell/, home/, settings/, sections/, ui/
        ├── lib/             client API, session (AuthGate), appareils, sections
        ├── middleware.ts    redirection vers /login sans cookie de session
        └── public/icons/    icônes PWA / iOS
```

## Démarrage depuis un iPad (GitHub Codespaces)
1. Dans Safari : github.com → dépôt **Knightbot-MD** (branche par défaut).
2. **Code** → onglet **Codespaces** → **Create codespace on …**
   (la base PostgreSQL + pgvector et les dépendances s'installent seules, ~3–5 min).
3. Dans le terminal du Codespace : `cd raphael && ./dev.sh`
4. Onglet **Ports** → port **3000** → icône 🌐 pour ouvrir RAPHAËL.
5. Premier lancement : l'écran **Configuration initiale** crée votre compte propriétaire
   (un seul compte possible). Si le port est rendu public, définissez d'abord
   `RAPHAEL_SETUP_TOKEN` dans `apps/api/.env`.

## Démarrage (ordinateur)
```bash
# 1. Base de données
docker compose up -d db

# 2. Installation + lancement (API port 8000, interface port 3000)
./setup.sh
./dev.sh               # http://localhost:3000
```

## Tests
```bash
cd apps/api
RAPHAEL_TEST_DATABASE_URL=postgresql://raphael:raphael@localhost:5432/raphael_test .venv/bin/pytest
cd ../web && npm run typecheck && npm run build
```
Sans `RAPHAEL_TEST_DATABASE_URL`, les tests de base de données sont ignorés (signalés `skipped`).
