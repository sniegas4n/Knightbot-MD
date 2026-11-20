/** Client de l'API. Les appels passent par la même origine (/v1/*, relayé par Next.js vers
 *  FastAPI). Aucune clé secrète côté client ; la session est un cookie httpOnly que le
 *  JavaScript ne peut pas lire. */
export const API_URL = process.env.NEXT_PUBLIC_API_URL ?? "";

export class ApiError extends Error {
  constructor(
    public status: number,
    message: string,
    public retryAfter: number | null = null,
  ) {
    super(message);
  }
}

/** Erreur réseau : le serveur n'a pas répondu (distincte d'une réponse d'erreur). */
export class NetworkError extends Error {}

function detailOf(body: unknown, status: number): string {
  if (body && typeof body === "object" && "detail" in body) {
    const d = (body as { detail: unknown }).detail;
    if (typeof d === "string") return d;
    if (Array.isArray(d) && d[0] && typeof d[0] === "object" && "msg" in d[0]) {
      return String((d[0] as { msg: unknown }).msg);
    }
  }
  return status >= 500 ? "Le serveur a rencontré une erreur." : `Erreur ${status}`;
}

export async function api<T>(path: string, init: RequestInit & { json?: unknown } = {}): Promise<T> {
  const { json, headers, ...rest } = init;
  let res: Response;
  try {
    res = await fetch(`${API_URL}${path}`, {
      credentials: "same-origin",
      cache: "no-store",
      ...rest,
      headers: json !== undefined ? { "Content-Type": "application/json", ...headers } : headers,
      body: json !== undefined ? JSON.stringify(json) : rest.body,
    });
  } catch (e) {
    if (e instanceof DOMException && e.name === "AbortError") throw e;
    throw new NetworkError("Serveur injoignable.");
  }
  if (res.status === 204) return undefined as T;
  const body: unknown = await res.json().catch(() => null);
  if (!res.ok) {
    const ra = res.headers.get("retry-after");
    throw new ApiError(res.status, detailOf(body, res.status), ra ? Number(ra) : null);
  }
  return body as T;
}

// ─── Santé ────────────────────────────────────────────────────────────────
export type Health = {
  status: "ok" | "degraded";
  version: string;
  database: { connected: boolean; pgvector: boolean; schema_version: number | null };
};

export const fetchHealth = (signal?: AbortSignal) => api<Health>("/v1/health", { signal });

// ─── Authentification ─────────────────────────────────────────────────────
export type Platform = "ios" | "ipados" | "android" | "windows" | "macos" | "linux" | "web";

export type Device = { id: string; name: string; platform: Platform };
export type User = { id: string; email: string; display_name: string; locale: string; timezone: string };
export type Me = { user: User; session_id: string; device: Device | null };
export type AuthStatus = { setup_required: boolean; setup_token_required: boolean };
export type SessionInfo = {
  id: string;
  device: Device | null;
  ip: string | null;
  user_agent: string | null;
  created_at: string;
  last_seen_at: string;
  expires_at: string;
  current: boolean;
};

type DeviceInfo = { device_name: string; platform: Platform };

export const auth = {
  status: () => api<AuthStatus>("/v1/auth/status"),
  me: () => api<Me>("/v1/auth/me"),
  setup: (body: DeviceInfo & { email: string; display_name: string; password: string; setup_token?: string }) =>
    api<Me>("/v1/auth/setup", { method: "POST", json: body }),
  login: (body: DeviceInfo & { email: string; password: string }) =>
    api<Me>("/v1/auth/login", { method: "POST", json: body }),
  logout: () => api<void>("/v1/auth/logout", { method: "POST" }),
  sessions: () => api<SessionInfo[]>("/v1/auth/sessions"),
  revoke: (id: string) => api<void>(`/v1/auth/sessions/${id}`, { method: "DELETE" }),
  revokeOthers: () => api<{ revoked: number }>("/v1/auth/sessions/revoke-others", { method: "POST" }),
  renameDevice: (id: string, name: string) =>
    api<Device>(`/v1/auth/devices/${id}`, { method: "PATCH", json: { name } }),
};
