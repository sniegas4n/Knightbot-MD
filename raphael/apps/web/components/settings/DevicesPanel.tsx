"use client";

import { useRouter } from "next/navigation";
import { useCallback, useEffect, useState } from "react";
import { ApiError, auth, type SessionInfo } from "@/lib/api";
import { useAuth } from "@/lib/auth";
import { PLATFORM_LABEL } from "@/lib/device";

const rtf = new Intl.RelativeTimeFormat("fr", { numeric: "auto" });

function relative(iso: string): string {
  const diff = (new Date(iso).getTime() - Date.now()) / 1000;
  const abs = Math.abs(diff);
  if (abs < 60) return "à l'instant";
  if (abs < 3600) return rtf.format(Math.round(diff / 60), "minute");
  if (abs < 86400) return rtf.format(Math.round(diff / 3600), "hour");
  return rtf.format(Math.round(diff / 86400), "day");
}

/** Liste réelle des sessions actives, avec révocation et renommage d'appareil. */
export function DevicesPanel() {
  const router = useRouter();
  const { refresh } = useAuth();
  const [sessions, setSessions] = useState<SessionInfo[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [confirming, setConfirming] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [editing, setEditing] = useState<{ id: string; name: string } | null>(null);

  const handle = useCallback(
    (e: unknown) => {
      if (e instanceof ApiError && e.status === 401) {
        router.replace("/login"); // session révoquée depuis un autre appareil
        return;
      }
      setError(e instanceof Error ? e.message : "Erreur inconnue.");
    },
    [router],
  );

  const load = useCallback(async () => {
    try {
      setSessions(await auth.sessions());
      setError(null);
    } catch (e) {
      handle(e);
    }
  }, [handle]);

  useEffect(() => {
    void load();
  }, [load]);

  const run = async (fn: () => Promise<unknown>) => {
    setBusy(true);
    try {
      await fn();
      await load();
    } catch (e) {
      handle(e);
    } finally {
      setBusy(false);
      setConfirming(null);
    }
  };

  const saveName = async () => {
    if (!editing) return;
    const { id, name } = editing;
    if (!name.trim()) return;
    await run(async () => {
      await auth.renameDevice(id, name);
      setEditing(null);
      await refresh();
    });
  };

  if (sessions === null && !error) return <p className="text-sm text-mist">Chargement…</p>;

  const others = sessions?.filter((s) => !s.current).length ?? 0;

  return (
    <div>
      {error && (
        <p role="alert" className="mb-3 rounded-lg border border-danger/40 bg-danger/10 px-3 py-2 text-sm text-danger">
          {error}
        </p>
      )}
      <ul className="divide-y divide-line/60">
        {sessions?.map((s) => (
          <li key={s.id} className="flex flex-col gap-3 py-3 sm:flex-row sm:items-center sm:justify-between">
            <div className="min-w-0">
              {editing && s.device && editing.id === s.device.id ? (
                <form
                  className="flex items-center gap-2"
                  onSubmit={(e) => {
                    e.preventDefault();
                    void saveName();
                  }}
                >
                  <label htmlFor={`name-${s.id}`} className="sr-only">
                    Nom de l&apos;appareil
                  </label>
                  <input
                    id={`name-${s.id}`}
                    autoFocus
                    maxLength={60}
                    value={editing.name}
                    onChange={(e) => setEditing({ ...editing, name: e.target.value })}
                    className="min-w-0 rounded-lg border border-line bg-night px-2 py-1 text-sm text-ice"
                  />
                  <button type="submit" disabled={busy} className="text-xs text-cyan-soft hover:text-ice">
                    Enregistrer
                  </button>
                  <button type="button" onClick={() => setEditing(null)} className="text-xs text-mist hover:text-ice">
                    Annuler
                  </button>
                </form>
              ) : (
                <p className="flex flex-wrap items-center gap-2 text-sm text-ice">
                  <span className="truncate">{s.device?.name ?? "Appareil inconnu"}</span>
                  {s.current && (
                    <span className="rounded-full border border-cyan/40 bg-cyan/10 px-2 py-0.5 font-mono text-[10px] uppercase tracking-wider text-cyan-soft">
                      Cet appareil
                    </span>
                  )}
                </p>
              )}
              <p className="mt-0.5 font-mono text-[11px] text-mist">
                {s.device ? PLATFORM_LABEL[s.device.platform] : "—"} · {s.ip ?? "IP inconnue"} · actif{" "}
                {relative(s.last_seen_at)}
              </p>
            </div>
            <div className="flex shrink-0 items-center gap-2">
              {s.device && !editing && (
                <button
                  type="button"
                  onClick={() => setEditing({ id: s.device!.id, name: s.device!.name })}
                  className="rounded-lg border border-line px-3 py-1.5 text-xs text-mist transition-colors hover:text-ice"
                >
                  Renommer
                </button>
              )}
              {!s.current &&
                (confirming === s.id ? (
                  <>
                    <button
                      type="button"
                      disabled={busy}
                      onClick={() => void run(() => auth.revoke(s.id))}
                      className="rounded-lg bg-danger px-3 py-1.5 text-xs font-medium text-void"
                    >
                      Confirmer
                    </button>
                    <button
                      type="button"
                      onClick={() => setConfirming(null)}
                      className="rounded-lg border border-line px-3 py-1.5 text-xs text-mist"
                    >
                      Annuler
                    </button>
                  </>
                ) : (
                  <button
                    type="button"
                    onClick={() => setConfirming(s.id)}
                    className="rounded-lg border border-danger/40 px-3 py-1.5 text-xs text-danger transition-colors hover:bg-danger/10"
                  >
                    Déconnecter
                  </button>
                ))}
            </div>
          </li>
        ))}
      </ul>
      {others > 0 && (
        <div className="mt-4 border-t border-line/60 pt-4">
          {confirming === "others" ? (
            <div className="flex flex-wrap items-center gap-2 text-sm">
              <span className="text-warn">
                Déconnecter {others} autre{others > 1 ? "s" : ""} session{others > 1 ? "s" : ""} ?
              </span>
              <button
                type="button"
                disabled={busy}
                onClick={() => void run(() => auth.revokeOthers())}
                className="rounded-lg bg-warn px-3 py-1.5 text-xs font-medium text-void"
              >
                Confirmer
              </button>
              <button
                type="button"
                onClick={() => setConfirming(null)}
                className="rounded-lg border border-line px-3 py-1.5 text-xs text-mist"
              >
                Annuler
              </button>
            </div>
          ) : (
            <button
              type="button"
              onClick={() => setConfirming("others")}
              className="text-sm text-mist underline-offset-4 hover:text-ice hover:underline"
            >
              Déconnecter tous les autres appareils
            </button>
          )}
        </div>
      )}
    </div>
  );
}
