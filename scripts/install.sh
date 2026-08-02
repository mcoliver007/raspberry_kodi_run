#!/usr/bin/env bash
#
# install.sh — installe le service de démarrage automatique de Kodi
# (avec attente audio + enceinte Bluetooth + TTS Piper) sur la Raspberry Pi.
#
# À exécuter en root (sudo) depuis une copie locale du dépôt sur la Pi :
#   sudo ./scripts/install.sh
#
# Variables d'environnement acceptées :
#   KODI_USER     utilisateur Linux sous lequel Kodi doit tourner (défaut: pi)
#   KODI_EXEC     commande de lancement de Kodi, identique à celle utilisée
#                 manuellement jusqu'ici (défaut: /usr/bin/kodi)
#   BT_SINK_MATCH motif du sink PulseAudio Bluetooth (défaut: bluez_sink)
#   PIPER_SERVICE nom de l'unité systemd du serveur TTS (défaut: piper-tts.service)
#   PIPER_SOCKET  chemin du socket Unix Piper (défaut: /tmp/piper_tts.sock)
#   WAIT_TIMEOUT  timeout en secondes pour chaque étape d'attente (défaut: 90)

set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "Ce script doit être exécuté en root (sudo ./scripts/install.sh)." >&2
    exit 1
fi

KODI_USER="${KODI_USER:-pi}"
KODI_EXEC="${KODI_EXEC:-/usr/bin/kodi}"
BT_SINK_MATCH="${BT_SINK_MATCH:-bluez_sink}"
PIPER_SERVICE="${PIPER_SERVICE:-piper-tts.service}"
PIPER_SOCKET="${PIPER_SOCKET:-/tmp/piper_tts.sock}"
WAIT_TIMEOUT="${WAIT_TIMEOUT:-90}"

if ! id "$KODI_USER" >/dev/null 2>&1; then
    echo "ERREUR: l'utilisateur '${KODI_USER}' n'existe pas sur ce système." >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

echo "==> Installation des scripts dans /usr/local/bin"
install -m 755 "$REPO_ROOT/scripts/wait-for-bluetooth-audio.sh" /usr/local/bin/wait-for-bluetooth-audio.sh
install -m 755 "$REPO_ROOT/scripts/wait-for-piper-tts.sh" /usr/local/bin/wait-for-piper-tts.sh

echo "==> Écriture de la configuration /etc/default/kodi-service"
cat > /etc/default/kodi-service <<EOF
# Généré par scripts/install.sh — modifiable manuellement puis
# "systemctl restart kodi-wait-ready.service kodi.service"
KODI_USER=${KODI_USER}
BT_SINK_MATCH=${BT_SINK_MATCH}
PIPER_SERVICE=${PIPER_SERVICE}
PIPER_SOCKET=${PIPER_SOCKET}
WAIT_TIMEOUT=${WAIT_TIMEOUT}
POLL_INTERVAL=2
EOF

echo "==> Installation des unités systemd"
sed -e "s#__KODI_USER__#${KODI_USER}#g" \
    -e "s#__KODI_EXEC__#${KODI_EXEC}#g" \
    "$REPO_ROOT/systemd/kodi.service" > /etc/systemd/system/kodi.service

install -m 644 "$REPO_ROOT/systemd/kodi-wait-ready.service" /etc/systemd/system/kodi-wait-ready.service

echo "==> Rechargement de systemd et activation des services"
systemctl daemon-reload
systemctl enable kodi-wait-ready.service
systemctl enable kodi.service

cat <<EOF

Installation terminée.

Vérifications à faire avant de redémarrer :
  - Confirme que '${PIPER_SERVICE}' est bien lié/activé :
      systemctl status ${PIPER_SERVICE}
  - Si tu connais le chemin du socket Unix de Piper, relance l'install avec
    PIPER_SOCKET=/chemin/vers/le.sock pour une vérification plus stricte.
  - Adapte KODI_EXEC si la commande de lancement habituelle de Kodi diffère
    de "${KODI_EXEC}" (édite /etc/systemd/system/kodi.service, ligne ExecStart).

Test manuel sans redémarrer :
  sudo systemctl start kodi-wait-ready.service
  journalctl -u kodi-wait-ready.service -f
  sudo systemctl start kodi.service
EOF
