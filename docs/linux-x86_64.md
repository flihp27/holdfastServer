# Linux x86_64

Guide de deploiement du serveur Holdfast sur une machine virtuelle locale, un noeud Proxmox, ou un PC Linux `x86_64`.

## Cible recommandee

- OS guest ou machine cible: Debian 12 ou Ubuntu 24.04 `x86_64`
- CPU: 4 vCPU minimum
- RAM: 16 Go recommandes
- Disque: 80 Go minimum
- Reseau: bridged ou equivalent si le serveur doit etre visible sur le LAN

## Cas d'usage couverts

- VM locale sous Windows 11 avec Hyper-V, VMware Workstation, VirtualBox ou autre hyperviseur
- VM Proxmox
- PC physique Linux `x86_64`

## Paquets a installer

Debian 12 / Ubuntu :

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl git
```

Installer ensuite Docker Engine et Compose v2 selon la methode de ton environnement.

Verifier :

```bash
docker --version
docker compose version
```

Si seul `docker-compose` est disponible, le projet le supporte aussi.

## Recuperer le projet

Quand le depot sera publie sur GitHub :

```bash
git clone <URL_DU_REPO>
cd <nom-du-repo>
```

## Configuration

Creer le fichier d'environnement :

```bash
cp .env.example .env
```

Verifier au minimum :

- `SERVER_NAME`
- `SERVER_ADMIN_PASSWORD`
- `SERVER_PASSWORD` si le serveur doit etre prive
- `MAXIMUM_PLAYERS`
- `NETWORK_BROADCAST_MODE`
- `SERVER_PORT`
- `STEAM_COMMUNICATIONS_PORT`
- `STEAM_QUERY_PORT`
- `TZ`

## Deploiement

Lancer :

```bash
bash scripts/install-update.sh
```

Ce flux :

- rend la configuration serveur dans `state/config/serverconfig_custom.txt`
- build l'image Docker
- telecharge ou met a jour le serveur dedie via SteamCMD dans le conteneur
- cree le conteneur s'il n'existe pas
- sinon ne le recree que si l'image ou la configuration ont change

## Verification

Verifier l'etat :

```bash
docker ps
docker logs --tail 200 holdfast-server
```

Verifier les ports :

```bash
ss -lun | egrep '20100|8700|27000'
```

## Exposition reseau

Si la VM ou le PC doit etre joignable depuis le LAN :

- utiliser un reseau bridge dans l'hyperviseur, ou l'equivalent Proxmox
- ouvrir les ports UDP :
- `20100`
- `8700`
- `27000`

Depuis un autre poste du reseau, tester l'IP de la VM ou du PC Linux.

## Notes Windows 11

Si tu l'utilises sur un PC Windows 11, la recommandation est :

- creer une VM Linux `x86_64`
- allouer 16 Go de RAM si la machine le permet
- activer un reseau bridge
- cloner ce depot dans la VM Linux
- executer le deploiement depuis la VM, pas depuis Windows

## Notes Proxmox

Recommandations simples :

- VM `q35`
- BIOS `OVMF` ou `SeaBIOS`
- CPU type `host`
- disque SSD ou stockage rapide
- carte reseau en bridge sur le LAN
- snapshots avant changements importants

## Depannage

Si `docker compose` n'existe pas mais `docker-compose` oui :

- le script le gere automatiquement

Si la build echoue sur une vieille chaine Docker :

- mettre a jour Docker
- ou verifier que le `Dockerfile` courant du depot est bien celui a jour

Si le serveur boucle au demarrage :

- lire `docker logs --tail 200 holdfast-server`
- lire `state/logs/outputlog_server.txt`
