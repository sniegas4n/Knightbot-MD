/** Les 8 sections de RAPHAËL. `phase` indique la phase où la section devient fonctionnelle. */
export type SectionId =
  | "home"
  | "conversation"
  | "memory"
  | "analysis"
  | "projects"
  | "agenda"
  | "finance"
  | "settings";

export type Section = {
  id: SectionId;
  href: string;
  label: string;
  /** Libellé court pour la barre basse des téléphones. */
  short: string;
  phase: number;
  summary: string;
};

export const SECTIONS: Section[] = [
  { id: "home", href: "/", label: "Accueil", short: "Accueil", phase: 2, summary: "Vue d'ensemble et accès à Raphaël." },
  {
    id: "conversation",
    href: "/conversation",
    label: "Conversation",
    short: "Chat",
    phase: 3,
    summary: "Échanges écrits avec Raphaël, réponses en flux, historique persistant et reprise après rechargement.",
  },
  {
    id: "memory",
    href: "/memoire",
    label: "Mémoire",
    short: "Mémoire",
    phase: 5,
    summary: "Tout ce que Raphaël retient de vous, avec la source de chaque souvenir. Vous pourrez voir, modifier, épingler et supprimer.",
  },
  {
    id: "analysis",
    href: "/analyse",
    label: "Analyse",
    short: "Analyse",
    phase: 7,
    summary: "Aide à la décision : comparaison d'options, risques, scénarios.",
  },
  {
    id: "projects",
    href: "/projets",
    label: "Projets",
    short: "Projets",
    phase: 7,
    summary: "Objectifs, projets et tâches, avec suivi des progrès.",
  },
  {
    id: "agenda",
    href: "/agenda",
    label: "Agenda",
    short: "Agenda",
    phase: 7,
    summary: "Événements, rappels et planification.",
  },
  {
    id: "finance",
    href: "/finances",
    label: "Finances",
    short: "Finances",
    phase: 7,
    summary: "Budget et suivi des dépenses. Raphaël n'exécute jamais de paiement.",
  },
  {
    id: "settings",
    href: "/parametres",
    label: "Paramètres",
    short: "Réglages",
    phase: 2,
    summary: "Profil, appareils connectés et sessions.",
  },
];

export function sectionFor(pathname: string): Section {
  return (
    SECTIONS.find((s) => s.href !== "/" && (pathname === s.href || pathname.startsWith(`${s.href}/`))) ??
    SECTIONS[0]!
  );
}
