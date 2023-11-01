import axios from 'axios';
import { expect } from '../assert/chai-expect';
import { Environment, getBasePath } from '../config/environment';
import { postNegative } from './negative-axios';

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
 * Creates hcv backend vault
 * @param {string} targetMount - name of the target hcv mount
 * @param {string} targetHcvToken - hcv root token
 * @param {string} vaultPrefix - hcv vault prefix (not config prefix for variables), default is 'my-hcv'
 */
export const createHcvVault = async (
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
