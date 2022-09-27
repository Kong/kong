#!/usr/bin/env sh

apk add --no-cache vault libcap > /setup.log 2>&1 || (cat /setup.log; exit 1)
setcap cap_ipc_lock= /usr/sbin/vault > /setup.log 2>&1 || (cat /setup.log; exit 1)
rm /setup.log

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
vault secrets enable -path=$VAULT_MOUNT -description="Test Kong vault-auth plugin" kv || exit 1
vault secrets enable -path=$VAULT_MOUNT_2 -description="Test Kong vault-auth plugin" kv || exit 1
