# raspberry_kodi_run

Service de démarrage automatique de Kodi sur Raspberry Pi 3B, qui attend
que la chaîne audio soit prête avant de lancer Kodi :

1. le serveur PulseAudio de la session utilisateur `pi` répond ;
2. une enceinte Bluetooth déjà appairée est **connectée** : un sink
   `bluez_sink.*` apparaît dans `pactl list sinks` (PulseAudio décharge ce
   sink automatiquement à la déconnexion, donc sa simple présence prouve la
   connexion — son état `RUNNING`/`IDLE`/`SUSPENDED` n'est pas vérifié, un
   sink `SUSPENDED` est juste un sink connecté mais inactif) ;
3. le service de synthèse vocale Piper (`piper-tts.service`) est actif ;
4. **alors seulement** Kodi démarre — même si aucun câble HDMI n'est
   branché sur la Pi (aucune dépendance sur un écran/HDMI n'est ajoutée,
   Kodi/KMS gère le hotplug lui-même) ;
5. quelques secondes après le démarrage de Kodi, une annonce vocale via
   Piper confirme que Kodi est lancé et que le son sort bien (vérification
   à l'oreille, sans avoir à regarder l'écran).

Ce dépôt suit la même convention que `piper-tts.service`
(voir [raspberry_test_synthese_vocale](https://github.com/mcoliver007/raspberry_test_synthese_vocale)) :
des **unités systemd utilisateur**, liées symboliquement au repo
(`systemctl --user link`) plutôt que copiées — toute modification des
fichiers du repo est prise en compte après un simple `daemon-reload`, sans
réinstallation.

**Important : le repo doit rester cloné en permanence dans
`~/raspberry_kodi_run`** (ex: `/home/pi/raspberry_kodi_run`), car les
unités référencent ce chemin via le spécificateur systemd `%h`.

## Fichiers

- `systemd/kodi-wait-ready.service` : unité oneshot qui exécute les deux
  scripts d'attente et bloque tant que les conditions ne sont pas remplies.
- `systemd/kodi.service` : lance Kodi (via `scripts/start-kodi.sh`), avec
  `After=`/`Requires=` sur `kodi-wait-ready.service`.
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
- `scripts/start-kodi.sh` : petit wrapper qui exécute `KODI_EXEC` (défini
  dans `config/kodi-service.env`), pour permettre de personnaliser la
  commande de lancement sans toucher à `kodi.service`.
- `config/kodi-service.env.example` : modèle de configuration. À copier en
  `config/kodi-service.env` (non versionné, tes réglages locaux restent
  intacts après un `git pull`).
- `scripts/install.sh` : lie les unités, active les services, active le
  démarrage sans connexion (`loginctl enable-linger`).
- `scripts/list-addon-services.py` : liste les addons Kodi ayant un service
  en arrière-plan (`service.py`), avec leur origine (dépôt officiel ou
  tiers) — voir « Diagnostic : crash Python au démarrage/arrêt de Kodi ».
- `scripts/diagnose-shutdown-crash.sh` : aide à corréler un SIGSEGV survenu
  à l'arrêt de l'interpréteur Python avec l'addon en cause (log noyau,
  coredump, log Kodi).
- `scripts/remove-addon.sh` : désactive (réversible, via l'API Kodi) ou
  désinstalle proprement un addon.

## Installation sur la Raspberry Pi

```bash
git clone <ce dépôt> /home/pi/raspberry_kodi_run
cd /home/pi/raspberry_kodi_run
./scripts/install.sh
```

**Ne pas lancer ce script avec `sudo`** : il doit tourner en tant
qu'utilisateur `pi` (les unités sont des services *utilisateur*). Il
invoque `sudo` lui-même, uniquement pour la commande `loginctl
enable-linger` qui nécessite les droits root.

À la première exécution, `config/kodi-service.env` est créé à partir de
`config/kodi-service.env.example`. Adapte-le si besoin :

| Variable        | Rôle                                                        | Défaut               |
|-----------------|--------------------------------------------------------------|----------------------|
| `KODI_EXEC`     | commande de lancement de Kodi (celle utilisée manuellement)   | `/usr/bin/kodi`      |
| `BT_SINK_MATCH` | motif du sink PulseAudio Bluetooth                            | `bluez_sink`         |
| `PIPER_SERVICE` | nom de l'unité systemd utilisateur du TTS Piper               | `piper-tts.service`  |
| `PIPER_SOCKET`  | chemin du socket Unix Piper                                   | `/tmp/piper_tts.sock` |
| `WAIT_TIMEOUT`  | délai max (s) pour chaque étape d'attente                     | `90`                 |
| `ANNOUNCE_TEXT` | phrase annoncée vocalement une fois Kodi démarré               | `Kodi est démarré. Le son fonctionne correctement.` |

Après modification de `config/kodi-service.env` :
```bash
systemctl --user restart kodi-wait-ready.service kodi.service
```

Après modification d'un fichier dans `systemd/` (grâce au lien
symbolique, pas besoin de relancer `install.sh`) :
```bash
systemctl --user daemon-reload
```

## Détails utiles

- **Lancement de Kodi** : `KODI_EXEC=/usr/bin/kodi` sans option
  particulière — c'est ce que fait la plupart des gens qui lancent Kodi en
  CLI sur Raspberry Pi OS (accès direct à l'écran via KMS/DRM, pas besoin de
  X ni de `--standalone`). Si un jour tu utilises une télécommande
  infrarouge, ajoute `--lircdev /dev/lirc0` dans `KODI_EXEC`.
- **PulseAudio** : comme `kodi-wait-ready.service` est une unité
  utilisateur (même session que PulseAudio), le script appelle `pactl`
  directement, sans bascule d'utilisateur ni détection système/session.
- **Socket Piper** : `/tmp/piper_tts.sock` est vérifié en plus de l'état
  actif de `piper-tts.service`, pour s'assurer que le serveur a bien
  terminé son initialisation avant de démarrer Kodi.
- **Annonce vocale de confirmation** : suit le protocole du serveur Piper
  (une ligne JSON `{"mode": "fast", "text": "..."}` envoyée sur le socket ;
  le serveur synthétise et joue lui-même l'audio). Le mode `fast` est utilisé
  car le texte est court. Personnalisable via `ANNOUNCE_TEXT`.

## Diagnostic : crash Python au démarrage/arrêt de Kodi

Symptôme typique : Kodi crashe (SIGSEGV) dans `PyObject_GC_UnTrack`
(libpython3.9) pendant l'arrêt de l'interpréteur Python — cause fréquente :
un addon communautaire avec un **service en arrière-plan** (`service.py`,
extension `xbmc.service`) laisse un thread Python actif (timer, requête
réseau, etc.) au moment où Kodi finalise l'interpréteur. N'importe quel
addon avec un service peut être en cause, pas nécessairement celui qu'on
soupçonne au premier abord — d'où l'intérêt d'isoler le vrai coupable
avant de désinstaller au hasard.

Trois scripts, à lancer sur la Pi (utilisateur `pi`, pas root) :

1. **Lister les suspects potentiels** — tous les addons avec un service en
   arrière-plan, avec leur dépôt d'origine (les dépôts tiers non officiels,
   comme un dépôt communautaire type « funstersplace », sont signalés) :
   ```bash
   ./scripts/list-addon-services.py --all
   ```

2. **Isoler le vrai coupable** — corrèle un segfault récent (log noyau) avec
   les services actifs, et surtout tente d'extraire un **backtrace du
   coredump** (seule preuve fiable ; la corrélation par log seule n'est
   qu'indicative, plusieurs services tournant en parallèle) :
   ```bash
   ./scripts/diagnose-shutdown-crash.sh
   ```
   Si `systemd-coredump` n'est pas encore installé, le script indique la
   commande à lancer, puis à relancer après le prochain crash pour obtenir
   un backtrace exploitable (idéalement avec `python3-dbg` pour le niveau
   Python via `py-bt`, pas seulement le niveau C).

3. **Désactiver ou désinstaller** l'addon identifié :
   ```bash
   # Réversible : l'addon reste installé mais ne redémarre plus
   # (nécessite Kodi lancé + serveur web HTTP activé dans les réglages) :
   ./scripts/remove-addon.sh <addon-id> --disable-only

   # Désinstallation complète (arrête kodi.service, supprime le dossier
   # de l'addon + ses données) :
   ./scripts/remove-addon.sh <addon-id>
   ```
   Pour retirer aussi un dépôt tiers non sécurisé une fois les addons
   concernés désinstallés : `./scripts/remove-addon.sh repository.<id>`.

### Cas résolu (2026-08-03) : ce n'était pas un addon

Sur cette installation, l'analyse du backtrace de coredump (étape 2
ci-dessus, `gdb` + `info sharedlibrary` sur le coredump) a montré que le
crash **n'était pas causé par un addon** (ni `plugin.video.vstream`, ni le
dépôt tiers funstersplace), mais par une bibliothèque Python installée au
niveau système :

```
/usr/local/lib/python3.9/dist-packages/charset_normalizer/cd.cpython-39-arm-linux-gnueabihf.so
```

`charset_normalizer` est une dépendance standard de `requests`, utilisée
par la quasi-totalité des addons vidéo qui font des requêtes HTTP — pas
seulement vstream. Ses modules `cd.py`/`md.py` peuvent être compilés en
extension native (mypyc) pour la performance ; la version pré-compilée
récupérée via piwheels sur cette Pi (ARMhf) corrompt la mémoire pendant un
`getattr()` déclenché par un import, avec un SIGSEGV dans
`PyObject_GC_UnTrack` (libpython3.9) au passage. Comme Kodi utilise le
`libpython3.9` du système, il voit (et est affecté par) ces paquets `pip`
globaux.

**Correctif** (réinstallation en pur Python, sans extension compilée) :
```bash
sudo pip3 uninstall -y charset-normalizer
sudo pip3 install --no-binary=charset-normalizer charset-normalizer

# Vérifier (doit afficher un chemin .py, pas .so) :
python3 -c "import charset_normalizer.cd as m; print(m.__file__)"
```
Par défaut, une build depuis la source (`--no-binary`) ne compile pas
l'extension mypyc — seule une wheel pré-compilée (comme celle de piwheels)
l'embarque.

Si le SIGSEGV revient malgré ce correctif, reprendre le diagnostic à
l'étape 2 : le nouveau coredump peut pointer vers une autre cause.

## Test manuel sans redémarrer la Pi

```bash
systemctl --user start kodi-wait-ready.service
journalctl --user -u kodi-wait-ready.service -f
systemctl --user start kodi.service
journalctl --user -u kodi.service -u kodi-announce-ready.service -f
```
