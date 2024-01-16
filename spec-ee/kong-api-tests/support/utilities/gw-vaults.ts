import axios from 'axios';
import { expect } from '../assert/chai-expect';
import { Environment, getBasePath } from '../config/environment';
import { postNegative } from './negative-axios';
import { logResponse } from './logging';

const getUrl = (endpoint = '') => {
  const basePath = getBasePath({
    environment: Environment.gateway.admin,
  });

  return `${basePath}/${endpoint}`;
};

const getHost = () => {
  const hostName = getBasePath({
    environment: Environment.gateway.hostName,
  });

  return hostName;
};

const hcvToken = 'vault-plaintext-root-token';

/**
 * Get target hcv mount kv engine version
 * @param {string} targetMount - name of the target hcv mount
 * @returns {string} - hashicorp vault kv version of target mount
 */
export const getHcvKvVersion = async (targetMount = 'secret') => {
  const resp = await axios({
    url: `http://${getHost()}:8200/v1/sys/mounts/${targetMount}`,
    headers: {
      'X-Vault-Token': hcvToken,
    },
  });

  expect(resp.data.options.version).to.be.a('string');
  const kvVersion = resp.data.options.version;

  return kvVersion;
};

/**
 * Enable Approle auth method in HCV
 * @param {string} path - path of the enabled approle auth method, default is 'approle'
 */
export const enableHcvApproleAuth = async (path = "approle") => {
  const resp = await axios({
    method: 'POST',
    url: `http://${getHost()}:8200/v1/sys/auth/${path}`,
    headers: {
      'X-Vault-Token': hcvToken,
    },
    data: {
      type: 'approle',
    },
  });

  logResponse(resp);

  expect(resp.status, 'Status should be 204').to.equal(204);
  return resp.data;
};

/**
 * Create an HCV policy for reading all secrets
 * @param {string} policy_name - name of the policy
 */
export const createHcvSecretReadPolicy = async (policy_name = "hcv-secret-read") => {
  const resp = await axios({
    method: 'POST',
    url: `http://${getHost()}:8200/v1/sys/policies/acl/${policy_name}`,
    headers: {
      'X-Vault-Token': hcvToken,
    },
    data: {
      policy: `path "secret/*" {
        capabilities = ["read"]
      }`,
    },
  });

  logResponse(resp);

  expect(resp.status, 'Status should be 204').to.equal(204);
  return resp.data;
}

/**
 * Create a new Approle in HCV
 * @param {string} path - path of the enabled approle auth method, default is 'approle'
 * @param {string} role_name - name of the approle to create, default is 'test-role'
 */
export const createHcvAppRole = async (path = "approle", role_name = "test-role") => {

  const policy_name = "hcv-secret-read";
  await createHcvSecretReadPolicy(policy_name);

  const resp = await axios({
    method: 'POST',
    url: `http://${getHost()}:8200/v1/auth/${path}/role/${role_name}`,
    headers: {
      'X-Vault-Token': hcvToken,
    },
    data: {
      secret_id_ttl: 0,
      token_ttl: 0,
      token_max_ttl: 0,
      token_policies: [policy_name],
    },
  });

  logResponse(resp);

  expect(resp.status, 'Status should be 204').to.equal(204);
  return resp.data;
};

/**
 * Fetch Approle ID from HCV
 * @param {string} role_name - name of the approle to fetch, default is 'test-role'
 * @param {string} path - path of the enabled approle auth method, default is 'approle'
 * @returns {string} - approle id
 */
export const getHcvApproleID = async (path = "approle", role_name = "test-role") => {
  const resp = await axios({
    method: 'GET',
    url: `http://${getHost()}:8200/v1/auth/${path}/role/${role_name}/role-id`,
    headers: {
      'X-Vault-Token': hcvToken,
    },
  });

  logResponse(resp);

  expect(resp.status, 'Status should be 200').to.equal(200);
  return resp.data.data.role_id;
};

/**
 * Create a new Approle Secret ID in HCV
 * @param {string} path - path of the enabled approle auth method, default is 'approle'
 * @param {string} role_name - name of the approle to fetch, default is 'test-role'
 * @returns {string} - approle secret id
 */
export const createHcvApproleSecretID = async (path = "approle", role_name = "test-role") => {
  const resp = await axios({
    method: 'POST',
    url: `http://${getHost()}:8200/v1/auth/${path}/role/${role_name}/secret-id`,
    headers: {
      'X-Vault-Token': hcvToken,
    },
    data: {
      ttl: 0,
    },
  });

  logResponse(resp);

  expect(resp.status, 'Status should be 200').to.equal(200);
  return resp.data.data.secret_id;
}

/**
 * Create a new Approle Wrapped Secret ID in HCV
 * @param {string} path - path of the enabled approle auth method, default is 'approle'
 * @param {string} role_name - name of the approle to fetch, default is 'test-role'
 * @returns {string} - wrapped approle secret id
 */
export const createHcvApproleWrappedSecretId = async (path = "approle", role_name = "test-role") => {
  const resp = await axios({
    method: 'POST',
    url: `http://${getHost()}:8200/v1/auth/${path}/role/${role_name}/secret-id`,
    headers: {
      'X-Vault-Token': hcvToken,
      'X-Vault-Wrap-TTL': '60m',
    },
    data: {
      ttl: 0,
    },
  });

  logResponse(resp);

  expect(resp.status, 'Status should be 200').to.equal(200);
  return resp.data.wrap_info.token;
}

/**
 * Constracts hcv secret url
 * @param {string} targetMount - name of the target hcv mount
 * @param {string} pathName - path of the secret in HCV vault
 * @returns {string} - hashicorp secret api
 */
export const getHcvSecretUrl = async (
  targetMount = 'secret',
  pathName = targetMount
) => {
  const kvVersion = await getHcvKvVersion(targetMount);

  const hcvSecretUrl = `http://${getHost()}:8200/v1/${targetMount}${
    kvVersion === '2' ? '/data/' : '/'
  }${pathName}`;

  return hcvSecretUrl;
};

/**
 * Creates hcv backend vault in Kong
 * @param {string} targetMount - name of the target hcv mount
 * @param {string} targetHcvToken - hcv root token
 * @param {string} vaultPrefix - hcv vault prefix (not config prefix for variables), default is 'my-hcv'
 */
export const createHcvVaultInKong = async (
  targetMount = 'secret',
  targetHcvToken = hcvToken,
  vaultPrefix = 'my-hcv'
) => {
  const kvVersion = await getHcvKvVersion(targetMount);

  const resp = await axios({
    method: 'put',
    url: `${getUrl('vaults')}/${vaultPrefix}`,
    data: {
      name: 'hcv',
      config: {
        protocol: 'http',
        host: 'host.docker.internal',
        port: 8200,
        mount: targetMount,
        kv: kvVersion === '2' ? 'v2' : 'v1',
        token: targetHcvToken,
      },
    },
  });

  expect(resp.status, 'Status should be 200').to.equal(200);

  return resp.data;
};

/**
 * Creates hcv backend vault using Approle auth method in Kong
 * @param {string} targetMount - name of the target hcv mount
 * @param {string} vaultPrefix - hcv vault prefix (not config prefix for variables), default is 'my-hcv'
 * @param {string} targetApproleRoleID - ID of the Approle
 * @param {string} targetApproleSecretID - Secret ID of the Approle
 * @param {boolean} approleResponseWrapping - whether the secret id is a response wrapping token
 */
export const createHcvVaultWithApproleInKong = async (
  targetMount = 'secret',
  vaultPrefix = 'my-hcv',
  targetApproleRoleID: string,
  targetApproleSecretID: string,
  approleResponseWrapping = false,
) => {
  const kvVersion = await getHcvKvVersion(targetMount);

  const resp = await axios({
    method: 'put',
    url: `${getUrl('vaults')}/${vaultPrefix}`,
    data: {
      name: 'hcv',
      config: {
        protocol: 'http',
        host: 'host.docker.internal',
        port: 8200,
        mount: targetMount,
        kv: kvVersion === '2' ? 'v2' : 'v1',
        auth_method: 'approle',
        approle_role_id: targetApproleRoleID,
        approle_secret_id: targetApproleSecretID,
        approle_response_wrapping: approleResponseWrapping,
      },
    },
  });

  logResponse(resp);

  expect(resp.status, 'Status should be 200').to.equal(200);

  return resp.data;
};

/**
 * Create HCV vault secrets
 * @param  {object} payload- request payload
 * @param {string} targetMount - name of the target hcv mount, default is 'secret'
 * @param {string} pathName - optional path of the secret in HCV vault
 */
export const createHcvVaultSecrets = async (
  payload: object,
  targetMount = 'secret',
  pathName = targetMount
) => {
  const hcvSecretUrl = await getHcvSecretUrl(targetMount, pathName);
  // kv v2 requires 'data' to be present in request payload
  if (hcvSecretUrl.includes('/data/')) {
    payload = { data: { ...payload } };
  }

  const resp = await axios({
    method: 'post',
    url: hcvSecretUrl,
    data: payload,
    headers: {
      'X-Vault-Token': hcvToken,
      'Content-Type': 'application/json',
    },
  });

  expect(resp.status, 'Status should be 200|204').to.equal(
    resp.data ? 200 : 204
  );

  return resp.data;
};

/**
 * Delete target HCV secret mount entierly
 * @param {string} mountName - target mount to delete
 */
export const deleteHcvSecretMount = async (mountName: string) => {
  const resp = await axios({
    method: 'delete',
    url: `http://${getHost()}:8200/v1/sys/mounts/${mountName}`,
    headers: {
      'X-Vault-Token': hcvToken,
    },
  });

  expect(resp.status, 'Status should be 204').to.equal(204);
};

/**
 * Delete target HCV secret path together with all secrets
 * @param {string} mountName - target mount to delete
 * @param {String} secretPathName - the path to delete
 */
export const deleteHcvSecret = async (
  mountName: string,
  secretPathName: string
) => {
  const resp = await axios({
    method: 'delete',
    url: `http://${getHost()}:8200/v1/${mountName}/metadata/${secretPathName}`,
    headers: {
      'X-Vault-Token': hcvToken,
    },
  });

  expect(resp.status, 'Status should be 204').to.equal(204);
};

/**
 * Get HCV vault secrets
 * @param {string} targetMount - name of the target hcv mount
 * @param {string} pathName - optional path of the secret in HCV vault
 */
export const getHcvVaultSecret = async (
  targetMount = 'secret',
  pathName = targetMount
) => {
  const hcvSecretUrl = await getHcvSecretUrl(targetMount, pathName);

  const resp = await axios({
    url: `${hcvSecretUrl}?version=1`,
    headers: {
      'X-Vault-Token': hcvToken,
    },
  });

  expect(resp.status, 'Status should be 200').to.equal(200);

  return resp.data.data;
};

/**
 * Create AWS backend vault entity
 * @param {string} vaultPrefix - the backend vault prefix, default is 'my-aws'
 */
export const createAwsVaultEntity = async (vaultPrefix = 'my-aws') => {
  const resp = await axios({
    method: 'put',
    url: `${getUrl('vaults')}/${vaultPrefix}`,
    data: {
      name: 'aws',
      config: {
        region: 'us-east-2',
      },
    },
  });

  expect(resp.status, 'Status should be 200').to.equal(200);
};

/**
 * Create Azure backend vault entity
 * @param {string} vaultPrefix - the backend vault prefix, default is 'my-azure'
 * @param {object} ttls - to specify ttl, neg_ttl and resurrect_ttl
 */
export const createAzureVaultEntity = async (vaultPrefix = 'my-azure', ttls?: object) => {
  const resp = await axios({
    method: 'put',
    url: `${getUrl('vaults')}/${vaultPrefix}`,
    data: {
      name: 'azure',
      config: {
        location: 'us-east',
        vault_uri: 'https://kong-vault.vault.azure.net/',
        ...ttls
      },
    },
  });

  expect(resp.status, 'Status should be 200').to.equal(200);
};

/**
 * Create ENV backend vault entity
 * @param {string} vaultPrefix - the backend vault prefix, default is 'my-env'
 * @param {object} configPayload - the vault config object payload e.g. {prefix: 'myvar_'}
 */
export const createEnvVaultEntity = async (
  vaultPrefix = 'my-env',
  configPayload: { prefix: string }
) => {
  const resp = await axios({
    method: 'put',
    url: `${getUrl('vaults')}/${vaultPrefix}`,
    data: {
      name: 'env',
      config: configPayload,
    },
  });

  expect(resp.status, 'Status should be 200').to.equal(200);
};

/**
 * Creates GCP backend vault
 * @param {string} projectId - gcp project_id, defaults to 'gcp-sdet-test'
 * @param {string} vaultPrefix - gcp vault prefix (not config prefix for variables), default is 'my-gcp'
 */
export const createGcpVaultEntity = async (
  vaultPrefix = 'my-gcp',
  projectId = 'gcp-sdet-test'
) => {
  const resp = await axios({
    method: 'put',
    url: `${getUrl('vaults')}/${vaultPrefix}`,
    data: {
      name: 'gcp',
      config: {
        project_id: projectId,
      },
    },
  });

  expect(resp.status, 'Status should be 200').to.equal(200);
  return resp.data;
};

/**
 * Delete target vault entity
 * @param {string} vaultPrefix
 */
export const deleteVaultEntity = async (vaultPrefix: string) => {
  const resp = await axios({
    method: 'delete',
    url: `${getUrl('vaults')}/${vaultPrefix}`,
  });

  expect(resp.status, 'Status should be 204').to.equal(204);
};

/**
 * Create a mount wiht kv engine 1
 * @param {string} mountName - target maount name
 * @param {number} kvEngineVersion - version of the kv engine
 */
export const createHcvMountWithTargetKvEngine = async (
  mountName: string,
  kvEngineVersion: number
) => {
  const resp = await axios({
    method: 'post',
    url: `http://${getHost()}:8200/v1/sys/mounts/${mountName}`,
    data: {
      type: 'kv',
      options: {
        version: kvEngineVersion,
      },
    },
    headers: {
      'X-Vault-Token': hcvToken,
    },
  });

  expect(resp.status, 'Status should be 204').to.equal(204);
  return resp.data;
};

/**
 * Create vault-auth vault entity
 * @param {string} vaultEntityName - the name of vault entity
 * @param {string} mountName - target mount name for the entity
 * @param {string} kvEngineVersion - target version of kv engine
 */
export const createVaultAuthVaultEntity = async (
  vaultEntityName = 'kong-auth',
  mountName = 'kong-auth',
  kvEngineVersion = 'v1'
) => {
  const resp = await postNegative(getUrl('vault-auth'), {
    name: vaultEntityName,
    mount: mountName,
    protocol: 'http',
    host: 'host.docker.internal',
    port: 8200,
    vault_token: hcvToken,
    kv: kvEngineVersion,
  });

  return resp;
};

/**
 * Get vault-auth vaults
 */
export const getVaultAuthVaults = async () => {
  const vaultUrl = getUrl('vault-auth');
  const resp = await axios(vaultUrl);
  expect(resp.status, 'Status should be 200').to.equal(200);

  return resp.data;
};

/**
 * Delete target vault-auth plugin vault entity
 * @param {string} vaultName - name of the target vault
 */
export const deleteVaultAuthPluginVaultEntity = async (
  vaultName = 'kong-auth'
) => {
  const resp = await axios({
    method: 'delete',
    url: `${getUrl('vault-auth')}/${vaultName}`,
  });

  expect(resp.status, 'Status should be 204').to.equal(204);
};
