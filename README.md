# rentingminers

Image Docker pour miner sur des machines louées (vast.ai, Clore.ai…) :

- **GPU NVIDIA** : SRBMiner-MULTI ou BzMiner, au choix (variable `MINER`) ;
- **CPU** : XMRig sur Monero, en option (variables `CPU_*`).

Image publiée : `clusmi/rentingminers:latest` (publique).

## Comment l'image est construite

Le workflow GitHub (`.github/workflows/build.yml`) :

1. cherche la **dernière version stable** de chaque mineur sur sa page GitHub officielle
   (`doktor83/SRBMiner-Multi`, `bzminer/bzminer`, `xmrig/xmrig`) ;
2. télécharge l'archive Linux et **vérifie son empreinte SHA-256** (celle que GitHub a
   enregistrée quand l'auteur a publié le fichier) : si elle ne correspond pas, la
   construction échoue ;
3. construit l'image et l'envoie sur Docker Hub en `clusmi/rentingminers:latest`.

Les versions incluses s'affichent dans le résumé du workflow et au démarrage du conteneur.

## Mise en place (une seule fois)

1. **Docker Hub** : crée le dépôt `rentingminers` (public). Ton token *Read & Write*
   existant fonctionne.
2. **GitHub** : crée un dépôt et envoie les fichiers **à la racine**, dossiers `.github` et
   `scripts` compris (pas dans un sous-dossier).
3. Dans le dépôt GitHub : *Settings → Secrets and variables → Actions → New repository secret*
   - `DOCKERHUB_USERNAME` : ton identifiant Docker Hub (`clusmi`)
   - `DOCKERHUB_TOKEN` : ton token Docker Hub
4. Onglet **Actions** → *Construire et publier l'image* → **Run workflow**.

Pour récupérer de nouvelles versions des mineurs, relance simplement le workflow.

## Variables d'environnement

### GPU (obligatoire)

| Variable | Obligatoire | Défaut | Rôle |
|---|---|---|---|
| `MINER` | non | `srbminer` | `srbminer` ou `bzminer` |
| `COIN` | non | `pearl` | `pearl`, `quantus`, ou tout autre nom d'algorithme (passé tel quel) |
| `POOL` | **oui** | | adresse:port de la pool, ex. `prl.kryptex.network:7048` |
| `WALLET` | **oui** | | ton adresse de wallet |
| `WORKER` | non | | nom du worker affiché par la pool |
| `PASS` | non | | mot de passe pool (rarement utile) |
| `EXTRA_ARGS` | non | | options en plus, passées telles quelles au mineur GPU |

`ALGO` est accepté à la place de `COIN` (`ALGO=pearlhash` fonctionne).

| `COIN` | SRBMiner | BzMiner |
|---|---|---|
| `pearl` | `--algorithm pearlhash` | `-a pearl` |
| `quantus` | `--algorithm quantus` | `-a quantus` |

### CPU avec XMRig (optionnel)

Le minage CPU démarre seulement si `CPU_POOL` **et** `CPU_WALLET` sont renseignés.

| Variable | Défaut | Rôle |
|---|---|---|
| `CPU_POOL` | | adresse:port de la pool Monero |
| `CPU_WALLET` | | ton adresse Monero |
| `CPU_WORKER` | | nom du worker, envoyé en mot de passe de pool (`-p`) et en `--rig-id` |
| `CPU_THREADS` | XMRig choisit | nombre de threads CPU |
| `CPU_COIN` | `monero` | valeur passée à `--coin` |
| `CPU_EXTRA_ARGS` | | options en plus pour XMRig (ex. `--tls` pour une pool en SSL) |

Sans `CPU_THREADS`, XMRig règle lui-même le nombre de threads. Pour RandomX, il le fixe
selon la mémoire cache du processeur, ce qui est en général le plus rapide : il n'utilise
donc pas forcément tous les threads de la machine. Fixe `CPU_THREADS` pour comparer.

Les lignes de XMRig sont préfixées par `[cpu]` dans les logs du conteneur.

### Commun

| Variable | Défaut | Rôle |
|---|---|---|
| `RESTART_DELAY` | `10` | secondes avant relance d'un mineur qui s'arrête |
| `DRY_RUN` | | `1` : affiche les commandes sans miner (pour vérifier) |

Chaque mineur est relancé seul s'il s'arrête : un plantage de XMRig n'interrompt pas le
GPU, et inversement.

Réglages fixes : minage CPU désactivé dans le mineur GPU (SRBMiner `--disable-cpu`,
BzMiner `--nvidia`), journal en texte simple (BzMiner `-o log`, XMRig `--no-color`).
SRBMiner n'affiche rien hors d'un terminal : son journal (`--log-file`) est recopié dans
les logs du conteneur.

## Template vast.ai

- **Image Path:Tag** : `clusmi/rentingminers`, version `latest`
- **Launch mode** : **Docker ENTRYPOINT**
- **Champ des arguments** : **vide**
- **Environment Variables** : `MINER`, `POOL`, `WALLET`, `WORKER`, et pour le CPU
  `CPU_POOL`, `CPU_WALLET`, `CPU_WORKER` (+ `CPU_THREADS` si besoin)

## À savoir

- **Frais** : chaque mineur prélève des frais de développeur fixés par son auteur
  (XMRig : 1 %). Compare les mineurs sur le hashrate vu par la pool.
- **XMRig en conteneur** : les messages sur les « huge pages » et les registres « MSR »
  sont normaux. Ces optimisations demandent des droits que seul l'hôte a ; sans elles,
  RandomX perd environ 10 à 20 %.
- **Impact sur le GPU** : le mineur GPU a besoin d'un peu de CPU. Compare le hashrate GPU
  vu par la pool avec et sans minage CPU, et réduis `CPU_THREADS` si besoin.

## Dépannage

- **`POOL est obligatoire` / `WALLET est obligatoire`** : variable GPU manquante.
- **`CPU_POOL est renseigne mais CPU_WALLET manque`** (ou l'inverse) : il faut les deux.
- **Le worker n'apparaît pas sur la pool** : certaines pools attendent le worker collé au
  wallet. Mets `WALLET=adresse.worker` et laisse `WORKER` vide.
- **Test sans miner** : ajoute `DRY_RUN=1`, le log montre les commandes exactes.
- **`No such container` sur vast.ai** : l'image n'a pas pu être téléchargée ; vérifie que
  le dépôt Docker Hub est public.
