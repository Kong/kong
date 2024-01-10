#!/usr/bin/env sh

# fixup for pongo doesn't bring other serivces in the same docker-compose file

if [ -z $(cat /etc/hosts | grep vault) ]; then
    echo "Vault container not found, assuming this is pongo lint"
    exit 0
fi

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
curl -s https://releases.hashicorp.com/vault/"${HC_VAULT_VERSION}"/vault_"${HC_VAULT_VERSION}"_linux_${arch}.zip -o /tmp/vault.zip
unzip /tmp/vault.zip
mv vault /usr/bin

export VAULT_ADDR='http://vault:8200'
export VAULT_TOKEN='vault-plaintext-root-token'

# check status
for i in $(seq 1 60); do
    vault status && break
    sleep 1
done

# create mount points KV version 1
vault secrets enable -path="kong-auth" -description="Test Kong vault-auth plugin" kv || true
vault secrets enable -path="kong-auth-2" -description="Test Kong vault-auth plugin" kv || true
vault secrets enable -path="kong-auth-v2" -description="Test Kong vault-auth plugin kv-v2" kv-v2 || true
