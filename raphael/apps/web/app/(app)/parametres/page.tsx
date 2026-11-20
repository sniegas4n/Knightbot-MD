"use client";

import { DevicesPanel } from "@/components/settings/DevicesPanel";
import { useAuth } from "@/lib/auth";

function Panel({ title, children, note }: { title: string; children: React.ReactNode; note?: string }) {
  return (
    <section className="rounded-2xl border border-line bg-abyss/70 p-5 md:p-6">
      <div className="flex items-baseline justify-between gap-3">
        <h2 className="font-display text-base font-semibold">{title}</h2>
        {note && <span className="font-mono text-[11px] text-mist/70">{note}</span>}
      </div>
      <div className="mt-4">{children}</div>
    </section>
  );
}

function Row({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex flex-col gap-0.5 py-2 sm:flex-row sm:items-baseline sm:justify-between">
      <dt className="text-sm text-mist">{label}</dt>
      <dd className="text-sm break-all text-ice">{value}</dd>
    </div>
  );
}

export default function SettingsPage() {
  const { me, logout } = useAuth();
  return (
    <div className="mx-auto flex w-full max-w-3xl flex-col gap-5 px-5 py-6 md:px-8 md:py-8">
      <h2 className="font-display text-xl font-semibold md:hidden">Paramètres</h2>

      <Panel title="Profil">
        <dl className="divide-y divide-line/60">
          <Row label="Nom" value={me.user.display_name} />
          <Row label="E-mail" value={me.user.email} />
          <Row label="Langue" value={me.user.locale} />
          <Row label="Fuseau horaire" value={me.user.timezone} />
        </dl>
      </Panel>

      <Panel title="Appareils et sessions">
        <DevicesPanel />
      </Panel>

      <Panel title="Sécurité" note="phase 8">
        <ul className="space-y-3 text-sm">
          <li className="flex items-center justify-between gap-3">
            <span className="text-mist">Face ID / Touch ID / Windows Hello (passkeys)</span>
            <button type="button" disabled className="rounded-lg border border-line px-3 py-1.5 text-xs text-mist opacity-60">
              Bientôt
            </button>
          </li>
          <li className="flex items-center justify-between gap-3">
            <span className="text-mist">Exporter ou supprimer toutes mes données</span>
            <button type="button" disabled className="rounded-lg border border-line px-3 py-1.5 text-xs text-mist opacity-60">
              Bientôt
            </button>
          </li>
        </ul>
      </Panel>

      <button
        type="button"
        onClick={() => void logout()}
        className="self-start rounded-lg border border-danger/50 px-4 py-2 text-sm text-danger transition-colors hover:bg-danger/10"
      >
        Se déconnecter de cet appareil
      </button>
    </div>
  );
}
