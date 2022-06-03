#!/usr/bin/env bash
# set -e

# this script is temporary, just wanted to not modify setup_env_github.sh for now
YQ_VERSION=v4.5.0
INSTALL_ROOT=${INSTALL_ROOT:=/install-cache}
INSTALL_ROOT_BIN=${INSTALL_ROOT_BIN:=/$INSTALL_ROOT/bin}
mkdir -p "${INSTALL_ROOT}"
mkdir -p "${INSTALL_ROOT_BIN}"
PONGO_DOWNLOAD=${INSTALL_ROOT}/pongo

wget https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64 \
    -O ${INSTALL_ROOT_BIN}/yq
chmod +x ${INSTALL_ROOT_BIN}/yq

if [[ ! -d $PONGO_DOWNLOAD ]]; then
    git clone https://github.com/Kong/kong-pongo.git \
        ${PONGO_DOWNLOAD}
    ln -s ${PONGO_DOWNLOAD}/pongo.sh ${INSTALL_ROOT_BIN}/pongo
fi
