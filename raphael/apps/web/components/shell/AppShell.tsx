"use client";

import { usePathname } from "next/navigation";
import { NavBar, NavRail } from "@/components/nav/AppNav";
import { ConnectionStatus, useSharedConnection } from "@/components/ui/ConnectionStatus";
import { Logo } from "@/components/ui/Logo";
import { sectionFor } from "@/lib/sections";

export function AppShell({ children }: { children: React.ReactNode }) {
  const section = sectionFor(usePathname());
  const conn = useSharedConnection();

  return (
    <div className="flex min-h-dvh">
      <NavRail />
      <div className="flex min-w-0 flex-1 flex-col">
        <header className="sticky top-0 z-20 flex h-16 items-center justify-between gap-4 border-b border-line/60 bg-void/70 px-5 backdrop-blur md:h-20 md:px-8">
          <div className="md:hidden">
            <Logo compact />
          </div>
          <h1 className="hidden font-display text-xl font-semibold md:block">{section.label}</h1>
          <ConnectionStatus conn={conn} />
        </header>
        {/* pb : place pour la barre de navigation basse sur téléphone. */}
        <main className="flex flex-1 flex-col pb-20 md:pb-0">{children}</main>
      </div>
      <NavBar />
    </div>
  );
}
