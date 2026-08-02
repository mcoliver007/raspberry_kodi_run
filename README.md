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
   Kodi/KMS gère le hotplug lui-même) ;
5. quelques secondes après le démarrage de Kodi, une annonce vocale via
   Piper confirme que Kodi est lancé et que le son sort bien (vérification
   à l'oreille, sans avoir à regarder l'écran).

## Fichiers

- `systemd/kodi-wait-ready.service` : unité oneshot qui exécute les deux
  scripts d'attente et bloque tant que les conditions ne sont pas remplies.
- `systemd/kodi.service` : lance Kodi, avec `After=`/`Requires=` sur
  `kodi-wait-ready.service`.
- `systemd/kodi-announce-ready.service` : unité compagnon de `kodi.service`
  (`WantedBy=kodi.service`) qui envoie une confirmation vocale une fois
  Kodi démarré.
- `scripts/wait-for-bluetooth-audio.sh` : attend PulseAudio + sink
  Bluetooth actif.
- `scripts/wait-for-piper-tts.sh` : attend que `piper-tts.service` soit actif
  (et, si `PIPER_SOCKET` est renseigné, que son socket Unix existe).
- `scripts/announce-kodi-ready.py` : envoie `{"mode": "fast", "text": ...}`
  au socket Piper (`/tmp/piper_tts.sock`) pour l'annonce vocale de
  confirmation.
- `scripts/install.sh` : installe scripts + unités + configuration.

## Installation sur la Raspberry Pi

```bash
git clone <ce dépôt> /home/pi/raspberry_kodi_run
cd /home/pi/raspberry_kodi_run
sudo ./scripts/install.sh
```

Les valeurs par défaut correspondent à ton installation (Kodi lancé
directement en CLI, socket Piper `/tmp/piper_tts.sock`). Tu n'as donc rien
à passer en variable pour une installation standard. Variables disponibles
si besoin d'adapter (toutes optionnelles, valeurs par défaut entre
parenthèses) :

| Variable        | Rôle                                                        | Défaut               |
|-----------------|--------------------------------------------------------------|----------------------|
| `KODI_USER`     | utilisateur Linux sous lequel Kodi tourne                     | `pi`                 |
| `KODI_EXEC`     | commande de lancement de Kodi (celle utilisée manuellement)   | `/usr/bin/kodi`      |
| `BT_SINK_MATCH` | motif du sink PulseAudio Bluetooth                            | `bluez_sink`         |
| `PIPER_SERVICE` | nom de l'unité systemd du TTS Piper                           | `piper-tts.service`  |
| `PIPER_SOCKET`  | chemin du socket Unix Piper                                   | `/tmp/piper_tts.sock` |
| `WAIT_TIMEOUT`  | délai max (s) pour chaque étape d'attente                     | `90`                 |
| `ANNOUNCE_TEXT` | phrase annoncée vocalement une fois Kodi démarré               | `Kodi est démarré. Le son fonctionne correctement.` |

La configuration est écrite dans `/etc/default/kodi-service` et peut être
modifiée après coup sans relancer `install.sh` :

```bash
sudo nano /etc/default/kodi-service
sudo systemctl restart kodi-wait-ready.service kodi.service
```

## Détails utiles

- **Lancement de Kodi** : `ExecStart` est réglé sur `/usr/bin/kodi` sans
  option particulière — c'est ce que fait la plupart des gens qui lancent
  Kodi en CLI sur Raspberry Pi OS (accès direct à l'écran via KMS/DRM, pas
  besoin de X ni de `--standalone`). Si un jour tu utilises une télécommande
  infrarouge, ajoute `--lircdev /dev/lirc0` dans `KODI_EXEC`.
- **PulseAudio** : aucune configuration nécessaire, `wait-for-bluetooth-audio.sh`
  détecte automatiquement s'il tourne en mode système ou en session
  utilisateur (`pi`). Pour vérifier toi-même lequel des deux s'applique :
  ```bash
  pactl info || sudo -u pi XDG_RUNTIME_DIR=/run/user/$(id -u pi) pactl info
  ```
- **Socket Piper** : `/tmp/piper_tts.sock` est vérifié en plus de l'état
  actif de `piper-tts.service`, pour s'assurer que le serveur a bien
  terminé son initialisation avant de démarrer Kodi.
- **Annonce vocale de confirmation** : suit le protocole du serveur Piper
  (une ligne JSON `{"mode": "fast", "text": "..."}` envoyée sur le socket ;
  le serveur synthétise et joue lui-même l'audio). Le mode `fast` est utilisé
  car le texte est court. Personnalisable via `ANNOUNCE_TEXT`.

## Test manuel sans redémarrer la Pi

```bash
sudo systemctl start kodi-wait-ready.service
journalctl -u kodi-wait-ready.service -f
sudo systemctl start kodi.service
journalctl -u kodi.service -f
journalctl -u kodi-announce-ready.service -f
```
