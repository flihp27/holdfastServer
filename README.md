# holdfastServer

Déploiement idempotent d'un serveur `Holdfast: Nations At War` en Docker, avec un point d'entrée unique pour une première installation ou une mise à jour répétable.

## Ce que fournit le dépôt

- une image locale construite depuis `Dockerfile`
- un service `Holdfast` via `compose.yaml`
- un script unique `scripts/install-update.sh`
- une configuration rendue dans `state/config/serverconfig_custom.txt`
- un guide cible Linux `x86_64` dans `docs/linux-x86_64.md`
- une pile d'administration optionnelle dans `compose.admin.yaml`

## Position actuelle

La cible supportée et recommandée est maintenant :

- un hôte Linux `x86_64`
- ou une VM Linux `x86_64`
- ou un nœud Proxmox / un PC physique Linux `x86_64`

Le dépôt n'essaie plus de supporter Apple Silicon en exécution réelle du serveur Holdfast.

## Démarrage rapide

```bash
cp .env.example .env
bash scripts/install-update.sh
```

Le script :

- crée `.env` depuis l'exemple s'il manque
- rend la configuration Holdfast
- build l'image Docker
- crée le conteneur s'il n'existe pas
- sinon ne le recrée que si l'image ou la configuration ont changé
- sinon fait une mise à jour idempotente sans recréation
- attend ensuite un état `healthy` et affiche un résumé de santé lisible

## Ports exposés

- `SERVER_PORT` en UDP pour le trafic de jeu
- `STEAM_COMMUNICATIONS_PORT` en UDP pour le trafic Steam
- `STEAM_QUERY_PORT` en UDP pour la découverte du serveur

## Historique des essais

Ce dépôt a été testé progressivement sur plusieurs stratégies locales avant d'être recentré sur `x86_64`.

Ce qui a été essayé :

- Docker Desktop sur Mac Apple Silicon avec image `linux/amd64`
- téléchargement du serveur dédié via `steamcmd` Linux dans le conteneur
- contournement Apple Silicon avec `steamcmd` macOS côté host
- partage des fichiers téléchargés vers Docker
- VM UTM Debian 12 (Rosetta)
- exécution du serveur Holdfast dans cette VM UTM

Ce qui a fonctionné :

- la build Docker
- le téléchargement complet de l'app Steam `1424230`
- le déploiement idempotent
- le montage des fichiers et le démarrage du conteneur

Ce qui n'a pas fonctionné :

- l'exécution du runtime Holdfast sous traduction `amd64` sur Apple Silicon
- l'exécution du runtime Holdfast dans UTM Debian 12 (Rosetta)

Le symptôme final observé dans les deux cas était le même :

- crash du binaire avec `exit code 134`
- assertion Mono dans `mono/.../x86-codegen.h`

Conclusion :

- le problème n'était pas Docker lui-même
- le problème n'était plus SteamCMD
- le problème est le runtime Holdfast/Mono sous traduction `amd64` sur Apple Silicon

Pour cette raison, le code exécutable a été nettoyé de tous les modes Apple Silicon / UTM, et la cible officielle est redevenue Linux `x86_64`.

## Guide de déploiement

Le guide détaillé pour une VM locale, Proxmox ou un PC Linux `x86_64` est ici :

`docs/linux-x86_64.md`

Ce guide est celui à suivre pour une future utilisation sur un PC Windows 11 via une VM Linux `x86_64`.

## Hardening inclus

- utilisateur non-root dans l'image
- `no-new-privileges`
- `cap_drop: ALL`
- limites de processus et de fichiers
- séparation entre données persistantes et image
- pas d'endpoint web d'admin exposé par défaut

## Tests

```bash
bash tests/test_install_update.sh
```

## Vérification post-déploiement

Le healthcheck Docker ne se limite plus à vérifier que le processus existe :

- il échoue sur des erreurs critiques observées en pratique comme `Unable to initialize Steam`
- il attend un signal runtime utile comme `Loading Round ID` ou `Finished loading map`

Le script `scripts/install-update.sh` attend cet état de santé et affiche ensuite :

- l'état Docker du conteneur
- l'état du healthcheck
- le dernier signal runtime utile
- la dernière erreur critique si une est détectée

## Références techniques

- wiki officiel Holdfast pour l'hébergement et la configuration du serveur
- SteamDB pour l'App ID Linux du serveur dédié
