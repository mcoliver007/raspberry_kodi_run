#!/usr/bin/env bash
#
# start-kodi.sh — lance Kodi avec la commande définie par KODI_EXEC
# (config/kodi-service.env), pour permettre de personnaliser la commande
# sans modifier kodi.service ni toucher au repo.

set -euo pipefail

KODI_EXEC="${KODI_EXEC:-/usr/bin/kodi}"

exec $KODI_EXEC
