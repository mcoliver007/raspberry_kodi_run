#!/usr/bin/env python3
"""Liste les addons Kodi qui déclarent un service en arrière-plan
(extension point "xbmc.service", typiquement un service.py qui tourne dans
l'interpréteur Python de Kodi tant que Kodi est lancé).

Utile pour isoler le responsable d'un crash au moment de l'arrêt de
l'interpréteur Python (SIGSEGV dans PyObject_GC_UnTrack ou similaire) :
seuls les addons ayant un service en arrière-plan ont un thread Python
encore actif au moment où Kodi ferme l'interpréteur.

Ne modifie rien : lecture seule des addon.xml et de la base addons
(ouverte en mode "ro" pour ne jamais risquer de la corrompre).

Variables d'environnement :
  KODI_HOME  dossier de configuration Kodi (défaut: ~/.kodi)

Usage :
  ./scripts/list-addon-services.py
  ./scripts/list-addon-services.py --all      # inclut aussi les addons sans service
"""

from __future__ import annotations

import glob
import os
import sqlite3
import sys
import xml.etree.ElementTree as ET
from dataclasses import dataclass

KODI_HOME = os.environ.get("KODI_HOME", os.path.expanduser("~/.kodi"))
ADDONS_DIR = os.path.join(KODI_HOME, "addons")
DATABASE_DIR = os.path.join(KODI_HOME, "userdata", "Database")

# Seul dépôt officiel Kodi : tout le reste (funstersplace, etc.) est un
# dépôt tiers, potentiellement non modéré/non sécurisé.
OFFICIAL_REPO_IDS = {"repository.xbmc.org"}

# Motifs signalés comme suspects dans ce dépôt (voir README) : à adapter
# si d'autres addons sont soupçonnés.
KNOWN_SUSPECT_PATTERNS = ("vstream", "funstersplace")


@dataclass
class Addon:
    addon_id: str
    name: str
    version: str
    path: str
    service_library: str | None = None
    service_start: str | None = None
    enabled: bool | None = None
    origin: str | None = None
    is_repository: bool = False

    @property
    def has_service(self) -> bool:
        return self.service_library is not None

    def suspect_reasons(self) -> list[str]:
        reasons = []
        haystack = f"{self.addon_id} {self.name} {self.origin or ''}".lower()
        for pattern in KNOWN_SUSPECT_PATTERNS:
            if pattern in haystack:
                reasons.append(f"nom/origine correspond au motif surveillé '{pattern}'")
        if self.origin and self.origin not in OFFICIAL_REPO_IDS:
            reasons.append(f"installé depuis un dépôt tiers non officiel ({self.origin})")
        elif self.origin == "":
            reasons.append("origine inconnue (installation manuelle via zip ?)")
        return reasons


def parse_addon_xml(addon_xml_path: str) -> Addon | None:
    try:
        root = ET.parse(addon_xml_path).getroot()
    except ET.ParseError as exc:
        print(f"[list-addon-services] AVERTISSEMENT: {addon_xml_path} illisible ({exc})", file=sys.stderr)
        return None

    addon_id = root.get("id", "?")
    name = root.get("name", addon_id)
    version = root.get("version", "?")
    addon = Addon(
        addon_id=addon_id,
        name=name,
        version=version,
        path=os.path.dirname(addon_xml_path),
        is_repository=addon_id.startswith("repository."),
    )

    for extension in root.findall("extension"):
        if extension.get("point") == "xbmc.service":
            addon.service_library = extension.get("library", "service.py")
            addon.service_start = extension.get("start", "startup")

    return addon


def load_enabled_and_origin(addons: dict[str, Addon]) -> None:
    """Croise avec la base addons de Kodi (lecture seule) pour récupérer
    l'état enabled/disabled et le dépôt d'origine de chaque addon."""
    db_candidates = sorted(glob.glob(os.path.join(DATABASE_DIR, "Addons*.db")))
    if not db_candidates:
        print(
            f"[list-addon-services] AVERTISSEMENT: aucune base Addons*.db trouvée dans {DATABASE_DIR} "
            "(état enabled/origine indisponible).",
            file=sys.stderr,
        )
        return

    db_path = db_candidates[-1]
    try:
        uri = f"file:{db_path}?mode=ro"
        con = sqlite3.connect(uri, uri=True, timeout=5)
        try:
            cur = con.execute("SELECT addonID, enabled, origin FROM installed")
            for addon_id, enabled, origin in cur.fetchall():
                if addon_id in addons:
                    addons[addon_id].enabled = bool(enabled)
                    addons[addon_id].origin = origin
        finally:
            con.close()
    except sqlite3.Error as exc:
        print(
            f"[list-addon-services] AVERTISSEMENT: lecture de {db_path} impossible ({exc}). "
            "État enabled/origine indisponible.",
            file=sys.stderr,
        )


def collect_addons() -> dict[str, Addon]:
    addons: dict[str, Addon] = {}
    for addon_xml_path in sorted(glob.glob(os.path.join(ADDONS_DIR, "*", "addon.xml"))):
        addon = parse_addon_xml(addon_xml_path)
        if addon is not None:
            addons[addon.addon_id] = addon
    return addons


def format_bool(value: bool | None) -> str:
    if value is None:
        return "?"
    return "actif" if value else "désactivé"


def main() -> int:
    show_all = "--all" in sys.argv[1:]

    if not os.path.isdir(ADDONS_DIR):
        print(f"[list-addon-services] ERREUR: dossier addons introuvable: {ADDONS_DIR}", file=sys.stderr)
        print("Renseigne KODI_HOME si Kodi n'utilise pas ~/.kodi.", file=sys.stderr)
        return 1

    addons = collect_addons()
    load_enabled_and_origin(addons)

    repos = [a for a in addons.values() if a.is_repository]
    services = [a for a in addons.values() if a.has_service]

    print(f"== Dépôts installés ({ADDONS_DIR}) ==")
    if not repos:
        print("  (aucun dépôt détecté)")
    for repo in sorted(repos, key=lambda a: a.addon_id):
        official = "officiel" if repo.addon_id in OFFICIAL_REPO_IDS else "TIERS — non officiel"
        print(f"  - {repo.addon_id} ({repo.name}, v{repo.version}) [{official}] [{format_bool(repo.enabled)}]")
    print()

    print("== Addons avec un service en arrière-plan (xbmc.service) ==")
    if not services:
        print("  (aucun addon avec service.py trouvé)")
    for addon in sorted(services, key=lambda a: a.addon_id):
        reasons = addon.suspect_reasons()
        flag = " *** SUSPECT ***" if reasons else ""
        print(f"  - {addon.addon_id} ({addon.name}, v{addon.version}){flag}")
        print(f"      service : {addon.service_library}  (start={addon.service_start})")
        print(f"      état    : {format_bool(addon.enabled)}")
        print(f"      origine : {addon.origin if addon.origin is not None else '?'}")
        print(f"      chemin  : {addon.path}")
        for reason in reasons:
            print(f"      ! {reason}")
    print()

    suspects = [a for a in services if a.suspect_reasons() and a.enabled is not False]
    if suspects:
        print("== Résumé : addons à investiguer en priorité ==")
        for addon in suspects:
            print(f"  - {addon.addon_id}  ({'; '.join(addon.suspect_reasons())})")
        print()
        print("Prochaine étape : ./scripts/diagnose-shutdown-crash.sh pour corréler avec le crash,")
        print("puis ./scripts/remove-addon.sh <addon-id> pour désactiver/désinstaller.")
    else:
        print("Aucun addon connu ne correspond aux motifs surveillés (vstream/funstersplace/dépôt tiers).")
        print("Le second thread fautif est peut-être un autre addon : vérifie la liste complète ci-dessus,")
        print("en particulier tout service dont l'origine n'est pas 'repository.xbmc.org'.")

    if show_all:
        others = [a for a in addons.values() if not a.has_service and not a.is_repository]
        print()
        print("== Autres addons installés (sans service en arrière-plan) ==")
        for addon in sorted(others, key=lambda a: a.addon_id):
            print(f"  - {addon.addon_id} ({addon.name}, v{addon.version}) [{format_bool(addon.enabled)}]")

    return 0


if __name__ == "__main__":
    sys.exit(main())
