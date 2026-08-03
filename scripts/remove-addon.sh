#!/usr/bin/env bash
#
# remove-addon.sh — désactive ou désinstalle proprement un addon Kodi.
#
# Usage :
#   ./scripts/remove-addon.sh <addon-id>                    # désinstallation complète
#   ./scripts/remove-addon.sh <addon-id> --disable-only      # désactivation seule (réversible)
#   ./scripts/remove-addon.sh <addon-id> --yes                # sans confirmation interactive
#
# Trouve l'id exact d'un addon avec : ./scripts/list-addon-services.py --all
#
# Désactivation (--disable-only) : passe par l'API JSON-RPC de Kodi
# (Addons.SetAddonEnabled) — nécessite que Kodi tourne ET que le serveur web
# soit activé (Réglages > Services > Contrôle > "Autoriser le contrôle à
# distance via HTTP"). Réversible : l'addon reste installé, juste inactif au
# prochain démarrage (son service.py ne sera donc plus lancé).
#
# Désinstallation complète (comportement par défaut) :
#   1. arrête kodi.service (unité systemd utilisateur de ce dépôt) si actif ;
#   2. supprime le dossier de l'addon et ses données utilisateur ;
#   3. laisse Kodi nettoyer lui-même l'entrée orpheline de sa base au
#      prochain démarrage — comportement standard : un addon dont le
#      dossier n'existe plus n'est pas (re)lancé.
# Ne redémarre PAS kodi.service automatiquement : à faire une fois vérifié
# que tout est en ordre (systemctl --user start kodi.service).
#
# Variables (désactivation via JSON-RPC uniquement) :
#   KODI_HOME      dossier de configuration Kodi (défaut: ~/.kodi)
#   KODI_RPC_HOST  (défaut: localhost)
#   KODI_RPC_PORT  (défaut: 8080)
#   KODI_RPC_USER  (défaut: kodi)
#   KODI_RPC_PASS  (défaut: vide)

set -uo pipefail

KODI_HOME="${KODI_HOME:-$HOME/.kodi}"
KODI_RPC_HOST="${KODI_RPC_HOST:-localhost}"
KODI_RPC_PORT="${KODI_RPC_PORT:-8080}"
KODI_RPC_USER="${KODI_RPC_USER:-kodi}"
KODI_RPC_PASS="${KODI_RPC_PASS:-}"

log() {
    echo "[remove-addon] $*"
}

addon_id=""
disable_only=0
assume_yes=0

for arg in "$@"; do
    case "$arg" in
        --disable-only) disable_only=1 ;;
        --yes|-y) assume_yes=1 ;;
        -*)
            echo "ERREUR: option inconnue: $arg" >&2
            exit 1
            ;;
        *) addon_id="$arg" ;;
    esac
done

if [ -z "$addon_id" ]; then
    echo "Usage: $0 <addon-id> [--disable-only] [--yes]" >&2
    echo "Exemple: $0 plugin.video.vstream" >&2
    echo "Trouve l'id exact avec: ./scripts/list-addon-services.py --all" >&2
    exit 1
fi

confirm() {
    [ "$assume_yes" -eq 1 ] && return 0
    read -r -p "$1 [o/N] " reply
    case "$reply" in
        o|O|oui|Oui) return 0 ;;
        *) return 1 ;;
    esac
}

# --- Désactivation via JSON-RPC (réversible) ----------------------------

disable_via_jsonrpc() {
    if ! command -v curl >/dev/null 2>&1; then
        log "ERREUR: curl introuvable, impossible d'appeler l'API JSON-RPC de Kodi."
        return 1
    fi

    payload=$(printf '{"jsonrpc":"2.0","id":1,"method":"Addons.SetAddonEnabled","params":{"addonid":"%s","enabled":false}}' "$addon_id")
    response="$(curl -sS --user "${KODI_RPC_USER}:${KODI_RPC_PASS}" \
        -H 'Content-Type: application/json' \
        -d "$payload" \
        "http://${KODI_RPC_HOST}:${KODI_RPC_PORT}/jsonrpc" 2>&1)"
    curl_rc=$?

    if [ "$curl_rc" -ne 0 ]; then
        log "ERREUR: appel JSON-RPC échoué (Kodi éteint, serveur web désactivé, ou hôte/port incorrects)."
        log "Détail: $response"
        log "Vérifie: Réglages > Services > Contrôle > 'Autoriser le contrôle à distance via HTTP'."
        log "Ou utilise la désinstallation complète (sans --disable-only)."
        return 1
    fi

    if echo "$response" | grep -q '"result":"OK"'; then
        log "Addon '${addon_id}' désactivé via l'API Kodi (toujours installé, ne redémarrera plus)."
        return 0
    fi

    log "ERREUR: Kodi a refusé/mal répondu à la requête: $response"
    return 1
}

# --- Désinstallation complète -------------------------------------------

uninstall_fully() {
    addon_dir="$KODI_HOME/addons/$addon_id"
    userdata_dir="$KODI_HOME/userdata/addon_data/$addon_id"

    if [ ! -d "$addon_dir" ]; then
        log "ERREUR: addon introuvable: $addon_dir"
        log "Vérifie l'id exact avec: ./scripts/list-addon-services.py --all"
        return 1
    fi

    log "Va supprimer :"
    log "  - $addon_dir"
    [ -d "$userdata_dir" ] && log "  - $userdata_dir"

    if ! confirm "Confirmer la suppression de '${addon_id}' ?"; then
        log "Annulé."
        return 1
    fi

    if systemctl --user is-active --quiet kodi.service 2>/dev/null; then
        log "Arrêt de kodi.service..."
        systemctl --user stop kodi.service
    fi

    rm -rf "$addon_dir"
    log "Supprimé: $addon_dir"

    if [ -d "$userdata_dir" ]; then
        rm -rf "$userdata_dir"
        log "Supprimé: $userdata_dir"
    fi

    log "Terminé. Kodi nettoiera l'entrée orpheline de sa base au prochain démarrage."
    log "Relance Kodi avec: systemctl --user start kodi.service"

    case "$addon_id" in
        repository.*)
            log "NOTE: ceci supprime le DÉPÔT '${addon_id}', pas les addons déjà installés depuis lui."
            log "Relance ./scripts/list-addon-services.py pour voir s'il en reste (origine = '${addon_id}')."
            ;;
    esac
}

if [ "$disable_only" -eq 1 ]; then
    disable_via_jsonrpc
else
    uninstall_fully
fi
