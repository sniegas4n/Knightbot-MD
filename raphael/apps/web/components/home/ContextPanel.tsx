"use client";

import Link from "next/link";
import { useAuth } from "@/lib/auth";
import { PLATFORM_LABEL } from "@/lib/device";

function Card({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section className="rounded-2xl border border-line bg-abyss/70 p-4">
      <h2 className="font-mono text-[11px] uppercase tracking-wider text-mist">{title}</h2>
      <div className="mt-2 text-sm">{children}</div>
    </section>
  );
}

/** Panneau contextuel (≥ 1280 px). */
export function ContextPanel() {
  const { me } = useAuth();
  return (
    <aside aria-label="Contexte" className="hidden flex-col gap-4 border-l border-line/60 p-6 xl:flex">
      <Card title="Cet appareil">
        {me.device ? (
          <>
            <p className="text-ice">{me.device.name}</p>
            <p className="font-mono text-[11px] text-mist">{PLATFORM_LABEL[me.device.platform]}</p>
          </>
        ) : (
          <p className="text-mist">Appareil non identifié.</p>
        )}
        <Link href="/parametres" className="mt-2 inline-block font-mono text-[11px] text-cyan-soft hover:text-ice">
          Gérer les appareils →
        </Link>
      </Card>
      <Card title="Actions en attente">
        <p className="text-mist">Aucune.</p>
        <p className="mt-1 font-mono text-[11px] text-mist/70">File de confirmation : phase 3.</p>
      </Card>
      <Card title="Souvenirs utilisés">
        <p className="text-mist">Aucun.</p>
        <p className="mt-1 font-mono text-[11px] text-mist/70">Mémoire persistante : phase 5.</p>
      </Card>
    </aside>
  );
}
