#!/usr/bin/env bash
#
# wait-for-piper-tts.sh
#
# Attend que le service de synthèse vocale Piper (piper-tts.service,
# cf /home/pi/raspberry_test_synthese_vocale/systemd/piper-tts.service)
# soit réellement opérationnel avant de démarrer Kodi.
#
# Deux vérifications successives :
#   1. l'unité systemd piper-tts.service est "active" (démarrée avec succès) ;
#   2. si PIPER_SOCKET est renseigné, le socket Unix existe bien sur le
#      disque (preuve que le serveur a fini son initialisation et écoute).
#      Si PIPER_SOCKET n'est pas défini, cette 2e étape est ignorée : on se
#      fie uniquement à l'état actif de l'unité systemd.
#
# Variables :
#   PIPER_SERVICE  nom de l'unité systemd du serveur TTS (défaut: piper-tts.service)
#   PIPER_SOCKET   chemin du socket Unix créé par le serveur (optionnel,
#                  à renseigner si connu, ex: /run/piper-tts/piper.sock)
#   WAIT_TIMEOUT   délai max en secondes avant abandon (défaut: 60)
#   POLL_INTERVAL  intervalle entre deux vérifications en secondes (défaut: 2)

set -uo pipefail

PIPER_SERVICE="${PIPER_SERVICE:-piper-tts.service}"
PIPER_SOCKET="${PIPER_SOCKET:-}"
WAIT_TIMEOUT="${WAIT_TIMEOUT:-60}"
POLL_INTERVAL="${POLL_INTERVAL:-2}"

log() {
    echo "[wait-for-piper-tts] $*"
}

deadline=$(( $(date +%s) + WAIT_TIMEOUT ))

log "Attente de l'activation du service '${PIPER_SERVICE}'..."
while ! systemctl is-active --quiet "$PIPER_SERVICE"; do
    if [ "$(date +%s)" -ge "$deadline" ]; then
        log "ERREUR: timeout, '${PIPER_SERVICE}' n'est pas actif après ${WAIT_TIMEOUT}s."
        exit 1
    fi
    sleep "$POLL_INTERVAL"
done
log "Service '${PIPER_SERVICE}' actif."

if [ -n "$PIPER_SOCKET" ]; then
    log "Attente de la création du socket '${PIPER_SOCKET}'..."
    while [ ! -S "$PIPER_SOCKET" ] && [ ! -e "$PIPER_SOCKET" ]; do
        if [ "$(date +%s)" -ge "$deadline" ]; then
            log "ERREUR: timeout, socket '${PIPER_SOCKET}' introuvable après ${WAIT_TIMEOUT}s."
            exit 1
        fi
        sleep "$POLL_INTERVAL"
    done
    log "Socket Piper disponible."
else
    log "PIPER_SOCKET non défini : vérification limitée à l'état actif du service."
fi

exit 0
