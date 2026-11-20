-- RAPHAËL — Phase 2 : authentification (compte propriétaire, sessions, appareils)

-- Un seul compte propriétaire, garanti par la base elle-même (et non seulement par l'API) :
-- l'index unique sur une expression constante interdit une deuxième ligne, même en cas de
-- requêtes simultanées.
CREATE UNIQUE INDEX users_single_owner ON users ((true));

-- Dernière utilisation d'une session : affichée dans Paramètres › Appareils.
ALTER TABLE sessions ADD COLUMN last_seen_at timestamptz NOT NULL DEFAULT now();

CREATE INDEX devices_user_idx ON devices(user_id);
CREATE INDEX sessions_device_idx ON sessions(device_id);
