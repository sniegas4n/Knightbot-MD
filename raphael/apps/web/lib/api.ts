/** Client minimal de l'API. Aucune clé secrète côté client : l'authentification se fera par
 *  cookie httpOnly (Phase 2), d'où credentials: "include". */
export const API_URL = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:8000";

export type Health = {
  status: "ok" | "degraded";
  version: string;
  database: { connected: boolean; pgvector: boolean; schema_version: number | null };
};

export async function fetchHealth(signal?: AbortSignal): Promise<Health> {
  const res = await fetch(`${API_URL}/v1/health`, { signal, credentials: "include", cache: "no-store" });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return (await res.json()) as Health;
}
