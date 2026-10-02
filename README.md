# rentingminers

Image Docker pour miner sur des machines louées (vast.ai, Clore.ai…) :

- **GPU NVIDIA** : SRBMiner-MULTI ;
- **CPU** : XMRig ou SRBMiner-MULTI, en option.

Les arguments des mineurs sont donnés **tels quels**, dans leur syntaxe d'origine.
Image publiée : `clusmi/rentingminers:latest` (publique).

## Comment l'image est construite

Le workflow GitHub (`.github/workflows/build.yml`) :

1. cherche la **dernière version stable** de chaque mineur sur sa page GitHub officielle
   (`doktor83/SRBMiner-Multi`, `xmrig/xmrig`) ;
2. télécharge l'archive Linux et **vérifie son empreinte SHA-256** (celle que GitHub a
   enregistrée quand l'auteur a publié le fichier) : si elle ne correspond pas, la
   construction échoue ;
3. construit l'image et l'envoie sur Docker Hub en `clusmi/rentingminers:latest`.

Les versions incluses s'affichent dans le résumé du workflow et au démarrage du conteneur.
Pour récupérer de nouvelles versions des mineurs, relance simplement le workflow.

## Mise en place (une seule fois)

1. **Docker Hub** : dépôt `rentingminers` (public).
2. **GitHub** : les fichiers **à la racine** du dépôt, dossiers `.github` et `scripts`
   compris.
3. *Settings → Secrets and variables → Actions* : `DOCKERHUB_USERNAME` (`clusmi`) et
   `DOCKERHUB_TOKEN`.
4. Onglet **Actions** → *Construire et publier l'image* → **Run workflow**.

## Variables

| Variable | Valeurs | Rôle |
|---|---|---|
| `GPU_MINER` | `srbminer` (défaut, seule valeur) | XMRig ne mine que sur CPU |
| `GPU_ARGS` | **obligatoire** | arguments SRBMiner, tels quels |
| `CPU_MINER` | `xmrig` (défaut) ou `srbminer` | |
| `CPU_ARGS` | vide = pas de minage CPU | arguments du mineur CPU, tels quels |
| `RESTART_DELAY` | `10` | secondes avant relance d'un mineur qui s'arrête |
| `DRY_RUN` | | `1` : affiche les commandes finales sans miner |

Une valeur avec des espaces se met entre guillemets dans les options Docker du template :
`-e GPU_ARGS="--algorithm pearlhash --pool ... --wallet ..."`. Des guillemets à
l'intérieur de la valeur marchent aussi (`--password "mot de passe"`).

### Ce que l'image ajoute automatiquement

Les arguments partent tels quels, l'image ajoute seulement ce qu'il faut pour tourner
dans un conteneur. **Une option déjà présente dans tes arguments n'est pas ajoutée.**

| Processus | Options ajoutées | Pourquoi |
|---|---|---|
| SRBMiner GPU | `--disable-cpu`, `--log-file` | GPU seulement ; SRBMiner n'écrit rien dans les logs sans fichier |
| SRBMiner CPU | `--disable-gpu`, `--disable-numa-binding`, `--log-file` | CPU seulement ; voir « machines à plusieurs processeurs » |
| XMRig | `--randomx-no-numa`, `--no-color` | idem ; logs lisibles |

Le SRBMiner CPU tourne dans son propre dossier (`/opt/miners/work/cpu`), à côté du
SRBMiner GPU, sans se mélanger avec lui. Chaque mineur est relancé seul s'il s'arrête :
un plantage du mineur CPU n'interrompt pas le GPU, et inversement. Les lignes du mineur
CPU sont préfixées par `[cpu]` dans les logs.

**Machines à plusieurs processeurs** : dans un conteneur, les mineurs ne peuvent pas
placer leur mémoire par processeur (« can't bind memory »). Sans `--randomx-no-numa`,
XMRig passe en mode lent, environ 10 fois moins de hashrate sur un bi-EPYC. D'où ces
options ajoutées d'office.

## Exemples de templates

**Pearl (GPU) + Monero (CPU, XMRig)** :

```
GPU_MINER=srbminer
GPU_ARGS=--algorithm pearlhash --pool prl.kryptex.network:7048 --wallet ADRESSE_PEARL --worker FARM
CPU_MINER=xmrig
CPU_ARGS=--coin monero -o xmr.kryptex.network:7029 -u ADRESSE_MONERO/RENT -t 184 -k
```

**Pearl (GPU) + DragonX (CPU, SRBMiner)** :

```
GPU_MINER=srbminer
GPU_ARGS=--algorithm pearlhash --pool prl.kryptex.network:7048 --wallet ADRESSE_PEARL --worker FARM
CPU_MINER=srbminer
CPU_ARGS=--algorithm randomdrgx --pool POOL:PORT --wallet ADRESSE_DRAGONX.RENT --cpu-threads 180
```

Le nom du worker suit le format attendu par la pool : `--worker` (SRBMiner), `wallet.worker`
ou `wallet/worker` (Kryptex pour Monero). Sans worker, ça mine quand même.

Quelques algorithmes CPU de SRBMiner (liste complète sur sa page GitHub) : `randomdrgx`
(DragonX), `verushash` (Verus), `randomepic` (Epic Cash), `randomx` (Monero).

## Template vast.ai

- **Image Path:Tag** : `clusmi/rentingminers`, version `latest`
- **Launch mode** : **Docker ENTRYPOINT**
- **Champ des arguments** : **vide**
- **Environment Variables** : `GPU_ARGS`, et `CPU_MINER` + `CPU_ARGS` pour le CPU
- **Après une reconstruction de l'image** : une location ne prend la nouvelle version que
  si son conteneur est recréé (`recycle`, ou le menu 2 de Vast-Switch-Log) ; un simple
  `reboot` garde l'ancienne.

## À savoir

- **Frais** : chaque mineur prélève des frais de développeur fixés par son auteur
  (XMRig : 1 % ; SRBMiner : selon l'algorithme, 2 % pour pearlhash, 0,85 % pour
  randomdrgx). Compare les mineurs sur le hashrate vu par la pool.
- **Mineur CPU en conteneur** : les messages sur les « huge pages » et les registres
  « MSR » sont normaux. Ces optimisations demandent des droits que seul l'hôte a ; sans
  elles, RandomX perd environ 10 à 20 %.
- **Impact sur le GPU** : le mineur GPU a besoin d'un peu de CPU. Compare le hashrate GPU
  vu par la pool avec et sans minage CPU, et réduis les threads CPU si besoin (`-t` pour
  XMRig, `--cpu-threads` pour SRBMiner).
- **Vérifier un template** : ajoute `DRY_RUN=1`, le log montre les deux commandes exactes.

## Dépannage

- **`GPU_ARGS est obligatoire`** : la variable manque ou est vide.
- **`variables d'une ancienne version detectees`** : le template utilise les anciens noms
  (`MINER`, `POOL`, `WALLET`, `CPU_POOL`…). Mets-le à jour avec `GPU_ARGS` / `CPU_ARGS`.
- **`guillemet non ferme`** : un guillemet ouvert dans `GPU_ARGS` ou `CPU_ARGS` sans son
  guillemet fermant.
- **Hashrate CPU très bas** : cherche `slow mode` (XMRig) dans les logs, et vérifie que la
  ligne `[rentingminers] CPU` contient `--randomx-no-numa` (XMRig) ou
  `--disable-numa-binding` (SRBMiner).
- **Le mineur refuse une option** : son message est dans les logs ; l'image ne vérifie pas
  les arguments, elle les transmet.
- **`No such container` sur vast.ai** : l'image n'a pas pu être téléchargée ; vérifie que
  le dépôt Docker Hub est public.
