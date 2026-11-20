import type { SectionId } from "@/lib/sections";

const PATHS: Record<SectionId, React.ReactNode> = {
  home: (
    <>
      <path d="M4 11.5 12 5l8 6.5" />
      <path d="M6.5 10v9h11v-9" />
      <circle cx="12" cy="14.5" r="1.6" />
    </>
  ),
  conversation: (
    <>
      <path d="M5 6.5h14v9H10l-4 3v-3H5z" />
      <path d="M9 10.5h6M9 13h3.5" />
    </>
  ),
  memory: (
    <>
      <path d="M12 3.5 19.5 8v8L12 20.5 4.5 16V8z" />
      <path d="M12 3.5V12m0 0 7.5-4M12 12 4.5 8M12 12v8.5" />
    </>
  ),
  analysis: (
    <>
      <path d="M4.5 19.5h15" />
      <path d="M7 16v-4M11 16V8M15 16v-6M19 16V5" />
    </>
  ),
  projects: (
    <>
      <rect x="4.5" y="4.5" width="15" height="15" rx="2.5" />
      <path d="m8 12 2.5 2.5L16 9" />
    </>
  ),
  agenda: (
    <>
      <rect x="4.5" y="6" width="15" height="13.5" rx="2.5" />
      <path d="M4.5 10.5h15M9 3.5V8M15 3.5V8" />
      <circle cx="12" cy="15" r="1.2" />
    </>
  ),
  finance: (
    <>
      <circle cx="12" cy="12" r="7.5" />
      <path d="M14.5 9.2a3 3 0 1 0 0 5.6M8 11h5M8 13h5" />
    </>
  ),
  settings: (
    <>
      <circle cx="12" cy="12" r="2.6" />
      <path d="M12 3.5v2.3M12 18.2v2.3M3.5 12h2.3M18.2 12h2.3M6 6l1.6 1.6M16.4 16.4 18 18M6 18l1.6-1.6M16.4 7.6 18 6" />
    </>
  ),
};

export function SectionIcon({ id, className = "size-6" }: { id: SectionId; className?: string }) {
  return (
    <svg
      viewBox="0 0 24 24"
      className={className}
      fill="none"
      stroke="currentColor"
      strokeWidth="1.6"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      {PATHS[id]}
    </svg>
  );
}
