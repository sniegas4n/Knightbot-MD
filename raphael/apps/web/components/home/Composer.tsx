/** Zone de saisie. Désactivée tant que le moteur conversationnel (phase 3) et la voix
 *  (phase 4) ne sont pas branchés : rien n'est simulé. */
export function Composer() {
  return (
    <form
      className="flex items-center gap-2 rounded-2xl border border-line bg-abyss/90 p-2 backdrop-blur"
      onSubmit={(e) => e.preventDefault()}
      aria-label="Écrire à Raphaël"
    >
      <label htmlFor="composer" className="sr-only">
        Message pour Raphaël
      </label>
      <input
        id="composer"
        disabled
        placeholder="Écrire à Raphaël… (phase 3)"
        className="min-w-0 flex-1 bg-transparent px-3 py-2 text-sm text-ice placeholder:text-mist/60 disabled:cursor-not-allowed"
      />
      <button
        type="button"
        disabled
        title="Conversation vocale — disponible en phase 4"
        aria-label="Conversation vocale — disponible en phase 4"
        className="grid size-11 shrink-0 place-items-center rounded-full border border-line bg-night text-mist opacity-60"
      >
        <svg viewBox="0 0 24 24" className="size-5" fill="none" stroke="currentColor" strokeWidth="1.6" aria-hidden="true">
          <rect x="9" y="3" width="6" height="12" rx="3" />
          <path d="M5 11a7 7 0 0 0 14 0M12 18v3" strokeLinecap="round" />
        </svg>
      </button>
      <button
        type="submit"
        disabled
        title="Envoi — disponible en phase 3"
        aria-label="Envoyer — disponible en phase 3"
        className="grid size-11 shrink-0 place-items-center rounded-full bg-cyan/20 text-cyan-soft opacity-50"
      >
        <svg viewBox="0 0 24 24" className="size-5" fill="none" stroke="currentColor" strokeWidth="1.8" aria-hidden="true">
          <path d="M5 12h13M13 6l6 6-6 6" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      </button>
    </form>
  );
}
