"""Étape 3 : Claude choisit 5 à 15 clips candidats dans la transcription."""

from __future__ import annotations

import json
import re
from typing import Any

import anthropic

from clipper.config import Config
from clipper.journal import journal

log = journal("selection")

# Schéma imposé à la réponse de Claude (sorties structurées).
SCHEMA_CANDIDATS = {
    "type": "object",
    "properties": {
        "candidats": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "debut": {"type": "number"},
                    "fin": {"type": "number"},
                    "sujet": {"type": "string"},
                    "note": {"type": "integer"},
                    "raison": {"type": "string"},
                },
                "required": ["debut", "fin", "sujet", "note", "raison"],
                "additionalProperties": False,
            },
        }
    },
    "required": ["candidats"],
    "additionalProperties": False,
}

_FIN_DE_PHRASE = re.compile(r"[.!?…]['\"»)]*$")


class ErreurSelection(Exception):
    pass


# --- Mise en forme de la transcription ----------------------------------


def phrases(mots: list[dict[str, Any]], silence_max: float = 2.0) -> list[dict[str, Any]]:
    """Regroupe les mots en phrases : coupure sur ponctuation finale, changement de locuteur ou long silence."""
    resultat: list[dict[str, Any]] = []
    courante: list[dict[str, Any]] = []
    for m in mots:
        if courante and (m["spk"] != courante[-1]["spk"] or m["s"] - courante[-1]["e"] > silence_max):
            resultat.append(_phrase(courante))
            courante = []
        courante.append(m)
        if _FIN_DE_PHRASE.search(m["w"]):
            resultat.append(_phrase(courante))
            courante = []
    if courante:
        resultat.append(_phrase(courante))
    return resultat


def _phrase(mots: list[dict[str, Any]]) -> dict[str, Any]:
    return {
        "s": mots[0]["s"],
        "e": mots[-1]["e"],
        "spk": mots[0]["spk"],
        "texte": " ".join(m["w"] for m in mots),
    }


def formater(liste_phrases: list[dict[str, Any]]) -> str:
    """Une ligne par phrase : « [début–fin] Sx : texte »."""
    return "\n".join(f"[{p['s']:.1f}–{p['e']:.1f}] S{p['spk']} : {p['texte']}" for p in liste_phrases)


def decouper_en_blocs(
    liste_phrases: list[dict[str, Any]], bloc_s: float, recouvrement_s: float
) -> list[list[dict[str, Any]]]:
    """Découpe une transcription longue en blocs de bloc_s secondes qui se recouvrent de recouvrement_s."""
    if not liste_phrases:
        return []
    fin_totale = liste_phrases[-1]["e"]
    if fin_totale <= bloc_s:
        return [liste_phrases]
    pas = max(bloc_s - recouvrement_s, 1.0)
    blocs = []
    debut = 0.0
    while debut < fin_totale:
        bloc = [p for p in liste_phrases if p["s"] >= debut and p["s"] < debut + bloc_s]
        if bloc:
            blocs.append(bloc)
        if debut + bloc_s >= fin_totale:
            break
        debut += pas
    return blocs


# --- Lecture de la réponse de Claude ------------------------------------


def analyser_reponse(texte: str, duree_video: float | None = None) -> tuple[list[dict[str, Any]], list[str]]:
    """Transforme la réponse de Claude en candidats valides. Retourne (candidats, motifs de rejet)."""
    donnees = _extraire_json(texte)
    if isinstance(donnees, dict):
        brut = donnees.get("candidats")
    else:
        brut = donnees
    if not isinstance(brut, list):
        raise ErreurSelection("La réponse de Claude ne contient pas de liste « candidats ».")

    candidats, rejets = [], []
    for i, c in enumerate(brut, 1):
        try:
            candidats.append(_valider_candidat(c, duree_video))
        except ValueError as exc:
            rejets.append(f"candidat {i} rejeté : {exc}")
    return candidats, rejets


def _extraire_json(texte: str) -> Any:
    texte = texte.strip()
    # Tolère un bloc ```json ... ``` ou du texte autour de l'objet.
    bloc = re.search(r"```(?:json)?\s*(.*?)```", texte, re.DOTALL)
    if bloc:
        texte = bloc.group(1).strip()
    try:
        return json.loads(texte)
    except json.JSONDecodeError:
        pass
    for ouvrant, fermant in (("{", "}"), ("[", "]")):
        a, b = texte.find(ouvrant), texte.rfind(fermant)
        if a != -1 and b > a:
            try:
                return json.loads(texte[a : b + 1])
            except json.JSONDecodeError:
                continue
    raise ErreurSelection("La réponse de Claude n'est pas du JSON lisible.")


def _valider_candidat(c: Any, duree_video: float | None) -> dict[str, Any]:
    if not isinstance(c, dict):
        raise ValueError("ce n'est pas un objet")
    try:
        debut, fin = float(c["debut"]), float(c["fin"])
    except (KeyError, TypeError, ValueError):
        raise ValueError("début ou fin manquant ou non numérique") from None
    if debut < 0 or fin <= debut:
        raise ValueError(f"bornes incohérentes ({debut} → {fin})")
    if duree_video and fin > duree_video + 1:
        raise ValueError(f"fin ({fin:.0f} s) après la fin de la vidéo ({duree_video:.0f} s)")
    sujet = str(c.get("sujet") or "").strip()
    if not sujet:
        raise ValueError("sujet vide")
    try:
        note = int(round(float(c["note"])))
    except (KeyError, TypeError, ValueError):
        raise ValueError("note manquante ou non numérique") from None
    if not 0 <= note <= 100:
        raise ValueError(f"note hors de 0–100 ({note})")
    return {"debut": round(debut, 2), "fin": round(fin, 2), "sujet": sujet, "note": note,
            "raison": str(c.get("raison") or "").strip()}


# --- Fusion et chevauchements -------------------------------------------


def taux_chevauchement(a: dict[str, Any], b: dict[str, Any]) -> float:
    """Part du plus court des deux clips qui recouvre l'autre (0 = disjoints, 1 = inclus)."""
    commun = min(a["fin"], b["fin"]) - max(a["debut"], b["debut"])
    if commun <= 0:
        return 0.0
    return commun / min(a["fin"] - a["debut"], b["fin"] - b["debut"])


def filtrer_chevauchements(candidats: list[dict[str, Any]], seuil: float) -> list[dict[str, Any]]:
    """Garde les meilleurs candidats en écartant ceux qui chevauchent un mieux noté au-delà du seuil."""
    gardes: list[dict[str, Any]] = []
    for c in sorted(candidats, key=lambda x: (-x["note"], x["debut"])):
        if all(taux_chevauchement(c, g) < seuil for g in gardes):
            gardes.append(c)
    return sorted(gardes, key=lambda x: x["debut"])


# --- Appel à Claude -----------------------------------------------------


def charger_prompt(cfg: Config, nom: str, variables: dict[str, Any]) -> str:
    texte = (cfg.dossier_prompts / f"{nom}.md").read_text(encoding="utf-8")
    for cle, valeur in variables.items():
        texte = texte.replace("{{" + cle + "}}", str(valeur))
    return texte


def _cout(usage: Any, cfg: Config) -> float:
    pe = float(cfg.get("selection.prix_entree_par_million", 0)) / 1e6
    ps = float(cfg.get("selection.prix_sortie_par_million", 0)) / 1e6
    entree = (
        (usage.input_tokens or 0)
        + 1.25 * (getattr(usage, "cache_creation_input_tokens", 0) or 0)
        + 0.1 * (getattr(usage, "cache_read_input_tokens", 0) or 0)
    )
    return entree * pe + (usage.output_tokens or 0) * ps


def appeler_claude(client: anthropic.Anthropic, systeme: str, message: str, cfg: Config) -> tuple[str, float]:
    """Envoie un bloc de transcription à Claude. Retourne (texte de la réponse, coût en dollars)."""
    with client.beta.messages.stream(
        model=cfg.get("selection.modele", "claude-opus-5-5"),
        max_tokens=32000,
        system=systeme,
        messages=[{"role": "user", "content": message}],
        output_config={
            "effort": cfg.get("selection.effort", "high"),
            "format": {"type": "json_schema", "schema": SCHEMA_CANDIDATS},
        },
        # Si un filtre de sécurité refuse à tort, l'API rejoue la requête sur un modèle de repli.
        betas=["server-side-fallback-2026-07-01"],
        fallbacks="default",
    ) as flux:
        reponse = flux.get_final_message()

    cout = _cout(reponse.usage, cfg)
    if reponse.stop_reason == "refusal":
        raise ErreurSelection("Claude a refusé de traiter cette transcription.")
    if reponse.stop_reason == "max_tokens":
        raise ErreurSelection("Réponse de Claude tronquée (limite de jetons atteinte).")
    texte = "".join(b.text for b in reponse.content if b.type == "text")
    return texte, cout


def selectionner(
    video: dict[str, Any], transcription: dict[str, Any], cfg: Config,
    client: anthropic.Anthropic | None = None,
) -> tuple[list[dict[str, Any]], float]:
    """Retourne (candidats retenus, coût total en dollars) pour une vidéo."""
    nb_min, nb_max = int(cfg.get("selection.nb_min", 5)), int(cfg.get("selection.nb_max", 15))
    duree_min, duree_max = int(cfg.get("selection.duree_min", 120)), int(cfg.get("selection.duree_max", 300))
    seuil = float(cfg.get("selection.chevauchement_max", 0.2))

    liste = phrases(transcription["mots"])
    if not liste:
        raise ErreurSelection("Transcription vide : rien à sélectionner.")
    blocs = decouper_en_blocs(
        liste,
        float(cfg.get("selection.bloc_minutes", 120)) * 60,
        float(cfg.get("selection.recouvrement_minutes", 10)) * 60,
    )
    systeme = charger_prompt(cfg, "selection", {
        "nb_min": nb_min, "nb_max": nb_max, "duree_min": duree_min, "duree_max": duree_max,
        "duree_min_minutes": round(duree_min / 60, 1), "duree_max_minutes": round(duree_max / 60, 1),
        "chevauchement_pct": round(seuil * 100),
    })
    if client is None:
        client = anthropic.Anthropic(api_key=cfg.secret("ANTHROPIC_API_KEY"))

    duree = float(video.get("duree") or transcription.get("duree") or 0)
    tous: list[dict[str, Any]] = []
    cout_total = 0.0
    for i, bloc in enumerate(blocs, 1):
        entete = (
            f"Titre de la vidéo : {video.get('titre') or 'inconnu'}\n"
            f"Chaîne : {video.get('chaine') or 'inconnue'}\n"
            f"Durée totale : {duree / 60:.0f} min\n"
        )
        if len(blocs) > 1:
            entete += (
                f"Bloc {i}/{len(blocs)} de la transcription ({bloc[0]['s'] / 60:.0f} à {bloc[-1]['e'] / 60:.0f} min). "
                "Ne propose que des clips entièrement contenus dans ce bloc.\n"
            )
        log.info("Sélection pour %s : bloc %d/%d envoyé à Claude...", video["id"], i, len(blocs))
        texte, cout = appeler_claude(client, systeme, entete + "\nTranscription :\n" + formater(bloc), cfg)
        cout_total += cout
        candidats, rejets = analyser_reponse(texte, duree or None)
        for r in rejets:
            log.warning("%s : %s", video["id"], r)
        tous.extend(candidats)

    retenus = filtrer_chevauchements(tous, seuil)
    if len(retenus) > nb_max:
        meilleurs = sorted(retenus, key=lambda x: -x["note"])[:nb_max]
        retenus = sorted(meilleurs, key=lambda x: x["debut"])
    if len(retenus) < nb_min:
        log.warning("%s : seulement %d candidats retenus (minimum visé : %d).", video["id"], len(retenus), nb_min)
    log.info("Sélection pour %s : %d candidats retenus sur %d proposés, coût %.3f $.",
             video["id"], len(retenus), len(tous), cout_total)
    return retenus, cout_total
