"use client";

import { useRouter, useSearchParams } from "next/navigation";
import { Suspense, useEffect, useState } from "react";
import { RaphaelCore } from "@/components/core/RaphaelCore";
import { Splash } from "@/components/shell/Splash";
import { Logo } from "@/components/ui/Logo";
import { ApiError, auth, NetworkError, type AuthStatus } from "@/lib/api";
import { defaultDeviceName, detectPlatform } from "@/lib/device";

/** Redirection interne uniquement (pas de « //autre-site »). */
function safeNext(raw: string | null): string {
  return raw && raw.startsWith("/") && !raw.startsWith("//") ? raw : "/";
}

function Field(props: React.InputHTMLAttributes<HTMLInputElement> & { label: string; hint?: string }) {
  const { label, hint, id, ...rest } = props;
  return (
    <div>
      <label htmlFor={id} className="mb-1.5 block text-sm text-mist">
        {label}
      </label>
      <input
        id={id}
        {...rest}
        className="w-full rounded-xl border border-line bg-night/80 px-3.5 py-2.5 text-ice placeholder:text-mist/50 focus:border-cyan/60 focus:outline-none"
      />
      {hint && <p className="mt-1 font-mono text-[11px] text-mist/70">{hint}</p>}
    </div>
  );
}

function LoginScreen() {
  const router = useRouter();
  const next = safeNext(useSearchParams().get("next"));
  const [status, setStatus] = useState<AuthStatus | null>(null);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [form, setForm] = useState({
    display_name: "",
    email: "",
    password: "",
    confirm: "",
    setup_token: "",
    device_name: "",
  });

  const check = async () => {
    setLoadError(null);
    try {
      // Déjà connecté ? On ne redemande pas le mot de passe.
      await auth.me();
      router.replace(next);
      return;
    } catch (e) {
      if (!(e instanceof ApiError && e.status === 401)) {
        setLoadError(e instanceof Error ? e.message : "Erreur inconnue.");
        return;
      }
    }
    try {
      setStatus(await auth.status());
    } catch (e) {
      setLoadError(e instanceof Error ? e.message : "Erreur inconnue.");
    }
  };

  useEffect(() => {
    setForm((f) => ({ ...f, device_name: f.device_name || defaultDeviceName() }));
    void check();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  if (loadError) return <Splash message={`Connexion impossible : ${loadError}`} onRetry={() => void check()} />;
  if (!status) return <Splash message="Connexion au serveur…" />;

  const setup = status.setup_required;
  const set = (k: keyof typeof form) => (e: React.ChangeEvent<HTMLInputElement>) =>
    setForm({ ...form, [k]: e.target.value });

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);
    if (setup && form.password !== form.confirm) {
      setError("Les deux mots de passe ne correspondent pas.");
      return;
    }
    setBusy(true);
    const device = { device_name: form.device_name.trim() || defaultDeviceName(), platform: detectPlatform() };
    try {
      if (setup) {
        await auth.setup({
          ...device,
          display_name: form.display_name.trim(),
          email: form.email.trim(),
          password: form.password,
          ...(status.setup_token_required ? { setup_token: form.setup_token } : {}),
        });
      } else {
        await auth.login({ ...device, email: form.email.trim(), password: form.password });
      }
      router.replace(next);
    } catch (err) {
      if (err instanceof ApiError && err.status === 429 && err.retryAfter) {
        setError(`Trop de tentatives. Réessayez dans ${Math.ceil(err.retryAfter / 60)} min.`);
      } else if (err instanceof ApiError && err.status === 409) {
        setError("Le compte propriétaire existe déjà. Connectez-vous.");
        setStatus({ ...status, setup_required: false });
      } else if (err instanceof NetworkError || err instanceof ApiError) {
        setError(err.message);
      } else {
        setError("Erreur inattendue.");
      }
      setBusy(false);
    }
  };

  return (
    <main className="flex min-h-dvh items-center justify-center px-5 py-10">
      <div className="w-full max-w-sm">
        <div className="flex flex-col items-center gap-5">
          <RaphaelCore state={busy ? "thinking" : "idle"} size={120} />
          <Logo />
        </div>

        <form onSubmit={submit} className="mt-8 space-y-4 rounded-2xl border border-line bg-abyss/80 p-6 backdrop-blur">
          <div>
            <h1 className="font-display text-lg font-semibold">{setup ? "Configuration initiale" : "Connexion"}</h1>
            <p className="mt-1 text-sm text-mist">
              {setup
                ? "Créez le compte propriétaire. RAPHAËL n'accepte qu'un seul compte : le vôtre."
                : "Identifiez-vous pour accéder à RAPHAËL."}
            </p>
          </div>

          {setup && (
            <Field id="display_name" label="Votre prénom" autoComplete="given-name" required maxLength={60}
              value={form.display_name} onChange={set("display_name")} />
          )}
          <Field id="email" label="E-mail" type="email" autoComplete={setup ? "email" : "username"} required
            value={form.email} onChange={set("email")} />
          <Field id="password" label="Mot de passe" type="password" required
            autoComplete={setup ? "new-password" : "current-password"}
            minLength={setup ? 12 : 1} maxLength={256}
            hint={setup ? "12 caractères minimum. Une phrase de passe est idéale." : undefined}
            value={form.password} onChange={set("password")} />
          {setup && (
            <Field id="confirm" label="Confirmer le mot de passe" type="password" autoComplete="new-password"
              required minLength={12} value={form.confirm} onChange={set("confirm")} />
          )}
          {setup && status.setup_token_required && (
            <Field id="setup_token" label="Jeton de configuration" required autoComplete="off"
              hint="Défini par RAPHAEL_SETUP_TOKEN sur le serveur."
              value={form.setup_token} onChange={set("setup_token")} />
          )}
          <Field id="device_name" label="Nom de cet appareil" maxLength={60} autoComplete="off"
            hint="Affiché dans Paramètres › Appareils."
            value={form.device_name} onChange={set("device_name")} />

          {error && (
            <p role="alert" className="rounded-lg border border-danger/40 bg-danger/10 px-3 py-2 text-sm text-danger">
              {error}
            </p>
          )}

          <button
            type="submit"
            disabled={busy}
            className="w-full rounded-xl bg-cyan px-4 py-2.5 font-medium text-void shadow-glow transition-opacity disabled:opacity-60"
          >
            {busy ? "Vérification…" : setup ? "Créer le compte" : "Se connecter"}
          </button>
        </form>
      </div>
    </main>
  );
}

export default function LoginPage() {
  return (
    <Suspense fallback={<Splash message="Connexion au serveur…" />}>
      <LoginScreen />
    </Suspense>
  );
}
