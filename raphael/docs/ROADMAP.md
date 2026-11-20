# RAPHAËL — Plan de développement

Chaque phase se termine par : code complet, tests qui passent, vérification manuelle, correction.
Aucune fonctionnalité n'est simulée : ce qui n'est pas prêt est affiché comme tel.

| Phase | Contenu | Critère de fin | Statut |
|---|---|---|---|
| **1. Architecture & design** | Docs d'architecture, système de design, monorepo, schéma de base complet (pgvector), API FastAPI avec sonde de santé, PWA Next.js avec tokens, noyau animé et page de référence du design | `pytest` vert, `next build` vert, migration appliquée sur PostgreSQL + pgvector | ✅ |
| **2. Interface principale** | Écran principal, navigation 8 sections, mise en page responsive, authentification (compte propriétaire, sessions, appareils) | Connexion réelle, navigation complète sur mobile et ordinateur | ✅ |
| **3. Moteur conversationnel** | Adaptateur LLM, prompt de personnalité, streaming WebSocket, historique persistant, socle des outils + file de confirmation | Conversation écrite réelle, persistée, reprise après rechargement | 🔜 |
| **4. Voix** | Capture micro, VAD, STT/TTS en flux, barge-in, mode appel | Conversation vocale mains libres avec interruption | 🔜 |
| **5. Mémoire persistante** | Extraction, embeddings, recherche hybride, consolidation, écran Mémoire (voir/modifier/supprimer) | Raphaël se souvient d'un fait d'une session à l'autre et cite sa source | 🔜 |
| **6. Multi-appareils** | Bus d'événements, synchro WebSocket, hors-ligne, installation PWA, notifications push | Message envoyé sur iPhone visible instantanément sur l'ordinateur | 🔜 |
| **7. Modules stratégiques** | Analyse/décision, objectifs & projets, agenda, budget, documents, recherche web ; étude téléphonie | Chaque module utilisable de bout en bout | 🔜 |
| **8. Tests & sécurité** | Tests E2E (Playwright), passkeys (Face ID / Touch ID / Windows Hello), audit sécurité, CSP, limitation de débit, export/suppression des données, sauvegardes | Checklist sécurité validée | 🔜 |

## Phase 2 — livré
- **API `auth`** : création unique du compte propriétaire (garantie par un index unique en base,
  jeton de configuration optionnel `RAPHAEL_SETUP_TOKEN`), connexion Argon2id, sessions opaques
  (SHA-256 seul stocké, cookie `httpOnly` + `SameSite=Strict`, `Secure` en HTTPS), appareils
  reconnus d'une connexion à l'autre, liste / révocation / renommage, « déconnecter tous les
  autres », limitation des échecs (5 / 15 min par IP et par e-mail), vérification d'origine
  (CSRF), journal d'audit. Migration `002_auth.sql`.
- **Interface** : écran de configuration / connexion, garde de session (middleware Next.js +
  vérification serveur), coque responsive — barre basse (< 768 px), rail d'icônes (tablette),
  rail avec libellés + panneau contextuel (≥ 1280 px) — 8 sections, Paramètres fonctionnels.
  Les sections des phases suivantes affichent clairement leur phase.
- **Vérification** : 20 tests `pytest` (dont 16 sur l'authentification), `next build` vert,
  parcours réel dans Chromium sur ordinateur, iPad et iPhone (configuration, navigation des
  8 sections, révocation d'un appareil depuis un autre, renommage, déconnexion, refus du
  mauvais mot de passe).
- **Limite connue** : le compteur de limitation est en mémoire (une instance) ; à déplacer en
  base si l'API tourne un jour sur plusieurs processus.
