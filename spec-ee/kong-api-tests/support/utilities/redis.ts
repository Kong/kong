import { createClient } from 'redis';
import { Environment, getBasePath, isGateway } from '../config/environment';
import { wait } from './random';
import { expect } from '../assert/chai-expect';

const redisUser = 'redisuser';
const redisPassword = 'redispassword';

export let client: any;

export const createRedisClient = () => {
  const host = getBasePath({ environment: isGateway() ? Environment.gateway.hostName : undefined });
  const redisConnectUrl = `redis://${redisUser}:${redisPassword}@${host}:6379`;
  client = createClient({ url: redisConnectUrl });
};

/**
 * Gets target redis database key metadata
 * @param {string} key - redis database key
 */
export const getTargetKeyData = async (key: any) => {
  const rawKeyDetails = await client.hGetAll(key);
  const keyDetails = Object.entries(rawKeyDetails)[0];

  return { entryCount: keyDetails[1], host: keyDetails[0] };
};

/**
 * Gets Redis database size
 * @param {object} options - options.expectedSize: 2 - to specify target size of DB
 * @returns {number} - DBSize of redis
 */
export const getDbSize = async (options: any = {}) => {
  let dbSize = await client.DBSIZE();

  if (options?.expectedSize && options?.expectedSize !== dbSize) {
    console.log(
      `Getting redis db size one more time as previous one was non-expected: ${dbSize}`
    );
    await wait(4000); // eslint-disable-line no-restricted-syntax
    dbSize = await client.DBSIZE();
  }

  return dbSize;
};

/**
 * Gets all Redis database Keys
 * @returns {object} - redis database keys
 */
export const getAllKeys = async () => {
  const allKeys = await client.sendCommand(['KEYS', '*']);

  return allKeys;
};

/**
 * Shuts down Redis service/container
 */
export const shutDownRedis = async () => {
  return client.sendCommand(['shutdown']);
};

/**
 * Clears all entries from Redis database
 */
export const resetRedisDB = async () => {
  return await client.sendCommand(['flushdb']);
};

/**
 * Reusable assertion to check standardized redis configuration fields
 * @param {object} resp - axios admin api plugin response containg the redis fields
 */
export const expectRedisFieldsInPlugins = (resp) => {
  const redisConfigurations = resp.config.redis

  const redisConfigKeys = [
    'ssl',
    'server_name',
    'sentinel_addresses',
    'password',
    'port',
    'ssl_verify',
    'connect_timeout',
    'send_timeout',
    'read_timeout',
    'host',
    'sentinel_password',
    'sentinel_username',
    'timeout',
    'cluster_addresses',
    'database',
    'keepalive_backlog',
    'keepalive_pool_size',
    'sentinel_role',
    'sentinel_master',
    'username'
  ]

  expect(redisConfigurations, 'Should have redis object in plugin response').to.be.a(
    'object'
  );
  expect(Object.keys(redisConfigurations), 'Should have correct number of redis configurations').to.have.lengthOf(redisConfigKeys.length)
  expect(redisConfigurations, 'Plugin should have correct redis configuration fields').to.have.keys(redisConfigKeys);

  const stringValueKeys = ['server_name', 'sentinel_addresses', 'password', 'host', 'sentinel_password', 'sentinel_username', 'cluster_addresses', 'sentinel_role', 'sentinel_master', 'username'];
  const numberValueKeys = ['port', 'connect_timeout', 'send_timeout', 'read_timeout', 'timeout', 'database', 'keepalive_backlog', 'keepalive_pool_size'];
  const booleanValueKeys = ['ssl', 'ssl_verify'];

  stringValueKeys.forEach((key) => {
    if (redisConfigurations[key] !== null) {
      expect(redisConfigurations[key], `${key} should be a string`).to.be.a('string');
    }
  });

  numberValueKeys.forEach((key) => {
    if (redisConfigurations[key] !== null) {
      expect(redisConfigurations[key], `${key} should be a number`).to.be.a('number');
    }
  });

  booleanValueKeys.forEach((key) => {
    if (redisConfigurations[key]!== null) {
      expect(redisConfigurations[key], `${key} should be a boolean`).to.be.a('boolean');
    }
  });
}