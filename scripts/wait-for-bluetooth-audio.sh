#!/usr/bin/env bash
#
# wait-for-bluetooth-audio.sh
#
# Bloque jusqu'à ce que :
#   1. un serveur PulseAudio (mode système OU session utilisateur) réponde ;
#   2. ce serveur ait un sink Bluetooth (bluez_sink.*) actif et non "suspended",
#      c'est-à-dire qu'une enceinte Bluetooth déjà appairée est bien
#      connectée ET reçoit effectivement l'audio.
#
# Variables (surchargeables via l'environnement, cf systemd EnvironmentFile) :
#   KODI_USER     utilisateur dont la session PulseAudio doit être testée
#                 si PulseAudio ne tourne pas en mode système (défaut: pi)
#   BT_SINK_MATCH motif recherché dans le nom du sink (défaut: bluez_sink)
#   WAIT_TIMEOUT  délai max en secondes avant abandon (défaut: 90)
#   POLL_INTERVAL intervalle entre deux vérifications en secondes (défaut: 2)

set -uo pipefail

KODI_USER="${KODI_USER:-pi}"
BT_SINK_MATCH="${BT_SINK_MATCH:-bluez_sink}"
WAIT_TIMEOUT="${WAIT_TIMEOUT:-90}"
POLL_INTERVAL="${POLL_INTERVAL:-2}"

log() {
    echo "[wait-for-bluetooth-audio] $*"
}

# Exécute une commande pactl en essayant successivement :
#   - le bus système (PulseAudio en mode system-wide) ;
#   - la session utilisateur de KODI_USER (PulseAudio en mode --user, cas le
#     plus fréquent sur Raspberry Pi OS).
run_pactl() {
    if pactl "$@" >/tmp/.wfba_out 2>/dev/null; then
        cat /tmp/.wfba_out
        return 0
    fi

    local uid
    uid="$(id -u "$KODI_USER" 2>/dev/null)" || return 1
    local runtime_dir="/run/user/${uid}"

    if [ -d "$runtime_dir" ]; then
        if sudo -u "$KODI_USER" \
            XDG_RUNTIME_DIR="$runtime_dir" \
            DBUS_SESSION_BUS_ADDRESS="unix:path=${runtime_dir}/bus" \
            pactl "$@" >/tmp/.wfba_out 2>/dev/null; then
            cat /tmp/.wfba_out
            return 0
        fi
    fi

    return 1
}

deadline=$(( $(date +%s) + WAIT_TIMEOUT ))

log "Attente du serveur audio PulseAudio (système ou session de '${KODI_USER}')..."
while true; do
    if run_pactl info >/dev/null; then
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
    sinks="$(run_pactl list sinks 2>/dev/null || true)"

    if [ -n "$sinks" ] && echo "$sinks" | grep -q "$BT_SINK_MATCH"; then
        # On isole le bloc du sink bluetooth et on vérifie son état
        # (RUNNING ou IDLE = connecté et prêt ; SUSPENDED = pas de flux/pas
        # vraiment opérationnel).
        state="$(echo "$sinks" | awk -v pat="$BT_SINK_MATCH" '
            /^Sink #/ { in_bt = 0 }
            $0 ~ "Name: .*" pat { in_bt = 1 }
            in_bt && /State:/ { print $2; exit }
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
