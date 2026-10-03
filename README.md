# rentingminers

Image Docker pour miner sur des machines louées (vast.ai, SaladCloud, Clore.ai…) :

- **GPU NVIDIA** : SRBMiner-MULTI ;
- **CPU** : XMRig ou SRBMiner-MULTI.

GPU seul, CPU seul ou les deux : **rien ne démarre sans choix explicite**. Les arguments
des mineurs sont donnés **tels quels**, dans leur syntaxe d'origine. Sur SaladCloud, un
chien de garde facultatif peut demander une autre machine quand la carte est trop lente
(voir plus bas).
Image publiée : `clusmi/rentingminers:latest` (publique).

## Comment l'image est construite

Le workflow GitHub (`.github/workflows/build.yml`) :

1. cherche la **dernière version stable** de chaque mineur sur sa page GitHub officielle
   (`doktor83/SRBMiner-Multi`, `xmrig/xmrig`) ;
2. télécharge l'archive Linux et **vérifie son empreinte SHA-256** (celle que GitHub a
   enregistrée quand l'auteur a publié le fichier) : si elle ne correspond pas, la
   construction échoue ;
3. construit l'image et l'envoie sur Docker Hub sous **deux étiquettes** :
   `clusmi/rentingminers:latest` et une étiquette datée, par exemple
   `clusmi/rentingminers:2026-10-03-2145`.

Les versions incluses et l'étiquette datée s'affichent dans le résumé du workflow ; les
versions aussi au démarrage du conteneur. Pour récupérer de nouvelles versions des mineurs,
relance simplement le workflow.

- **vast.ai** : garde `latest` ; après un build, `recycle` (menu 2 de Vast-Switch-Log)
  re-télécharge l'image.
- **SaladCloud** : Salad copie l'image dans son registre à la création du groupe et ne la
  re-télécharge pas tant que l'étiquette ne change pas, même si `latest` a bougé. Mets donc
  l'**étiquette datée** dans le groupe (Edit → Image Source) ; pour passer à un nouveau
  build, remplace-la par la nouvelle : Salad télécharge la nouvelle image et redéploie
  les replicas.

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
| `GPU_MINER` | `srbminer` (seule valeur) | XMRig ne mine que sur CPU |
| `GPU_ARGS` | | arguments SRBMiner, tels quels |
| `CPU_MINER` | `xmrig` ou `srbminer` | |
| `CPU_ARGS` | | arguments du mineur CPU, tels quels |
| `RESTART_DELAY` | `10` | secondes avant relance d'un mineur qui s'arrête |
| `DRY_RUN` | | `1` : affiche les commandes finales sans miner |
| `SALAD_WATCHDOG`, `SALAD_MIN_HASHRATE`, … | | chien de garde SaladCloud, voir [plus bas](#saladcloud--chien-de-garde) |

Aucun mineur n'est prérempli. Un côté démarre seulement si **son mineur et ses arguments**
sont renseignés tous les deux :

| `GPU_MINER` + `GPU_ARGS` | `CPU_MINER` + `CPU_ARGS` | Résultat |
|---|---|---|
| renseignés | vides | GPU seul |
| vides | renseignés | CPU seul |
| renseignés | renseignés | GPU + CPU |
| vides | vides | erreur « rien a miner » |
| l'un sans l'autre | | erreur, rien ne démarre |

Dans le template vast.ai, le plus simple est la section **Environment Variables** : une
case pour le nom, une pour la valeur, **sans guillemets**. Dans le champ « Docker
Options », la syntaxe est `-e GPU_ARGS="--algorithm pearlhash --pool ... --wallet ..."`,
avec le `-e` et des guillemets autour de la valeur. Si vast.ai garde ces guillemets dans
la valeur, l'image les retire. Des guillemets à l'intérieur de la valeur marchent aussi
(`--password "mot de passe"`).

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

**Pearl seul (GPU)** :

```
GPU_MINER=srbminer
GPU_ARGS=--algorithm pearlhash --pool prl.kryptex.network:7048 --wallet ADRESSE_PEARL --worker FARM
```

**DragonX seul (CPU, SRBMiner)** :

```
CPU_MINER=srbminer
CPU_ARGS=--algorithm randomdrgx --pool POOL:PORT --wallet ADRESSE_DRAGONX.RENT --cpu-threads 180
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
- **Environment Variables** : `GPU_MINER` + `GPU_ARGS` pour le GPU, `CPU_MINER` + `CPU_ARGS`
  pour le CPU (l'un, l'autre ou les deux)
- **Après une reconstruction de l'image** : une location ne prend la nouvelle version que
  si son conteneur est recréé (`recycle`, ou le menu 2 de Vast-Switch-Log) ; un simple
  `reboot` garde l'ancienne.

## SaladCloud : chien de garde

Sur Salad, chaque replica tourne sur le PC d'un particulier, avec une carte parfois bridée
ou utilisée en même temps. Le chien de garde lit le hashrate dans le log SRBMiner et, si la
carte est trop lente, demande à Salad de déplacer le conteneur sur une autre machine (via
le service de métadonnées de Salad, `169.254.169.254/v1/reallocate`). Il n'est actif que
sur Salad (variable `SALAD_MACHINE_ID` injectée par Salad) **et** si `SALAD_WATCHDOG` est
renseigné : sur vast.ai, rien ne change.

| Variable | Exemple | Rôle |
|---|---|---|
| `SALAD_WATCHDOG` | `observe` ou `reallocate` | `observe` : surveille et écrit ses verdicts dans le log sans agir ; `reallocate` : demande la réallocation |
| `SALAD_MIN_HASHRATE` | `5090=300T,4090=250T,3090=100T` | seuil par modèle de carte (K, M, G, T = kilo/méga/giga/téra H/s) ; la première clé contenue dans le nom du modèle s'applique (`3090` couvre aussi la 3090 Ti) ; un modèle absent n'est pas surveillé |
| `SALAD_GRACE` | `300` | secondes de répit après chaque (re)démarrage du mineur GPU |
| `SALAD_BAD_READINGS` | `3` | lectures consécutives sous le seuil avant verdict |
| `SALAD_MAX_RESTARTS` | `5` | verdict si le mineur GPU redémarre au moins N fois en 10 min (inactif si absent) |

Déroulement : après le répit, une lecture toutes les 30 s (SRBMiner publie ses statistiques
toutes les 30 à 90 s, seules les nouvelles comptent) ; `SALAD_BAD_READINGS` lectures
consécutives sous le seuil donnent un verdict, une lecture au-dessus remet le compteur à
zéro, une lecture à 0 n'est pas comptée (pool injoignable). Après un verdict, 10 min de
pause. Les lignes du chien de garde commencent par `[salad]`.

Conseil : première mise en service en `observe`, lecture des logs pendant une heure,
puis `reallocate`. Les seuils se placent vers 85 % du hashrate d'une carte saine **sans
overclock** (sur Salad, impossible d'overclocker), par exemple pour pearlhash : RTX 5090
≈ 340 TH/s → `300T`, RTX 4090 ≈ 290 TH/s → `250T`, RTX 3090 ≈ 130 TH/s → `100T`.

Exemple (Docker Run dans Salad) :

```
docker run --gpus all -e GPU_MINER=srbminer -e GPU_ARGS="--algorithm pearlhash --pool POOL:PORT --wallet ADRESSE_PEARL --worker SALAD" -e SALAD_WATCHDOG=observe -e SALAD_MIN_HASHRATE=5090=300T,4090=250T,3090=100T -e SALAD_MAX_RESTARTS=5 clusmi/rentingminers:AAAA-MM-JJ-HHMM
```

`AAAA-MM-JJ-HHMM` est l'étiquette datée du build (résumé du workflow GitHub). Modifier ces
variables ou l'étiquette dans Salad (Edit) crée une nouvelle version du groupe et redéploie
tous les replicas.

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

- **`rien a miner`** : aucun côté n'est complet. Il faut `GPU_MINER` + `GPU_ARGS` et/ou
  `CPU_MINER` + `CPU_ARGS`.
- **`CPU_ARGS est renseigne mais CPU_MINER manque`** (et variantes) : un côté a l'une de
  ses deux variables sans l'autre ; complète-le ou vide les deux.
- **`variables d'une ancienne version ignorees`** : le conteneur reçoit aussi les anciens
  noms (`MINER`, `POOL`, `WALLET`, `CPU_POOL`…). Vast.ai réinjecte parfois les variables du
  template d'origine d'une location ; elles sont ignorées, seules `GPU_MINER`, `GPU_ARGS`,
  `CPU_MINER` et `CPU_ARGS` comptent. La ligne `Variables recues` dit lesquelles sont
  arrivées.
- **`guillemet non ferme`** : un guillemet ouvert dans `GPU_ARGS` ou `CPU_ARGS` sans son
  guillemet fermant.
- **Hashrate CPU très bas** : cherche `slow mode` (XMRig) dans les logs, et vérifie que la
  ligne `[rentingminers] CPU` contient `--randomx-no-numa` (XMRig) ou
  `--disable-numa-binding` (SRBMiner).
- **Le mineur refuse une option** : son message est dans les logs ; l'image ne vérifie pas
  les arguments, elle les transmet.
- **`No such container` sur vast.ai** : l'image n'a pas pu être téléchargée ; vérifie que
  le dépôt Docker Hub est public.
- **`SALAD_WATCHDOG est renseigne mais ce conteneur ne tourne pas sur Salad`** : la variable
  est dans un template vast.ai ; sans effet, à retirer.
- **`Pas de seuil pour « ... »`** : la carte attribuée par Salad n'est pas dans
  `SALAD_MIN_HASHRATE` ; elle mine normalement, sans surveillance du hashrate.
- **`Demande de reallocation refusee ou sans reponse`** : le service de métadonnées de Salad
  n'a pas accepté la demande ; le chien de garde réessaie au prochain verdict. Si ça
  persiste, réalloue l'instance à la main (menu ⋮ → Reallocate).
