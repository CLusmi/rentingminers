# Image de minage pour GPU loues (vast.ai, SaladCloud, Clore.ai...) :
#   - GPU NVIDIA : SRBMiner-MULTI, ForgeMiner, OneZeroMiner, PeakMiner ou lpminer
#                  (GPU_MINER, GPU_ARGS)
#   - CPU        : XMRig ou SRBMiner-MULTI (CPU_MINER, CPU_ARGS)
# Un cote ne demarre que si son mineur ET ses arguments sont renseignes.
# Sur SaladCloud, un chien de garde facultatif (SALAD_WATCHDOG, SRBMiner
# seulement) demande une autre machine quand la carte est trop lente (voir
# entrypoint.sh).
#
# Les versions, URL et empreintes sont fournies par le workflow GitHub
# (scripts/resolve-versions.sh). Chaque fichier est telecharge depuis la page
# GitHub officielle du mineur (lpminer : eu.lproute.com, version et empreinte
# figees) et verifie avant installation.

# ---------------------------------------------------------------------------
# Etape 1 : telechargement et verification des mineurs
# ---------------------------------------------------------------------------
FROM ubuntu:24.04 AS fetch

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

ARG SRB_VERSION
ARG SRB_URL
ARG SRB_SHA256
ARG XMRIG_VERSION
ARG XMRIG_URL
ARG XMRIG_SHA256
ARG FORGE_VERSION
ARG FORGE_URL
ARG FORGE_SHA256
ARG OZM_VERSION
ARG OZM_URL
ARG OZM_SHA256
ARG PEAK_VERSION
ARG PEAK_URL
ARG PEAK_SHA256
ARG LPMINER_VERSION
ARG LPMINER_URL
ARG LPMINER_SHA256

# lpminer : son dossier lib/ (libstdc++ fourni par l'auteur) est garde a cote du binaire.
COPY scripts/fetch-miner.sh /usr/local/bin/fetch-miner
RUN chmod +x /usr/local/bin/fetch-miner \
    && mkdir -p /opt/miners \
    && fetch-miner srbminer     "$SRB_VERSION"     "$SRB_URL"     "$SRB_SHA256"     SRBMiner-MULTI \
    && fetch-miner xmrig        "$XMRIG_VERSION"   "$XMRIG_URL"   "$XMRIG_SHA256"   xmrig \
    && fetch-miner forgeminer   "$FORGE_VERSION"   "$FORGE_URL"   "$FORGE_SHA256"   forge \
    && fetch-miner onezerominer "$OZM_VERSION"     "$OZM_URL"     "$OZM_SHA256"     onezerominer \
    && fetch-miner peakminer    "$PEAK_VERSION"    "$PEAK_URL"    "$PEAK_SHA256"    peakminer \
    && fetch-miner lpminer      "$LPMINER_VERSION" "$LPMINER_URL" "$LPMINER_SHA256" lpminer lib

# ---------------------------------------------------------------------------
# Etape 2 : image finale, sans outils de telechargement
# ---------------------------------------------------------------------------
FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive
# ca-certificates : connexions TLS aux pools.
# ocl-icd-libopencl1 : chargeur OpenCL, que SRBMiner ouvre au demarrage.
# wget : demande par SRBMiner (il s'arrete sans lui si sa connexion directe a
# ses serveurs de frais echoue).
# Le pilote NVIDIA (libcuda, NVML) n'est PAS dans l'image : l'hote l'injecte
# au lancement (vast.ai, Clore, docker --gpus all). XMRig est autonome.
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates ocl-icd-libopencl1 wget \
    && rm -rf /var/lib/apt/lists/*

COPY --from=fetch /opt/miners /opt/miners
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 0755 /usr/local/bin/entrypoint.sh \
    && mkdir -p /opt/miners/work

ENV NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=compute,utility \
    RESTART_DELAY=10

LABEL org.opencontainers.image.title="rentingminers" \
      org.opencontainers.image.description="GPU NVIDIA : SRBMiner-MULTI, ForgeMiner, OneZeroMiner, PeakMiner ou lpminer (GPU_MINER, GPU_ARGS) ; CPU : XMRig ou SRBMiner-MULTI (CPU_MINER, CPU_ARGS)"

WORKDIR /opt/miners/work
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
