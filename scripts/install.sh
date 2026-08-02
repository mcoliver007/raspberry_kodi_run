#!/usr/bin/env bash
#
# install.sh — installe le service de démarrage automatique de Kodi comme
# unités systemd *utilisateur*, liées symboliquement (systemctl --user link)
# aux fichiers du repo — même convention que piper-tts.service.
#
# IMPORTANT : le repo doit rester en permanence à l'emplacement
#   ~/raspberry_kodi_run   (ex: /home/pi/raspberry_kodi_run)
# car les unités référencent ce chemin via le spécificateur systemd "%h".
#
# À exécuter en tant qu'utilisateur "pi" (PAS avec sudo), depuis le repo :
#   ~/raspberry_kodi_run/scripts/install.sh
#
# Une seule étape nécessite les droits root (activer le démarrage des
# services utilisateur sans connexion) : le script invoquera "sudo" lui-même
# uniquement pour cette commande (loginctl enable-linger).

set -euo pipefail

if [ "$(id -u)" -eq 0 ]; then
    echo "Ce script doit être exécuté en tant qu'utilisateur normal (pi), PAS avec sudo." >&2
    echo "Il invoquera sudo lui-même si besoin pour la seule étape qui le nécessite." >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
EXPECTED_ROOT="${HOME}/raspberry_kodi_run"

if [ "$REPO_ROOT" != "$EXPECTED_ROOT" ]; then
    echo "ERREUR: le repo doit se trouver dans '${EXPECTED_ROOT}' (trouvé: '${REPO_ROOT})." >&2
    echo "Les unités systemd référencent ce chemin fixe via %h/raspberry_kodi_run." >&2
    exit 1
fi

echo "==> Rendre les scripts exécutables"
chmod +x "$REPO_ROOT"/scripts/*.sh "$REPO_ROOT"/scripts/*.py

echo "==> Préparation de la configuration (config/kodi-service.env)"
if [ ! -f "$REPO_ROOT/config/kodi-service.env" ]; then
    cp "$REPO_ROOT/config/kodi-service.env.example" "$REPO_ROOT/config/kodi-service.env"
    echo "    Créé à partir de l'exemple. Vérifie/adapte : $REPO_ROOT/config/kodi-service.env"
else
    echo "    Déjà présent, non modifié : $REPO_ROOT/config/kodi-service.env"
fi

echo "==> Lien symbolique des unités systemd utilisateur"
mkdir -p "$HOME/.config/systemd/user"
systemctl --user link \
    "$REPO_ROOT/systemd/kodi-wait-ready.service" \
    "$REPO_ROOT/systemd/kodi.service" \
    "$REPO_ROOT/systemd/kodi-announce-ready.service"

echo "==> Activation des services"
systemctl --user daemon-reload
systemctl --user enable kodi-wait-ready.service
systemctl --user enable kodi.service
systemctl --user enable kodi-announce-ready.service

echo "==> Activation du démarrage sans connexion (loginctl enable-linger)"
if command -v loginctl >/dev/null && loginctl show-user "$USER" -p Linger 2>/dev/null | grep -q "Linger=yes"; then
    echo "    Linger déjà actif pour ${USER}."
else
    sudo loginctl enable-linger "$USER"
    echo "    Linger activé pour ${USER}."
fi

cat <<EOF

Installation terminée.

Comme les unités sont liées (pas copiées), toute modification des fichiers
dans $REPO_ROOT/systemd/ est prise en compte après :
  systemctl --user daemon-reload

Vérifications à faire avant de redémarrer :
  - Adapte si besoin $REPO_ROOT/config/kodi-service.env (notamment KODI_EXEC
    si ta commande de lancement de Kodi diffère de "/usr/bin/kodi").
  - Confirme que piper-tts.service est bien actif :
      systemctl --user status piper-tts.service

Test manuel sans redémarrer :
  systemctl --user start kodi-wait-ready.service
  journalctl --user -u kodi-wait-ready.service -f
  systemctl --user start kodi.service
  journalctl --user -u kodi.service -u kodi-announce-ready.service -f
EOF
