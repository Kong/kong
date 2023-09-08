#!/usr/bin/env sh

HC_VAULT_VERSION=1.7.1
arch=$(arch)
if [[ $arch == "x86_64" || $arch == "amd64" ]]; then
    arch=amd64
elif [[ $arch == "aarch64" || $arch == "arm64" ]]; then
    arch=arm64
else
    echo "Unsupport architecture for vault: $arch"
    exit 1
fi
curl -Os https://releases.hashicorp.com/vault/"${HC_VAULT_VERSION}"/vault_"${HC_VAULT_VERSION}"_linux_${arch}.zip
unzip vault_"${HC_VAULT_VERSION}"_linux_${arch}.zip
mv vault /usr/bin

# start vault in background, use 'nohup' to keep it around after script exit
nohup vault server -dev > /kong/vault.log 2>&1 &

# grab tokens
sleep 0.5
export VAULT_ADDR=$(grep "VAULT_ADDR" < /kong/vault.log | sed 's/$ export VAULT_ADDR=//' | sed 's/ //g' | sed 's/'\''//g')
export VAULT_TOKEN=$(grep "Root Token:" < /kong/vault.log | sed 's/Root Token: //')

# check status
vault status > /dev/null 2>&1
if [ $? -eq 0 ]; then
  echo "Vault dev server started, logs in; /kong/vault.log"
else
  echo "Failed starting Vault dev server"
  exit 1
fi

# create mount points KV version 1
export VAULT_MOUNT="kong-auth"
export VAULT_MOUNT_2="kong-auth-2"
export VAULT_MOUNT_V2="kong-auth-v2"
vault secrets enable -path=$VAULT_MOUNT -description="Test Kong vault-auth plugin" kv || exit 1
vault secrets enable -path=$VAULT_MOUNT_2 -description="Test Kong vault-auth plugin" kv || exit 1
vault secrets enable -path=$VAULT_MOUNT_V2 -description="Test Kong vault-auth plugin kv-v2" kv-v2 || exit 1
