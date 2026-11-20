"use client";

import { AppShell } from "@/components/shell/AppShell";
import { Splash } from "@/components/shell/Splash";
import { ConnectionProvider } from "@/components/ui/ConnectionStatus";
import { AuthGate } from "@/lib/auth";

/** Toutes les sections de l'application : accessibles uniquement avec une session valide. */
export default function AppLayout({ children }: { children: React.ReactNode }) {
  return (
    <AuthGate
      fallback={(s) =>
        s.kind === "loading" ? <Splash /> : <Splash message={`Connexion impossible : ${s.message}`} onRetry={s.retry} />
      }
    >
      <ConnectionProvider>
        <AppShell>{children}</AppShell>
      </ConnectionProvider>
    </AuthGate>
  );
}
