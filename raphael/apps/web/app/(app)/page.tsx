"use client";

import { RaphaelCore } from "@/components/core/RaphaelCore";
import { Composer } from "@/components/home/Composer";
import { ContextPanel } from "@/components/home/ContextPanel";
import { useSharedConnection } from "@/components/ui/ConnectionStatus";
import { useAuth } from "@/lib/auth";
import { STATE_META } from "@/lib/raphael-state";

function greeting(date: Date): string {
  const h = date.getHours();
  return h >= 5 && h < 18 ? "Bonjour" : "Bonsoir";
}

/** Écran principal : noyau (état réel de la connexion), fil de discussion, saisie.
 *  La conversation (phase 3) et la voix (phase 4) ne sont pas encore branchées : leurs
 *  contrôles sont visibles mais désactivés, avec leur phase. */
export default function Home() {
  const { me } = useAuth();
  const conn = useSharedConnection();
  const state = conn.kind === "offline" ? "offline" : "idle";
  const firstName = me.user.display_name.split(" ")[0];

  return (
    <div className="flex flex-1 xl:grid xl:grid-cols-[minmax(0,1fr)_320px]">
      <div className="mx-auto flex w-full max-w-[760px] flex-1 flex-col px-5 md:px-8">
        <section className="flex flex-col items-center gap-4 pt-8 pb-6 md:pt-12">
          <RaphaelCore state={state} className="size-40 md:size-[220px]" />
          <div className="text-center">
            <p className="font-display text-lg text-ice">
              {greeting(new Date())}, {firstName}.
            </p>
            <p className="mt-1 text-sm text-mist" aria-live="polite">
              {conn.kind === "checking" ? "Initialisation…" : STATE_META[state].hint}
            </p>
          </div>
        </section>

        <section
          aria-label="Fil de discussion"
          className="flex min-h-40 flex-1 flex-col items-center justify-center rounded-2xl border border-dashed border-line/80 bg-abyss/40 p-6 text-center"
        >
          <p className="text-sm text-mist">Aucun échange pour l&apos;instant.</p>
          <p className="mt-1 font-mono text-[11px] text-mist/70">
            La conversation écrite sera branchée en phase 3.
          </p>
        </section>

        <div className="sticky bottom-20 py-4 md:bottom-0 md:pb-6">
          <Composer />
        </div>
      </div>

      <ContextPanel />
    </div>
  );
}
