import axios, { AxiosResponse } from 'axios';
import https from 'https';
import {
  logResponse,
  getGatewayHost,
  expect,
  getBasePath,
  Environment,
  eventually,
} from '@support';

const defaultPort = 8100;

const agent = new https.Agent({
  rejectUnauthorized: false,
});

axios.defaults.httpsAgent = agent;

const adminUrl = `${getBasePath({
  app: 'gateway',
  environment: Environment.gateway.adminSec,
})}`;

/**
 * Get /status/ready endpoint response
 * @param {number} port - port to use
 */
export const getStatusReadyEndpointResponse = async (
  port = defaultPort
) : Promise<AxiosResponse> =>
    axios({
      url: `https://${getGatewayHost()}:${port}/status/ready`,
      validateStatus: null,
    })

/**
 * Expect /status/ready to return 200 OK
 * @param {number} port - port to use
 */
export const expectStatusReadyEndpointOk = async (port = defaultPort) => {
  const response = await getStatusReadyEndpointResponse(port);
  logResponse(response);
  expect(response.status).to.equal(200);
  expect(response.data.message).to.equal('ready');
};

/**
 * Expect /status/ready to return 503 with given message
 * @param {string} message - message to expect
 * @param {number} port - port to use
 */
export const expectStatusReadyEndpoint503 = async (
  message,
  port = defaultPort
) => {
  const response = await getStatusReadyEndpointResponse(port);
  logResponse(response);

  expect(response.status).to.equal(503);
  expect(response.data.message).to.equal(message);
  return response;
};

/**
 * Wait for /status/ready to return given status
 * @param returnStatus - status to wait for
 * @param timeout - timeout in ms
 * @param port - port to use
 */
export const waitForTargetStatus = async (
  returnStatus: number,
  timeout: number,
  port: number = defaultPort
) => {
  await eventually(async () => {
    const response = await getStatusReadyEndpointResponse(port);
    logResponse(response);
    expect(response.status).to.equal(returnStatus);
  }, timeout);
};

export const getClusteringDataPlanes = async () => {
  const resp = await axios({
    url:`${adminUrl}/clustering/data-planes`,
  })

  return resp.data
}
