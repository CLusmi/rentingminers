# rentingminers

Image Docker pour miner sur des machines louées (vast.ai, SaladCloud, Clore.ai…) :

- **GPU NVIDIA** : SRBMiner-MULTI, ForgeMiner, OneZeroMiner, PeakMiner, lpminer ou
  ARIAEnergy PRL (Pearl, Quantus… selon le mineur) ;
- **CPU** : XMRig ou SRBMiner-MULTI.

GPU seul, CPU seul ou les deux : **rien ne démarre sans choix explicite**. Les arguments
des mineurs sont donnés **tels quels**, dans leur syntaxe d'origine. Sur SaladCloud, un
chien de garde facultatif (SRBMiner seulement) peut demander une autre machine quand la
carte est trop lente (voir plus bas).
Image publiée : `clusmi/rentingminers:latest` (publique).

## Comment l'image est construite

Le workflow GitHub (`.github/workflows/build.yml`) :

1. cherche la **dernière version stable** de chaque mineur sur sa page GitHub officielle
   (`doktor83/SRBMiner-Multi`, `xmrig/xmrig`, `0xHashRaptor/ForgeMiner`,
   `OneZeroMiner/onezerominer`, `peakminer/peakminer`) ; lpminer (Quantus, LuckyPool,
   `eu.lproute.com`) et ARIAEnergy PRL (`dl.ariabrain.com`) ne sont pas sur GitHub : leur
   version, leur URL et leur empreinte sont **figées** dans `scripts/resolve-versions.sh`
   (nouvelle version = changer la ligne) ;
2. télécharge l'archive Linux (ou le binaire nu pour PeakMiner) et **vérifie son
   empreinte SHA-256** (celle que GitHub a enregistrée quand l'auteur a publié le fichier,
   ou celle figée), le `SHA256SUMS` fourni dans l'archive s'il y en a un, et que c'est bien
   un exécutable Linux : sinon, la construction échoue ;
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
| `GPU_MINER` | `srbminer`, `forgeminer`, `onezerominer`, `peakminer`, `lpminer` ou `ariaenergy` | XMRig ne mine que sur CPU |
| `GPU_ARGS` | | arguments du mineur GPU, tels quels, dans sa propre syntaxe (voir [Mineurs GPU](#mineurs-gpu)) |
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
| ForgeMiner, PeakMiner | `--no-color` | logs lisibles sans terminal |
| OneZeroMiner | rien | |
| lpminer | variable `LP_DISABLE_HOTKEYS=1` (et ses bibliothèques `lib/`) | pas de clavier dans un conteneur |
| ARIAEnergy PRL | lancé par `run-all.sh` : un processus par carte visible, `--worker NOM-gpuN` s'il y a plusieurs cartes | le mineur ne mine qu'une carte par processus |
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

## Mineurs GPU

Un seul mineur GPU à la fois (`GPU_MINER`), avec ses arguments dans **sa** syntaxe. Les
pools sont des exemples : LuckyPool Quantus `pl.lproute.com:5660` (ou `eu.lproute.com`,
`us-east.lproute.com`… même port), Kryptex Quantus `qtc.kryptex.network:7049`, Kryptex
Pearl `prl.kryptex.network:7048`, HeroMiners Pearl `de.pearl.herominers.com:1200`.

| `GPU_MINER` | Mineur | Pièces (frais) | `GPU_ARGS` |
|---|---|---|---|
| `srbminer` | SRBMiner-MULTI | Pearl `pearlhash` (2 %), Quantus `quantus` | `--algorithm pearlhash --pool POOL:PORT --wallet ADRESSE --worker NOM --pearl-k1` / `--algorithm quantus --pool POOL:PORT --wallet ADRESSE --worker NOM` |
| `forgeminer` | ForgeMiner (`forge`) | Pearl `pearlhash` (2 %), Quantus `quantus` (2 %) | `--algorithm quantus --pool POOL:PORT --wallet ADRESSE --worker NOM` |
| `onezerominer` | OneZeroMiner | `pearlhash` (1 %), `quantus` (2 %) | `-a quantus -o POOL:PORT -w ADRESSE --worker NOM` |
| `peakminer` | PeakMiner | `pearl` (2 %), `quantus` (2 %) | `--coin quantus -o POOL:PORT -u ADRESSE -w NOM` (ou `-u ADRESSE.NOM`) |
| `lpminer` | lpminerquantus (LuckyPool) | Quantus seulement, sur LuckyPool ; frais non documentés | `--algo quantus --pool POOL:PORT --wallet ADRESSE --worker NOM` |
| `ariaenergy` | ARIAEnergy PRL | Pearl seulement (2 % : 120 s toutes les 100 min) | `--pool POOL:PORT --wallet ADRESSE --worker NOM` |

Pour Pearl avec ForgeMiner / OneZeroMiner : `pearlhash` à la place de `quantus` ; avec
PeakMiner : `--coin pearl`. Attention, ForgeMiner et OneZeroMiner ont aussi un `qhash` :
c'est **QubitCoin**, qui porte le même ticker QTC, pas Quantus.

Pilotes NVIDIA demandés par les mineurs (sur Salad, la machine attribuée a le pilote
qu'elle a ; un mineur qui le refuse s'arrête et se relance en boucle, lis ses lignes dans
les logs) : lpminer **580 ou plus** (CUDA 13.2) ; ForgeMiner 580+ pour les RTX 50 ;
OneZeroMiner 528+ ; PeakMiner et SRBMiner embarquent leur runtime ; ARIAEnergy PRL
embarque deux builds (CUDA 13 à partir du pilote 580, CUDA 12 pour 525 à 579) et choisit
seul, RTX 3000 ou plus récente.

**ARIAEnergy PRL mine une carte par processus.** L'image s'en charge : avec une seule carte
visible (Salad), le mineur est lancé tel quel ; avec plusieurs (rig vast.ai), un processus
par carte, le worker suffixé `-gpu0`, `-gpu1`… (la pool montre chaque carte), chaque ligne
de log préfixée `[gpuN]`. Si un processus s'arrête, les autres sont arrêtés et l'ensemble
est relancé. Au démarrage, le mineur fait un auto-test (une preuve complète vérifiée) puis
un auto-réglage de ses kernels : compte une à deux minutes avant le premier hashrate.

Le chien de garde Salad lit le log de SRBMiner : avec un autre mineur GPU, il est ignoré
(ligne `pris en charge seulement avec GPU_MINER=srbminer` dans les logs) et le mineur
tourne sans surveillance.

## Exemples de templates

**Quantus (GPU, SRBMiner)** :

```
GPU_MINER=srbminer
GPU_ARGS=--algorithm quantus --pool pl.lproute.com:5660 --wallet ADRESSE_QUANTUS --worker FARM
```

**Quantus (GPU, ForgeMiner)** :

```
GPU_MINER=forgeminer
GPU_ARGS=--algorithm quantus --pool pl.lproute.com:5660 --wallet ADRESSE_QUANTUS --worker FARM
```

**Quantus (GPU, OneZeroMiner)** :

```
GPU_MINER=onezerominer
GPU_ARGS=-a quantus -o pl.lproute.com:5660 -w ADRESSE_QUANTUS --worker FARM
```

**Quantus (GPU, PeakMiner)** :

```
GPU_MINER=peakminer
GPU_ARGS=--coin quantus -o pl.lproute.com:5660 -u ADRESSE_QUANTUS -w FARM
```

**Quantus sur LuckyPool (GPU, lpminer)** :

```
GPU_MINER=lpminer
GPU_ARGS=--algo quantus --pool pl.lproute.com:5660 --wallet ADRESSE_QUANTUS --worker FARM
```

**Pearl (GPU, ARIAEnergy PRL)** :

```
GPU_MINER=ariaenergy
GPU_ARGS=--pool de.pearl.herominers.com:1200 --wallet ADRESSE_PEARL --worker FARM
```

**Pearl (GPU) + Monero (CPU, XMRig)** :

```
GPU_MINER=srbminer
GPU_ARGS=--algorithm pearlhash --pool POOL:PORT --wallet ADRESSE_PEARL --worker FARM --pearl-k1
CPU_MINER=xmrig
CPU_ARGS=--coin monero -o xmr.kryptex.network:7029 -u ADRESSE_MONERO/RENT -t 184 -k
```

**Pearl seul (GPU)** :

```
GPU_MINER=srbminer
GPU_ARGS=--algorithm pearlhash --pool POOL:PORT --wallet ADRESSE_PEARL --worker FARM --pearl-k1
```

**DragonX seul (CPU, SRBMiner)** :

```
CPU_MINER=srbminer
CPU_ARGS=--algorithm randomdrgx --pool POOL:PORT --wallet ADRESSE_DRAGONX.RENT --cpu-threads 180
```

**Pearl (GPU) + DragonX (CPU, SRBMiner)** :

```
GPU_MINER=srbminer
GPU_ARGS=--algorithm pearlhash --pool POOL:PORT --wallet ADRESSE_PEARL --worker FARM --pearl-k1
CPU_MINER=srbminer
CPU_ARGS=--algorithm randomdrgx --pool POOL:PORT --wallet ADRESSE_DRAGONX.RENT --cpu-threads 180
```

`--pearl-k1` : nouveau code pearlhash de SRBMiner, apparu en **3.7.2** (NVIDIA Ampere, Ada
et Blackwell). Une image construite avec une version plus ancienne refuse l'option et
SRBMiner ne démarre pas : mets d'abord l'image à jour, puis l'option.

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
| `SALAD_ZERO_READINGS` | `2` | verdict après N lectures consécutives à 0 H/s (2 par défaut ; `0` = règle désactivée) |
| `SALAD_STALE_MINUTES` | `2` | verdict après N minutes sans nouvelle statistique du mineur GPU (2 par défaut ; `0` = désactivée). Si SRBMiner publie ses statistiques moins souvent, la limite devient deux fois cet intervalle, pour ne pas juger entre deux lignes |

Déroulement : après le répit, une lecture toutes les 30 s (SRBMiner publie ses statistiques
toutes les 30 à 90 s, seules les nouvelles comptent) ; `SALAD_BAD_READINGS` lectures
consécutives sous le seuil donnent un verdict, une lecture au-dessus remet le compteur à
zéro. Une lecture à 0 ne compte pas pour le seuil mais pour `SALAD_ZERO_READINGS` : deux
lectures à 0 de suite et la machine est jugée en panne. Plus aucune ligne de statistiques
pendant `SALAD_STALE_MINUTES` (mineur figé) : verdict aussi. Après un verdict, 10 min de
pause. Les lignes du chien de garde commencent par `[salad]`.

Conseil : première mise en service en `observe`, lecture des logs pendant une heure,
puis `reallocate`. Les seuils se placent vers 85 % du hashrate d'une carte saine **sans
overclock** (sur Salad, impossible d'overclocker) : un seuil au-dessus de ce que font tes
cartes fait réallouer **toutes** les machines, sans fin. Lis le hashrate réel dans le menu 2
de Salad-Switch-Log avant de fixer les seuils, et refais-le après un changement de version
de SRBMiner ou d'option (`--pearl-k1`).

Exemple (Docker Run dans Salad) :

```
docker run --gpus all -e GPU_MINER=srbminer -e GPU_ARGS="--algorithm pearlhash --pool POOL:PORT --wallet ADRESSE_PEARL --worker SALAD --pearl-k1" -e SALAD_WATCHDOG=observe -e SALAD_MIN_HASHRATE=5090=385T,4090=300T,3090=125T -e SALAD_GRACE=90 -e SALAD_BAD_READINGS=2 -e SALAD_MAX_RESTARTS=5 -e SALAD_ZERO_READINGS=2 -e SALAD_STALE_MINUTES=2 clusmi/rentingminers:AAAA-MM-JJ-HHMM
```

`AAAA-MM-JJ-HHMM` est l'étiquette datée du build (résumé du workflow GitHub). Modifier ces
variables ou l'étiquette dans Salad (Edit) crée une nouvelle version du groupe et redéploie
tous les replicas.

## À savoir

- **Frais** : chaque mineur prélève des frais de développeur fixés par son auteur
  (XMRig : 1 % ; SRBMiner : selon l'algorithme, 2 % pour pearlhash, 0,85 % pour
  randomdrgx ; ForgeMiner 2 % ; OneZeroMiner 1 % pearlhash / 2 % quantus ; PeakMiner 2 % ;
  ARIAEnergy PRL 2 % ; lpminer : non documentés). Compare les mineurs sur le hashrate vu
  par la pool.
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
- **Le mineur GPU s'arrête aussitôt et se relance en boucle** : ses propres lignes, juste
  avant `Le mineur GPU s'est arrete`, disent pourquoi (option inconnue comme `--pearl-k1`
  sur une version trop ancienne, pool injoignable, pilote NVIDIA trop ancien pour lpminer
  ou ForgeMiner…).
- **`GPU_MINER=... inconnu`** : valeurs possibles `srbminer`, `forgeminer`, `onezerominer`,
  `peakminer`, `lpminer`, `ariaenergy`.
- **`pris en charge seulement avec GPU_MINER=srbminer`** : le chien de garde Salad est
  renseigné avec un autre mineur GPU ; il est ignoré, le mineur tourne sans surveillance.
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
