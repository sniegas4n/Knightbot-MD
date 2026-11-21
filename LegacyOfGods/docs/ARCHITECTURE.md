# LEGACY OF GODS — Architecture technique

> Document de référence du directeur technique. Toute nouvelle fonctionnalité doit respecter ces règles.

## 1. Analyse du projet & décisions structurantes

| # | Constat | Décision |
|---|---------|----------|
| 1 | MMORPG avec économie, trading et prestige : la **duplication d'objets** est le risque n°1. | Le serveur est la seule source de vérité. Phase 2 : DataStore avec **verrou de session** (`UpdateAsync`) pour qu'un profil ne puisse jamais être ouvert sur deux serveurs à la fois. Le trading s'appuiera dessus. |
| 2 | Donjons (solo → raid 10) et PvP classé ne peuvent pas cohabiter proprement avec le monde ouvert sur un même serveur. | **Univers multi-places** : `Monde` (place principale), `Donjon` et `Arène` (places séparées, serveurs réservés via `TeleportService:ReserveServer`). Matchmaking inter-serveurs via `MemoryStoreService`. |
| 3 | Guildes, classements et saisons sont **inter-serveurs**. | Données de guilde dans un DataStore dédié (`UpdateAsync` uniquement), classements via `OrderedDataStore`, diffusion temps réel via `MessagingService`. |
| 4 | Shift = sprint entre en conflit avec le **Shift-Lock** natif de Roblox. | Shift-Lock désactivé (`StarterPlayer.EnableMouseLockOption = false`, `Player.DevEnableMouseLock = false`). Un verrouillage de cible (lock-on) dédié au combat viendra en Phase 1-B. |
| 5 | Touches Z / Q (compétence 1 / esquive) : sur clavier **AZERTY** elles correspondent aux touches de déplacement ZQSD. | Toutes les touches sont dans `Config.Input` ; un menu de remappage est prévu (Phase 6). À tester avec des joueurs AZERTY dès la Phase 1-B. |
| 6 | Les données du profil se chargent de façon asynchrone. Faire apparaître le personnage avant risque d'exposer un joueur « vide ». | `Players.CharacterAutoLoads = false`. Le personnage n'apparaît **qu'après** `PlayerReady`. |
| 7 | La structure proposée met le HUD dans `StarterGui/HUD`. | Le HUD est **généré en code** (`HUDController` + composants). Avantages : versionnable sous Git, aucune GUI à recréer à la main, thème centralisé dans `Config.UI`. Les menus (Inventaire, Guilde…) suivront le même modèle. |
| 8 | Raretés de clans : si un « reroll » de clan est vendu en Robux, c'est un **objet aléatoire payant** (règles Roblox : affichage obligatoire des probabilités, restrictions selon les pays). | Recommandation : rerolls obtenables en jeu uniquement, ou vente en Robux avec affichage des probabilités et vérification de `PolicyService`. À trancher avant la Phase 3. |
| 9 | Déplacements : sur Roblox, le client possède physiquement son personnage. | Le serveur valide ce qui compte (endurance, cooldown, i-frames, dégâts). Un contrôle anti-vitesse/téléportation côté serveur sera ajouté (Phase 1-B). |
| 10 | Niveau max 500 + prestige : risque d'écart irréversible. | Courbe d'XP et bonus de prestige **plafonnés** dans `Config.Progression` ; simulation de la courbe avant la Phase 5. |

## 2. Arborescence

```
ReplicatedStorage
├── Shared                     (Folder)
│   ├── Config                 (ModuleScript)  ← point d'entrée unique de la configuration
│   │   ├── Core / Character / Movement / Camera / Progression
│   │   └── Economy / Regions / Input / Animations / UI / Network   (ModuleScripts enfants)
│   ├── Modules                (Folder)
│   │   ├── Net                (ModuleScript)  accès aux Remotes
│   │   ├── Signal             (ModuleScript)  évènements internes
│   │   ├── Maid               (ModuleScript)  nettoyage
│   │   └── ProgressionFormulas(ModuleScript)  formules partagées
│   ├── ItemDefinitions        (Phase 3)
│   ├── AbilityDefinitions     (Phase 3)
│   ├── ClanDefinitions        (Phase 3)
│   └── ArtifactDefinitions    (Phase 3)
└── Remotes                    (Folder)  ← CRÉÉ AUTOMATIQUEMENT par le serveur

ServerScriptService
├── ServerMain                 (Script)   point d'entrée serveur
├── Services                   (Folder)
│   ├── PlayerStateService     → deviendra PlayerDataService (Phase 2)
│   ├── EconomyService
│   ├── LevelService
│   ├── ResourceService
│   ├── CharacterService
│   ├── MovementService
│   └── DebugService
└── Modules                    (Folder)
    ├── RemoteGuard            limite de fréquence + pcall
    ├── Validate               validation des arguments
    └── Notifier               notifications HUD

ServerStorage : NPCs, Bosses, Weapons, Maps, DungeonAssets (Folders)

StarterPlayer
└── StarterPlayerScripts
    ├── ClientMain             (LocalScript) point d'entrée client
    ├── Controllers            (Folder)
    │   ├── InputController / CameraController / MovementController
    │   └── HUDController / DebugController
    └── UI                     (Folder)
        ├── Create / Format
        └── Components : ResourceBar, SkillSlot, NotificationFeed

Workspace : World, NPCs, Enemies, Bosses, Zones, Dungeons, SpawnLocations (Folders)
```

## 3. Cycle de vie (serveur et client)

```
ServerMain / ClientMain
  1. require() de chaque module dans LOAD_ORDER
  2. module:Init(registry)   → récupère ses dépendances, connecte les Signals. NE DOIT PAS ATTENDRE.
  3. module:Start()          → connexions Roblox, Remotes, boucles. Chaque Start dans son propre thread.
```

Les services ne se `require` **pas** entre eux : ils reçoivent la table `services` dans `Init`. Cela supprime les dépendances circulaires et rend l'ordre de démarrage explicite.

### Graphe des dépendances (Phase 1)

```
PlayerStateService ──PlayerReady/PlayerLeaving──► EconomyService, LevelService, ResourceService, CharacterService, MovementService, DebugService
CharacterService   ──CharacterSpawned/Died─────► ResourceService (remplissage), MovementService (arrêt sprint)
ResourceService    ──Ticked(dt)────────────────► MovementService (consommation du sprint)
MovementService    ──RefreshWalkSpeed()────────► CharacterService (vitesse calculée en un seul endroit)
```

## 4. Flux réseau

| Remote | Sens | Arguments | Validation serveur |
|--------|------|-----------|--------------------|
| `Movement_RequestSprint` | C → S | `active: boolean` | type, vivant, non étourdi, endurance ≥ seuil, 12 appels/s max |
| `Movement_RequestDodge` | C → S | `direction: Vector3` | type, NaN/inf, magnitude ≤ 10, cooldown, endurance, 5 appels/s max |
| `UI_Notify` | S → C | `{ Text, Kind }` | — (le client vérifie le format) |
| `Debug_Command` | C → S | `command: string, value: number?` | **n'existe que dans Studio** |

État répliqué sans Remote : **attributs** (lecture seule pour le client, car un attribut modifié par le client ne se réplique pas vers le serveur).

| Objet | Attributs |
|-------|-----------|
| `Player` | `DataLoaded`, `Level`, `Experience`, `ExperienceRequired`, `StatPoints`, `Gold`, `Crystals`, `DivineShards`, `Stamina`, `MaxStamina`, `Energy`, `MaxEnergy`, `IsSprinting`, `RegionId` (Phase 4) |
| `Character` (Model) | `Invulnerable`, `Stunned` |

## 5. Conventions de nommage

| Élément | Convention | Exemple |
|---------|-----------|---------|
| Service serveur | `PascalCase` + `Service` | `MovementService` |
| Contrôleur client | `PascalCase` + `Controller` | `HUDController` |
| Module utilitaire | `PascalCase` | `RemoteGuard`, `ProgressionFormulas` |
| Fichiers (Rojo) | `Nom.luau` = ModuleScript, `Nom.server.luau` = Script, `Nom.client.luau` = LocalScript, `init.luau` = le dossier devient un ModuleScript | `ServerMain.server.luau` |
| Remotes | `Domaine_Action` ; requêtes client : `Domaine_RequestAction` | `Movement_RequestDodge`, `UI_Notify` |
| Attributs | `PascalCase` ; publics sur `Player`, états de combat sur le `Character` | `IsSprinting`, `Stunned` |
| Clés de config | `PascalCase`, regroupées par domaine | `Config.Movement.Dodge.Cooldown` |
| Constantes locales | `UPPER_SNAKE_CASE` | `TICK_INTERVAL` |
| Variables / fonctions locales | `camelCase` | `lastDodgeTime`, `onCharacterAdded` |
| Méthodes publiques | `PascalCase` avec `:` | `ResourceService:TrySpend()` |
| Signals | `PascalCase` au passé ou état | `PlayerReady`, `Dodged`, `LevelUp` |
| Identifiants de contenu (sauvegardés) | `snake_case` préfixé par le type, **jamais renommés** | `region_aether`, `artifact_dragon_heart`, `clan_shadow` |
| Tags CollectionService | `PascalCase` | `PlayerCharacter`, `Enemy`, `Interactable` |
| Dossiers Workspace / ServerStorage | `PascalCase` pluriel | `Enemies`, `SpawnLocations` |
| Langue | Code et identifiants en **anglais**, textes affichés et commentaires en **français** | — |

## 6. Règles de sécurité permanentes

1. Le client **demande**, le serveur **décide**. Aucun dégât, gain d'XP, monnaie ou objet n'est accepté depuis un argument client.
2. Tout Remote client → serveur passe par `RemoteGuard.OnServerEvent` (limite de fréquence + `pcall`).
3. Tout argument est validé avec `Validate` (type, NaN, infini, bornes, longueur).
4. Une seule source d'écriture par donnée (ex. seul `EconomyService` modifie les monnaies).
5. Les outils de debug vérifient `RunService:IsStudio()` **côté serveur**.
6. `RemoteFunction` uniquement si une réponse est indispensable, jamais de `InvokeClient`.
