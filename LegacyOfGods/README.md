# LEGACY OF GODS — Projet Roblox (Luau)

MMORPG anime pour Roblox. Ce dossier contient le code source complet, organisé pour être synchronisé avec **Rojo** ou copié à la main dans Roblox Studio.

- Architecture, conventions et décisions techniques : [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
- État actuel : **Phase 1 — Mission 1** (configuration, structure, personnage & déplacement, HUD).

> ⚠️ Ce code n'a **pas encore été exécuté dans Roblox Studio** ni passé dans un analyseur Luau. Il a été relu manuellement. Vos tests ci-dessous servent de première validation.

---

## Installation

### Option A — Rojo (recommandée)

1. Installer Rojo (extension VS Code « Rojo » ou `aftman`/`rokit`) et le plugin Rojo dans Studio.
2. Dans ce dossier : `rojo serve`
3. Dans Studio : plugin Rojo → **Connect**. Tout est créé automatiquement, y compris les propriétés (`StreamingEnabled`, `CharacterAutoLoads`, Shift-Lock désactivé).

Avec [Rokit](https://github.com/rojo-rbx/rokit), la version de Rojo est figée dans `rokit.toml` :

```bash
rokit install        # installe Rojo 7.7.1
rojo plugin install  # installe le plugin Rojo correspondant dans Studio
rojo serve           # puis Studio : plugin Rojo → Connect
```

### Tests automatisés par Claude (Studio MCP)

Pour que Claude lance le jeu dans Studio, lise la sortie et corrige les erreurs, il doit tourner **sur votre ordinateur** (Studio ne fonctionne pas dans un conteneur Linux) :

1. Ouvrir Claude Code sur votre machine dans ce dossier (application Claude Desktop, ou `claude remote-control` dans un terminal).
2. Activer le serveur MCP de Roblox Studio : option MCP intégrée de Studio (réglages de l'Assistant) sur les versions récentes, sinon l'installateur `studio-rust-mcp-server` de Roblox (GitHub), qui ajoute le plugin et l'enregistre auprès de Claude.
3. Vérifier avec `claude mcp list`, Studio ouvert et connecté à `rojo serve`.

### Option B — Installation manuelle dans Studio

Règle de correspondance :

| Fichier | Objet Studio | Nom |
|---------|--------------|-----|
| `X.luau` | **ModuleScript** | `X` |
| `X.server.luau` | **Script** | `X` |
| `X.client.luau` | **LocalScript** | `X` |
| `Dossier/init.luau` | le **dossier devient un ModuleScript** nommé `Dossier`, ses autres fichiers sont ses enfants | `Config` |
| dossier simple | **Folder** | même nom |

Étapes :

1. **ReplicatedStorage** → Folder `Shared`
   - ModuleScript `Config` (contenu de `Config/init.luau`), avec comme **enfants** les ModuleScripts : `Core`, `Character`, `Movement`, `Camera`, `Progression`, `Economy`, `Regions`, `Input`, `Animations`, `UI`, `Network`.
   - Folder `Modules` : ModuleScripts `Net`, `Signal`, `Maid`, `ProgressionFormulas`.
   - ⚠ Ne créez **pas** le dossier `Remotes` : le serveur le crée.
2. **ServerScriptService**
   - Script `ServerMain`
   - Folder `Services` : ModuleScripts `PlayerStateService`, `EconomyService`, `LevelService`, `ResourceService`, `CharacterService`, `MovementService`, `DebugService`
   - Folder `Modules` : ModuleScripts `RemoteGuard`, `Validate`, `Notifier`
3. **StarterPlayer > StarterPlayerScripts**
   - LocalScript `ClientMain`
   - Folder `Controllers` : ModuleScripts `InputController`, `CameraController`, `MovementController`, `HUDController`, `DebugController`
   - Folder `UI` : ModuleScripts `Create`, `Format` + Folder `Components` avec ModuleScripts `ResourceBar`, `SkillSlot`, `NotificationFeed`
4. **ServerStorage** : Folders `NPCs`, `Bosses`, `Weapons`, `Maps`, `DungeonAssets`.
5. **Workspace** : Folders `World`, `NPCs`, `Enemies`, `Bosses`, `Zones`, `Dungeons`, `SpawnLocations`.
6. **Propriétés à régler** (fenêtre Properties) :
   - `Players` → `CharacterAutoLoads` = **false**
   - `StarterPlayer` → `EnableMouseLockOption` = **false**, `CameraMaxZoomDistance` = 32, `CameraMinZoomDistance` = 6
   - `Workspace` → `StreamingEnabled` = **true**
7. Placer un **SpawnLocation** (dans `Workspace > SpawnLocations`) et un sol.

Respectez les noms **exactement** (majuscules comprises) : les scripts se trouvent par leur nom.

---

## Tests (Play Solo, puis « Start » 2 joueurs)

| # | Action | Résultat attendu |
|---|--------|------------------|
| 1 | Lancer **Play** | Sortie : `[ServerMain] LEGACY OF GODS v0.1.0 — démarrage`, puis `7 service(s) démarré(s)`, puis `[DebugService] Outils de debug ACTIFS`. Aucune erreur rouge. |
| 2 | Observer l'apparition | Le personnage apparaît une fois. Le HUD glisse depuis les bords (panneaux gauche, droite, bas). La barre de vie Roblox par défaut a disparu. |
| 3 | Explorer → `ReplicatedStorage > Remotes` | Contient `Movement_RequestSprint`, `Movement_RequestDodge`, `UI_Notify`, `Debug_Command`. |
| 4 | Maintenir **Shift** en avançant | Vitesse ×1,6, FOV s'élargit, barre ENDURANCE descend. Relâcher : vitesse normale, régénération après ~1 s. |
| 5 | Maintenir Shift **sans bouger** | L'endurance ne baisse pas. |
| 6 | Sprinter jusqu'à 0 | Le sprint s'arrête tout seul (serveur). |
| 7 | **Q** en avançant / à l'arrêt | Dash vers l'avant / pas en arrière (~14 studs). Case Q : voile de recharge 0,8 s. Endurance −25. |
| 8 | Spammer **Q** | Une esquive par 0,8 s maximum. Endurance < 25 : barre qui tremble + « Endurance insuffisante ». |
| 9 | Q en sautant | Refusé (`AllowInAir = false`). |
| 10 | Pendant une esquive, Explorer → votre personnage → Attributs | `Invulnerable` passe à `true` ≈ 0,25 s. |
| 11 | **F6** (ou chat `/xp 250`) | Barre d'XP qui se remplit. Assez d'XP : bannière « NIVEAU 2 ! » + notification. |
| 12 | Chat `/xp 100000` | Plusieurs niveaux d'un coup, `StatPoints` (attribut Player) = 3 × niveaux gagnés. |
| 13 | `/level 500` puis F6 | Barre pleine « NIVEAU MAXIMUM », aucun gain. |
| 14 | **F7** / `/crystals 50` / `/shards 5` | Monnaies mises à jour (format compact : 1.5K, 2M…). |
| 15 | **F8** ×5 | Vie qui baisse avec traînée blanche. À 0 : mort, réapparition après 5 s, barres pleines. |
| 16 | **F9** (étourdissement 2 s) | Impossible de bouger, de sprinter ou d'esquiver, puis retour à la normale. |
| 17 | Device Emulator (téléphone, paysage) | Boutons tactiles « Sprint » (bascule) et « Esquive » ; HUD lisible, sans chevauchement ; touches clavier masquées. |
| 18 | Manette (si disponible) | L3 = sprint (bascule), B = esquive. |
| 19 | Test → Clients and Servers → 2 joueurs | Chaque joueur a son HUD et ses valeurs ; le sprint de l'un n'affecte pas l'autre. |
| 20 | Taper « q » dans le chat | Aucune esquive. |

**Test de sécurité (vue Serveur → barre de commande, pendant le Play)** : vous pouvez simuler un client malveillant côté client avec la barre de commande en vue *Client* :

```lua
local r = game.ReplicatedStorage.Remotes.Movement_RequestDodge
for i = 1, 50 do r:FireServer(Vector3.new(0/0, 0, 1)) end
```

Attendu : avertissements `[RemoteGuard] … direction invalide` puis `limite de fréquence dépassée`, aucune erreur, aucune esquive accordée.

---

## Erreurs possibles

| Symptôme | Cause probable | Solution |
|----------|----------------|----------|
| `Infinite yield possible on 'ReplicatedStorage:WaitForChild("Shared")'` | Dossier mal nommé | Vérifier `Shared` (S majuscule). |
| `[ServerMain] Service introuvable : X` | ModuleScript absent ou mal nommé | Nom exact dans `Services`. |
| `attempt to index nil with 'Core'` | Les sous-modules de `Config` ne sont pas ses **enfants** | Glisser `Core`, `Character`… à l'intérieur du ModuleScript `Config`. |
| `[Net] Remote 'X' non reçu après 20s` | `ServerMain` n'a pas démarré (erreur plus haut) | Lire la première erreur serveur. |
| Le personnage n'apparaît jamais | `PlayerStateService` en erreur | Corriger l'erreur affichée ; `CharacterAutoLoads=false` attend le profil. |
| Le personnage apparaît deux fois / HUD dupliqué | `CharacterAutoLoads` resté à true | Mettre `Players.CharacterAutoLoads = false` dans Properties. |
| Shift active le Shift-Lock | `EnableMouseLockOption` resté à true | Le régler à false dans StarterPlayer. |
| Le dash ne bouge pas | `HumanoidRootPart` ancré, ou personnage personnalisé sans `RootAttachment` | Désancrer ; le code crée une attache de secours. |
| Commandes de chat sans effet | Selon la configuration TextChatService, `Player.Chatted` peut ne pas recevoir le message | Utiliser les touches **F6–F9**. |
| Rien avec F6–F9 | Hors Studio (normal) ou `Config.Core.Debug.Enabled = false` | — |
| Animation d'esquive absente | IDs vides dans `Config.Animations` (normal) | Créer les animations puis renseigner `rbxassetid://…`. |
| La vie remonte seule | Script `Health` par défaut de Roblox (régénération 1 %/s) | Normal en Phase 1 ; remplacé par la régénération serveur en Phase 2. |

---

## Critères de validation de la Mission 1

- [ ] Aucune erreur rouge dans la sortie (serveur et client) au lancement ni après 5 minutes.
- [ ] Les 4 Remotes sont créés automatiquement ; aucun n'a été créé à la main.
- [ ] Le personnage n'apparaît qu'une fois, après le chargement du profil, et réapparaît 5 s après la mort.
- [ ] Sprint : vitesse, FOV et endurance cohérents ; arrêt automatique à 0 ; aucune consommation à l'arrêt.
- [ ] Esquive : cooldown respecté (client et serveur), coût en endurance, i-frames visibles dans les attributs.
- [ ] HUD : vie, énergie, endurance, niveau, XP, 3 monnaies, mini-carte provisoire, quêtes, barre Q/Z/X/C/V.
- [ ] HUD responsive : PC 1080p, tablette et téléphone (Device Emulator) sans chevauchement.
- [ ] Mobile : boutons Sprint et Esquive fonctionnels.
- [ ] Spam de Remotes sans effet ni erreur côté serveur.
- [ ] Toute valeur d'équilibrage se modifie dans `Shared > Config` uniquement (ex. passer `Dodge.Cooldown` à 2 change le client ET le serveur).

Une fois ces points validés, prochaine étape : **Phase 1-B — combat de base** (attaques légère/lourde, combos, hitboxes serveur, parade, étourdissement), puis **Phase 2 — sauvegarde DataStore**.
