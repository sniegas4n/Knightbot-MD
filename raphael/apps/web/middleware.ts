import { NextResponse, type NextRequest } from "next/server";

/** Premier filtre, côté serveur Next.js : sans cookie de session, on envoie directement vers
 *  /login au lieu de charger l'application. La validité réelle de la session est vérifiée
 *  par l'API (le cookie peut être expiré ou révoqué) via <AuthGate>. */
export function middleware(req: NextRequest) {
  if (req.cookies.has("raphael_session")) return NextResponse.next();
  const url = req.nextUrl.clone();
  const target = req.nextUrl.pathname;
  url.pathname = "/login";
  url.search = target && target !== "/" ? `?next=${encodeURIComponent(target)}` : "";
  return NextResponse.redirect(url);
}

export const config = {
  // Tout sauf : l'écran de connexion, la référence de design, l'API relayée, les fichiers
  // statiques et le manifeste PWA.
  matcher: ["/((?!login|design|v1|_next|icons|manifest\\.webmanifest|favicon\\.ico).*)"],
};
