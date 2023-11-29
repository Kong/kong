import axios from 'axios';
import { wait } from './random';
import { expect } from '../assert/chai-expect';
import { getBasePath, Environment, isGateway } from '@support';
import https from 'https';

const host = getBasePath({ environment: isGateway() ? Environment.gateway.hostName : undefined });
const metricsUrl = `https://${host}:8100/metrics`;

const agent = new https.Agent({
  rejectUnauthorized: false,
});

axios.defaults.httpsAgent = agent;

/**
 * Send a request to the status API to get all metrics
 * @returns metrics response
 */
const getAllMetrics = async () => {
  const resp = await axios({
    method: 'get',
    url: metricsUrl,
  });

  expect(resp.status, 'Status for getting /metrics should be 200').equal(200);
  return resp.data;
};

/**
 * Return a selected value from the metrics API if it is found
 * @param {string} metricName - name of the metric to get, eg kong_data_plane_config_hash
 * @returns {string} initial shared dict byte value
 */
export const getMetric = async (metricName) => {
  const metrics = await getAllMetrics();
  const re = new RegExp(`${metricName}\\{.+\\} (.+)`);
  const match = metrics.match(re);
  if (match) return match[1];
};

/**
 * Recurse till the configuration hash changes twice and return the hash
 * @param {string} configHash - initial value of the metric
 * @param {object} options
 * @property {number} targetNumberOfConfigHashChanges - times the config hash needs to ne changed to exit the recursion
 * @property {number} timeout - timeout for waiting for configuration hash update
 * @returns {string} - the latest configuration hash
 */
export const waitForConfigHashUpdate = async (
  configHash,
  options: any = {}
) => {
  options = { targetNumberOfConfigHashChanges: 1, timeout: 14000, ...options };
  const currentHash = await getMetric('kong_data_plane_config_hash');
  const interval = 2000;
  let timesHashChanged = options.timesHashChanged
    ? options.timesHashChanged
    : 0;

  // wait the given timeout period if target number of hash changes wasn't reached
  if (
    currentHash === configHash ||
    timesHashChanged !== options.targetNumberOfConfigHashChanges
  ) {
    await wait(interval); // eslint-disable-line no-restricted-syntax
  }

  // return current hash value only when timeout is reached or the amount of hash changes
  // equals to the given number. Sometimes hash needs to change twice for kong config changes to take effect
  if (
    options?.timeout <= 0 ||
    timesHashChanged === options.targetNumberOfConfigHashChanges
  ) {
    return currentHash;
  } else {
    // increase the times that hash has changed only when current hash doesn't equal previous hash
    if (currentHash !== configHash) {
      timesHashChanged += 1;
    }

    // decrease the timeout for next iteration/recursion
    options.timeout -= interval;

    // note that here we are passing currentHash as parameter instead of configHash
    // this is done to keep track of how many times the hash has changed
    return await waitForConfigHashUpdate(currentHash, {
      targetNumberOfConfigHashChanges: options.targetNumberOfConfigHashChanges,
      timeout: options.timeout,
      timesHashChanged,
    });
  }
};

/**
 * Return the shared dict byte value from the metrics API
 * @param {string }dict_name - name of the shared dict to check
 * @returns shared dict byte value
 */
export const getSharedDictValue = async (dict_name) => {
  const metrics = await getAllMetrics();
  const re = new RegExp(
    `kong_memory_lua_shared_dict_bytes\\{.+shared_dict="${dict_name}\\} (.+)`
  );
  return metrics.match(re)[1];
};

/**
 * Return when given shared dict value has changed after a request is sent
 * @param {string} initialValue - initial value of the metric
 * @param {string} dict_name - name of the shared dict to check
 */
export const waitForDictUpdate = async (initialValue, dict_name) => {
  let timeWaited = 0;
  const timeout = 5000;

  if (initialValue != false) {
    while (
      (await getSharedDictValue(dict_name)) == initialValue &&
      timeWaited <= timeout
    ) {
      wait(10);
      timeWaited += 10;
    }
  }
};
