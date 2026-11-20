import { RaphaelCore } from "@/components/core/RaphaelCore";
import { Logo } from "@/components/ui/Logo";

/** Écran d'attente / d'erreur plein écran (vérification de session, serveur injoignable). */
export function Splash({ message, onRetry }: { message?: string; onRetry?: () => void }) {
  const failed = onRetry !== undefined;
  return (
    <div className="flex min-h-dvh flex-col items-center justify-center gap-6 px-6 text-center">
      <RaphaelCore state={failed ? "offline" : "idle"} size={140} />
      <Logo />
      <p className={failed ? "text-danger" : "text-mist"} role="status" aria-live="polite">
        {message ?? "Vérification de la session…"}
      </p>
      {failed && (
        <button
          type="button"
          onClick={onRetry}
          className="rounded-lg border border-line px-4 py-2 text-sm text-ice transition-colors hover:border-cyan/50"
        >
          Réessayer
        </button>
      )}
    </div>
  );
}
