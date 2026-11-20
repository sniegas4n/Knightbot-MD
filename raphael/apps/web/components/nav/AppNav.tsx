"use client";

import { motion } from "framer-motion";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { Logo } from "@/components/ui/Logo";
import { SECTIONS, sectionFor } from "@/lib/sections";
import { SectionIcon } from "./SectionIcon";

/** Rail latéral : icônes seules sur tablette (768–1279 px), icônes + libellés sur ordinateur. */
export function NavRail() {
  const active = sectionFor(usePathname()).id;
  return (
    <nav
      aria-label="Navigation principale"
      className="sticky top-0 hidden h-dvh w-20 shrink-0 flex-col border-r border-line bg-abyss/80 backdrop-blur md:flex xl:w-60"
    >
      <div className="flex h-20 items-center justify-center xl:justify-start xl:px-6">
        <span className="font-display text-lg font-semibold tracking-[0.35em] text-ice xl:hidden" aria-hidden="true">
          R
        </span>
        <div className="hidden xl:block">
          <Logo compact />
        </div>
      </div>
      <ul className="flex flex-1 flex-col gap-1 px-3">
        {SECTIONS.map((s) => {
          const on = s.id === active;
          return (
            <li key={s.id} className={s.id === "settings" ? "mt-auto mb-4" : undefined}>
              <Link
                href={s.href}
                aria-current={on ? "page" : undefined}
                title={s.label}
                className={`relative flex h-12 items-center justify-center gap-3 rounded-xl transition-colors duration-200 xl:justify-start xl:px-4 ${
                  on ? "text-ice" : "text-mist hover:bg-night/60 hover:text-ice"
                }`}
              >
                {on && (
                  <motion.span
                    layoutId="rail-active"
                    className="absolute inset-0 rounded-xl border border-cyan/40 bg-cyan/10 shadow-glow"
                    transition={{ type: "spring", stiffness: 400, damping: 34 }}
                  />
                )}
                <SectionIcon id={s.id} className="relative size-6 shrink-0" />
                <span className="relative hidden text-sm xl:inline">{s.label}</span>
                {s.phase > 2 && (
                  <span className="relative ml-auto hidden font-mono text-[10px] text-mist/60 xl:inline">P{s.phase}</span>
                )}
              </Link>
            </li>
          );
        })}
      </ul>
    </nav>
  );
}

/** Barre basse des téléphones (< 768 px), au-dessus de la zone de sécurité iOS. */
export function NavBar() {
  const active = sectionFor(usePathname()).id;
  return (
    <nav
      aria-label="Navigation principale"
      className="fixed inset-x-0 bottom-0 z-30 border-t border-line bg-abyss/90 pb-[env(safe-area-inset-bottom)] backdrop-blur md:hidden"
    >
      <ul className="grid grid-cols-8">
        {SECTIONS.map((s) => {
          const on = s.id === active;
          return (
            <li key={s.id}>
              <Link
                href={s.href}
                aria-current={on ? "page" : undefined}
                aria-label={s.label}
                className={`relative flex h-16 flex-col items-center justify-center gap-1 transition-colors duration-200 ${
                  on ? "text-ice" : "text-mist"
                }`}
              >
                {on && (
                  <motion.span
                    layoutId="bar-active"
                    className="absolute top-0 h-0.5 w-8 rounded-full bg-cyan shadow-glow"
                    transition={{ type: "spring", stiffness: 400, damping: 34 }}
                  />
                )}
                <SectionIcon id={s.id} className={`size-[22px] ${on ? "text-cyan-soft" : ""}`} />
                <span className="text-[9.5px] leading-none tracking-tight">{s.short}</span>
              </Link>
            </li>
          );
        })}
      </ul>
    </nav>
  );
}
