# raspberry_kodi_run

Service de démarrage automatique de Kodi sur Raspberry Pi 3B, qui attend
que la chaîne audio soit prête avant de lancer Kodi :

1. PulseAudio est démarré (mode système **ou** session utilisateur, détecté
   automatiquement) ;
2. une enceinte Bluetooth déjà appairée est **connectée et reçoit
   effectivement l'audio** (sink `bluez_sink.*` à l'état `RUNNING`/`IDLE`,
   pas `SUSPENDED`) ;
3. le service de synthèse vocale Piper (`piper-tts.service`) est actif ;
4. **alors seulement** Kodi démarre — même si aucun câble HDMI n'est
   branché sur la Pi (aucune dépendance sur un écran/HDMI n'est ajoutée,
   Kodi/KMS gère le hotplug lui-même).

## Fichiers

- `systemd/kodi-wait-ready.service` : unité oneshot qui exécute les deux
  scripts d'attente et bloque tant que les conditions ne sont pas remplies.
- `systemd/kodi.service` : lance Kodi, avec `After=`/`Requires=` sur
  `kodi-wait-ready.service`.
- `scripts/wait-for-bluetooth-audio.sh` : attend PulseAudio + sink
  Bluetooth actif.
- `scripts/wait-for-piper-tts.sh` : attend que `piper-tts.service` soit actif
  (et, si `PIPER_SOCKET` est renseigné, que son socket Unix existe).
- `scripts/install.sh` : installe scripts + unités + configuration.

## Installation sur la Raspberry Pi

```bash
git clone <ce dépôt> /home/pi/raspberry_kodi_run
cd /home/pi/raspberry_kodi_run
sudo KODI_USER=pi KODI_EXEC=/usr/bin/kodi-standalone ./scripts/install.sh
```

Variables disponibles (toutes optionnelles, valeurs par défaut entre
parenthèses) :

| Variable        | Rôle                                                        | Défaut               |
|-----------------|--------------------------------------------------------------|----------------------|
| `KODI_USER`     | utilisateur Linux sous lequel Kodi tourne                     | `pi`                 |
| `KODI_EXEC`     | commande de lancement de Kodi (celle utilisée manuellement)   | `/usr/bin/kodi-standalone` |
| `BT_SINK_MATCH` | motif du sink PulseAudio Bluetooth                            | `bluez_sink`         |
| `PIPER_SERVICE` | nom de l'unité systemd du TTS Piper                           | `piper-tts.service`  |
| `PIPER_SOCKET`  | chemin du socket Unix Piper, si connu                         | (aucun, vérif. plus stricte si renseigné) |
| `WAIT_TIMEOUT`  | délai max (s) pour chaque étape d'attente                     | `90`                 |

La configuration est écrite dans `/etc/default/kodi-service` et peut être
modifiée après coup sans relancer `install.sh` :

```bash
sudo nano /etc/default/kodi-service
sudo systemctl restart kodi-wait-ready.service kodi.service
```

## Points à vérifier / adapter sur ta Pi

Ces points n'ont pas pu être confirmés à l'avance et méritent une
vérification avant le premier redémarrage automatique :

- **Commande de lancement de Kodi** : `ExecStart` dans `kodi.service` est
  positionné à `KODI_EXEC` (défaut `/usr/bin/kodi-standalone`). Si tu lances
  Kodi autrement à la main (ex: `startx /usr/bin/kodi -- :0 vt7`, script
  perso...), adapte `KODI_EXEC` lors de l'installation ou édite directement
  `/etc/systemd/system/kodi.service`.
- **Mode PulseAudio (système vs session utilisateur)** : le script
  `wait-for-bluetooth-audio.sh` essaie d'abord le bus système, puis la
  session de `KODI_USER` via `/run/user/<uid>`. Si PulseAudio est lancé
  différemment (ex: PipeWire avec `pipewire-pulse`), le script devrait
  fonctionner tel quel (il utilise `pactl`), mais teste-le manuellement :
  `sudo -u pi XDG_RUNTIME_DIR=/run/user/$(id -u pi) pactl list sinks`.
- **Socket Piper** : le service `piper-tts.service` existant est vérifié
  via `systemctl is-active`. Si tu connais le chemin exact du socket Unix
  qu'il crée, renseigne `PIPER_SOCKET` pour une vérification plus fiable
  (le service peut être "actif" sans que le socket soit encore prêt).

## Test manuel sans redémarrer la Pi

```bash
sudo systemctl start kodi-wait-ready.service
journalctl -u kodi-wait-ready.service -f
sudo systemctl start kodi.service
journalctl -u kodi.service -f
```
