import { SectionIcon } from "@/components/nav/SectionIcon";
import { SECTIONS, type SectionId } from "@/lib/sections";

/** Section pas encore construite : on l'annonce clairement, avec sa phase. Rien n'est simulé. */
export function SectionPlaceholder({ id }: { id: SectionId }) {
  const s = SECTIONS.find((x) => x.id === id)!;
  return (
    <div className="flex flex-1 items-center justify-center px-5 py-10 md:px-8">
      <div className="w-full max-w-md rounded-2xl border border-line bg-abyss/70 p-8 text-center">
        <div className="mx-auto grid size-14 place-items-center rounded-2xl border border-line bg-night text-cyan-soft">
          <SectionIcon id={s.id} className="size-7" />
        </div>
        <h2 className="mt-5 font-display text-xl font-semibold md:hidden">{s.label}</h2>
        <p className="mt-3 text-sm text-mist md:mt-5">{s.summary}</p>
        <p className="mt-6 inline-flex items-center gap-2 rounded-full border border-line px-3 py-1 font-mono text-[11px] uppercase tracking-wider text-mist">
          <span className="size-1.5 rounded-full bg-warn" aria-hidden="true" />
          Disponible en phase {s.phase}
        </p>
      </div>
    </div>
  );
}
