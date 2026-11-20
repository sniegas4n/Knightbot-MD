"use client";

import { usePathname, useRouter } from "next/navigation";
import { createContext, useCallback, useContext, useEffect, useState } from "react";
import { ApiError, auth, type Me } from "./api";

type AuthState =
  | { kind: "loading" }
  | { kind: "authenticated"; me: Me }
  | { kind: "unreachable"; message: string };

type AuthValue = {
  me: Me;
  refresh: () => Promise<void>;
  logout: () => Promise<void>;
};

const AuthContext = createContext<AuthValue | null>(null);

/** Compte connecté. Utilisable uniquement sous <AuthGate>. */
export function useAuth(): AuthValue {
  const v = useContext(AuthContext);
  if (!v) throw new Error("useAuth() hors de <AuthGate>");
  return v;
}

export function loginHref(pathname: string): string {
  return pathname && pathname !== "/" ? `/login?next=${encodeURIComponent(pathname)}` : "/login";
}

/** Vérifie la session auprès du serveur avant d'afficher l'application.
 *  401 → écran de connexion ; serveur injoignable → écran d'erreur avec nouvel essai. */
export function AuthGate({
  children,
  fallback,
}: {
  children: React.ReactNode;
  fallback: (state: { kind: "loading" } | { kind: "unreachable"; message: string; retry: () => void }) => React.ReactNode;
}) {
  const router = useRouter();
  const pathname = usePathname();
  const [state, setState] = useState<AuthState>({ kind: "loading" });

  const load = useCallback(async () => {
    try {
      setState({ kind: "authenticated", me: await auth.me() });
    } catch (e) {
      if (e instanceof ApiError && e.status === 401) {
        router.replace(loginHref(pathname));
        return;
      }
      setState({ kind: "unreachable", message: e instanceof Error ? e.message : "Erreur inconnue." });
    }
    // pathname volontairement absent : la vérification se fait au chargement, pas à chaque page.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [router]);

  useEffect(() => {
    void load();
  }, [load]);

  const logout = useCallback(async () => {
    try {
      await auth.logout();
    } finally {
      router.replace("/login");
    }
  }, [router]);

  if (state.kind === "loading") return <>{fallback({ kind: "loading" })}</>;
  if (state.kind === "unreachable") {
    return (
      <>
        {fallback({
          kind: "unreachable",
          message: state.message,
          retry: () => {
            setState({ kind: "loading" });
            void load();
          },
        })}
      </>
    );
  }
  return (
    <AuthContext.Provider value={{ me: state.me, refresh: load, logout }}>{children}</AuthContext.Provider>
  );
}
