#!/usr/bin/env bash
#
# wait-for-bluetooth-audio.sh
#
# Bloque jusqu'à ce que :
#   1. le serveur PulseAudio de la session utilisateur réponde ;
#   2. ce serveur ait un sink Bluetooth (bluez_sink.*) dans sa liste, ce qui
#      prouve que l'enceinte déjà appairée est bien connectée : PulseAudio
#      décharge automatiquement la carte/le sink Bluetooth dès que
#      l'appareil se déconnecte, donc la simple présence du sink dans
#      "pactl list sinks" suffit comme preuve de connexion.
#
#      Volontairement, on ne filtre PAS sur l'état RUNNING/IDLE/SUSPENDED :
#      un sink Bluetooth connecté mais inactif (aucun son en cours) est
#      normalement à l'état SUSPENDED (mise en veille par PulseAudio pour
#      économiser la liaison), ce qui ne veut absolument pas dire qu'il est
#      déconnecté. Exiger RUNNING/IDLE ferait attendre indéfiniment tant
#      qu'aucun son n'est joué.
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

log "Attente de la connexion d'un sink Bluetooth ('${BT_SINK_MATCH}')..."
while true; do
    if pactl list sinks short 2>/dev/null | grep -q "$BT_SINK_MATCH"; then
        log "Sink Bluetooth trouvé : enceinte connectée."
        exit 0
    fi

    log "Aucun sink Bluetooth détecté pour l'instant."

    if [ "$(date +%s)" -ge "$deadline" ]; then
        log "ERREUR: timeout en attendant l'enceinte Bluetooth après ${WAIT_TIMEOUT}s."
        exit 1
    fi
    sleep "$POLL_INTERVAL"
done
