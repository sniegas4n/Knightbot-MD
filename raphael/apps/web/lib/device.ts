import type { Platform } from "./api";

export const PLATFORM_LABEL: Record<Platform, string> = {
  ios: "iPhone",
  ipados: "iPad",
  android: "Android",
  windows: "Windows",
  macos: "Mac",
  linux: "Linux",
  web: "Navigateur",
};

/** Plateforme de l'appareil courant. iPadOS se présente comme un Mac : on le reconnaît à
 *  son écran tactile. */
export function detectPlatform(): Platform {
  if (typeof navigator === "undefined") return "web";
  const ua = navigator.userAgent;
  if (/iPhone|iPod/.test(ua)) return "ios";
  if (/iPad/.test(ua) || (/Macintosh/.test(ua) && navigator.maxTouchPoints > 1)) return "ipados";
  if (/Android/.test(ua)) return "android";
  if (/Windows/.test(ua)) return "windows";
  if (/Macintosh|Mac OS X/.test(ua)) return "macos";
  if (/Linux|CrOS/.test(ua)) return "linux";
  return "web";
}

function detectBrowser(ua: string): string | null {
  if (/Edg\//.test(ua)) return "Edge";
  if (/Firefox\/|FxiOS/.test(ua)) return "Firefox";
  if (/CriOS|Chrome\//.test(ua)) return "Chrome";
  if (/Safari\//.test(ua)) return "Safari";
  return null;
}

export function defaultDeviceName(): string {
  const platform = detectPlatform();
  const browser = typeof navigator === "undefined" ? null : detectBrowser(navigator.userAgent);
  return browser ? `${PLATFORM_LABEL[platform]} · ${browser}` : PLATFORM_LABEL[platform];
}
