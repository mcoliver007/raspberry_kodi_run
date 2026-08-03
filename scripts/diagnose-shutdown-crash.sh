#!/usr/bin/env bash
#
# diagnose-shutdown-crash.sh
#
# Aide à isoler quel addon (thread Python en arrière-plan) est responsable
# d'un SIGSEGV survenant à l'arrêt de l'interpréteur Python de Kodi
# (typiquement dans PyObject_GC_UnTrack / libpython3.9, pendant la
# finalisation de l'interpréteur).
#
# Deux volets, à ne pas confondre :
#   1. Corrélation par horodatage (indicative) : cherche les segfaults
#      kodi/python dans le journal noyau et liste les addons dont le
#      service.py tournait, d'après le log Kodi -> une liste de candidats,
#      PAS une preuve (plusieurs services tournent en même temps).
#   2. Backtrace du coredump (preuve définitive) : si systemd-coredump est
#      actif, extrait le backtrace de TOUS les threads du dernier coredump
#      Kodi (C avec "thread apply all bt", et niveau Python avec
#      "thread apply all py-bt" si les symboles de debug sont installés).
#      C'est la seule méthode qui identifie le addon fautif avec certitude
#      plutôt que par déduction.
#
# Ce script est en LECTURE SEULE : il ne modifie rien sur le système (les
# commandes d'installation de paquets suggérées sont affichées, jamais
# exécutées automatiquement).
#
# Variables :
#   KODI_HOME  dossier de configuration Kodi (défaut: ~/.kodi)

set -uo pipefail

KODI_HOME="${KODI_HOME:-$HOME/.kodi}"

log() {
    echo "[diagnose-shutdown-crash] $*"
}

echo "=== 1. Segfaults récents dans le journal noyau (kodi/python) ==="
kernel_log="$(journalctl -k -o short-iso --no-pager 2>/dev/null)"
journalctl_rc=$?
segfault_lines="$(echo "$kernel_log" | grep -iE 'segfault|general protection fault' | grep -iE 'kodi|python' || true)"

if [ -z "$segfault_lines" ]; then
    if [ "$journalctl_rc" -ne 0 ] && [ "$(id -u)" -ne 0 ]; then
        log "Aucun résultat — vérifie les droits d'accès au journal (essaie: sudo journalctl -k)."
    else
        log "Aucun segfault kodi/python trouvé sur le boot courant."
        log "Pour le boot précédent (si la Pi a redémarré après le crash): journalctl -k -b -1"
    fi
else
    log "Segfault(s) trouvé(s) (5 plus récents) :"
    echo "$segfault_lines" | tail -n 5
fi
echo

echo "=== 2. Coredump Kodi (backtrace = preuve définitive) ==="
if ! command -v coredumpctl >/dev/null 2>&1; then
    log "coredumpctl indisponible (paquet systemd-coredump non installé)."
    log "Pour capturer un backtrace exploitable au PROCHAIN crash :"
    log "  sudo apt install -y systemd-coredump gdb python3-dbg"
    log "  systemctl status systemd-coredump.socket   # doit être 'active'"
    log "Puis relance ce script après le prochain crash."
else
    dump_line="$(coredumpctl list --no-pager --no-legend 2>/dev/null | grep -i kodi | tail -n 1 || true)"
    if [ -z "$dump_line" ]; then
        log "Aucun coredump Kodi trouvé pour l'instant."
        log "Vérifie que la capture est active : systemctl status systemd-coredump.socket"
        log "et relance ce script après le prochain crash."
    else
        log "Dernier coredump Kodi :"
        echo "  $dump_line"
        dump_pid="$(echo "$dump_line" | awk '{print $2}')"
        echo
        if command -v gdb >/dev/null 2>&1; then
            log "Extraction du backtrace de TOUS les threads (PID coredump: ${dump_pid})..."
            log "(si 'py-bt' échoue avec une exception Python, les symboles de debug ne sont pas"
            log " installés pour cette version de libpython3.9 — le backtrace C ci-dessous reste"
            log " exploitable : cherche le nom de l'addon/du module dans les frames. Pour activer"
            log " py-bt : sudo apt install -y python3-dbg)"
            echo
            coredumpctl debug "$dump_pid" --no-pager \
                --debugger-arguments="-batch -ex 'set pagination off' -ex 'thread apply all bt' -ex 'thread apply all py-bt'" \
                2>&1 | tail -n 300
        else
            log "gdb non installé : sudo apt install -y gdb python3-dbg"
            log "puis : coredumpctl debug ${dump_pid} --debugger-arguments=\"-batch -ex 'thread apply all bt' -ex 'thread apply all py-bt'\""
        fi
    fi
fi
echo

echo "=== 3. Services Python actifs d'après le log Kodi (candidats) ==="
kodi_log="$KODI_HOME/temp/kodi.log"
kodi_old_log="$KODI_HOME/temp/kodi.old.log"

if [ ! -f "$kodi_log" ] && [ ! -f "$kodi_old_log" ]; then
    log "Log Kodi introuvable ($kodi_log). Renseigne KODI_HOME si Kodi n'utilise pas ~/.kodi."
else
    log "Addons dont le service.py a démarré (CPythonInvoker), d'après le log :"
    found=0
    for f in "$kodi_old_log" "$kodi_log"; do
        [ -f "$f" ] || continue
        matches="$(grep -iE 'CPythonInvoker.*service\.py.*start processing' "$f" 2>/dev/null | tail -n 20 || true)"
        if [ -n "$matches" ]; then
            found=1
            echo "  -- $f --"
            echo "$matches"
        fi
    done
    if [ "$found" -eq 0 ]; then
        log "Aucune ligne CPythonInvoker/service.py trouvée (loglevel debug désactivé ?)."
        log "Active-le : Kodi > Réglages > Système > Journalisation > 'Activer le débogage',"
        log "reproduis le crash, puis relance ce script."
    fi
fi
echo

log "Compare ces candidats avec la sortie de ./scripts/list-addon-services.py"
log "(tout addon présent ici ET signalé comme suspect = candidat sérieux, vstream ou non)."
log "Rappel : seul le backtrace du coredump (partie 2) identifie le coupable avec certitude."
