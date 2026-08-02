#!/usr/bin/env bash
#
# wait-for-bluetooth-audio.sh
#
# Bloque jusqu'à ce que :
#   1. le serveur PulseAudio de la session utilisateur réponde ;
#   2. ce serveur ait un sink Bluetooth (bluez_sink.*) actif et non "suspended",
#      c'est-à-dire qu'une enceinte Bluetooth déjà appairée est bien
#      connectée ET reçoit effectivement l'audio.
#
# Ce script est exécuté par une unité systemd *utilisateur*
# (kodi-wait-ready.service), donc déjà dans le bon contexte
# (XDG_RUNTIME_DIR/DBUS_SESSION_BUS_ADDRESS positionnés automatiquement par
# systemd --user) : pas besoin de sudo/su ni de changer d'utilisateur.
#
# Variables (surchargeables via config/kodi-service.env) :
#   BT_SINK_MATCH motif recherché dans le nom du sink (défaut: bluez_sink)
#   WAIT_TIMEOUT  délai max en secondes avant abandon (défaut: 90)
#   POLL_INTERVAL intervalle entre deux vérifications en secondes (défaut: 2)

set -uo pipefail

BT_SINK_MATCH="${BT_SINK_MATCH:-bluez_sink}"
WAIT_TIMEOUT="${WAIT_TIMEOUT:-90}"
POLL_INTERVAL="${POLL_INTERVAL:-2}"

log() {
    echo "[wait-for-bluetooth-audio] $*"
}

deadline=$(( $(date +%s) + WAIT_TIMEOUT ))

log "Attente du serveur audio PulseAudio (session utilisateur)..."
while true; do
    if pactl info >/dev/null 2>&1; then
        log "Serveur PulseAudio disponible."
        break
    fi
    if [ "$(date +%s)" -ge "$deadline" ]; then
        log "ERREUR: timeout en attendant PulseAudio après ${WAIT_TIMEOUT}s."
        exit 1
    fi
    sleep "$POLL_INTERVAL"
done

log "Attente d'un sink Bluetooth ('${BT_SINK_MATCH}') actif..."
while true; do
    sinks="$(pactl list sinks 2>/dev/null || true)"

    if [ -n "$sinks" ] && echo "$sinks" | grep -q "$BT_SINK_MATCH"; then
        # On isole le bloc du sink bluetooth (chaque sink est un paragraphe
        # séparé par une ligne vide dans la sortie de "pactl list sinks") et
        # on vérifie son état (RUNNING ou IDLE = connecté et prêt ;
        # SUSPENDED = pas de flux/pas vraiment opérationnel). Attention :
        # la ligne "State:" apparaît AVANT la ligne "Name:" dans chaque
        # bloc, d'où le traitement paragraphe par paragraphe plutôt que
        # ligne par ligne.
        state="$(echo "$sinks" | awk -v RS="" -v pat="$BT_SINK_MATCH" '
            $0 ~ pat {
                if (match($0, /State: [A-Za-z]+/)) {
                    print substr($0, RSTART + 7, RLENGTH - 7)
                }
                exit
            }
        ')"

        if [ "$state" = "RUNNING" ] || [ "$state" = "IDLE" ]; then
            log "Sink Bluetooth trouvé et opérationnel (état: ${state})."
            exit 0
        else
            log "Sink Bluetooth trouvé mais pas encore prêt (état: ${state:-inconnu})."
        fi
    else
        log "Aucun sink Bluetooth détecté pour l'instant."
    fi

    if [ "$(date +%s)" -ge "$deadline" ]; then
        log "ERREUR: timeout en attendant l'enceinte Bluetooth après ${WAIT_TIMEOUT}s."
        exit 1
    fi
    sleep "$POLL_INTERVAL"
done
