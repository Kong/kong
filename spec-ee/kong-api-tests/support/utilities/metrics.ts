import { gatewayAuthHeader } from '../config/gateway-vars';
const { authHeaderKey, authHeaderValue } = gatewayAuthHeader();
import axios from 'axios';
import { wait } from './random';
import { getBasePath, Environment } from '@support';
import https from 'https';
import { isGwHybrid } from '../config/gateway-vars';

const headers = { authHeaderKey: authHeaderValue };
const host = getBasePath({ environment: Environment.gateway.hostName });
const metricsUrl = `https://${host}:8100/metrics`;
const isHybrid = isGwHybrid();

const agent = new https.Agent({
  rejectUnauthorized: false,
});

axios.defaults.httpsAgent = agent;

/**
 * Send a request to the status API to get metrics
 * @returns metrics response
 */
export const getAllMetrics = async () => {
  const resp = await axios({
    method: 'get',
    url: metricsUrl,
    headers,
  });
  if (resp.status == 200) return resp.data;
  else return '';
};

/**
 * Return a selected value from the metrics API
 * @param metricName - name of the metric to get, eg kong_data_plane_config_hash
 * @returns initial shared dict byte value
 */
export const getMetric = async (metricName) => {
  if (isHybrid) {
    const metrics = await getAllMetrics();
    const re = new RegExp(`${metricName}\\{.+\\} (.+)`);
    const match = metrics.match(re);
    if (match) return match[1];
  }
  return '';
};

/**
 * Return the shared dict byte value from the metrics API
 * @param dict_name - name of the shared dict to check
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
 * Return when given config hash value has changed after a request is sent
 * @param initialValue - initial value of the metric
 */
export const waitForHashUpdate = async (configHash, altWait) => {
  if (configHash != '') {
    let timeWaited = 0;
    const timeout = 5000;

    while (
      (await getMetric('kong_data_plane_config_hash')) == configHash &&
      timeWaited <= timeout
    ) {
      wait(10);
      timeWaited += 10;
    }
    return await getMetric('kong_data_plane_config_hash');
  } else {
    await wait(altWait);
    return '';
  }
};

/**
 * Return when given shared dict value has changed after a request is sent
 * @param initialValue - initial value of the metric
 * @param dict_name - name of the shared dict to check
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
