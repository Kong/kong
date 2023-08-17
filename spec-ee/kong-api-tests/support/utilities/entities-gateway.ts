import axios, { AxiosRequestHeaders } from 'axios';
import { expect } from '../assert/chai-expect';
import { Environment, getBasePath, isGateway } from '../config/environment';
import { logResponse } from './logging';
import { randomString, wait } from './random';
import { retryRequest } from './retry-axios';
import { getNegative, postNegative } from './negative-axios';

export const getUrl = (endpoint: string) => {
  const basePath = getBasePath({
    environment: isGateway() ? Environment.gateway.admin : undefined,
  });
  return `${basePath}/${endpoint}`;
};

const proxyUrl = `${getBasePath({
  environment: Environment.gateway.proxy,
})}`;

/**
 * Request to create GW Service
 * @param {string} name - service name
 * @param {object} payload - request payload
 * @param {string} workspace - name of the worksapce
 * @returns {AxiosResponse}
 */
export const createGatewayService = async (
  name: string,
  payload?: object,
  workspace?: string
) => {
  payload ? (payload = { name, ...payload }) : null;
  const endpoint = `${workspace}/services`;

  const url = workspace ? `${getUrl(endpoint)}` : getUrl('services');

  const requestPayload = payload || {
    name,
    url: 'http://httpbin/anything',
  };

  const resp = await axios({
    method: 'post',
    url,
    data: requestPayload,
  });
  logResponse(resp);
  expect(resp.status, 'Status should be 201').equal(201);
  expect(resp.data.name, 'Should have correct service name').equal(name);

  return resp.data;
};

/**
 * Request to update GW Service
 * @param {string} serviceIdOrName
 * @param {object} payload - request payload
 * @param {string} workspace - name of the worksapce
 * @returns {AxiosResponse}
 */
export const updateGatewayService = async (
  serviceIdOrName: string,
  payload?: object,
  workspace?: string
) => {
  payload ? (payload = { ...payload }) : null;
  const endpoint = `${workspace}/services/`;

  const url = workspace
    ? `${getUrl(endpoint)}`
    : getUrl(`services/${serviceIdOrName}`);

  const resp = await axios({
    method: 'patch',
    url,
    data: payload,
  });
  logResponse(resp);

  expect(resp.status, 'Status should be 200').equal(200);

  return resp.data;
};

/**
 * Reusable request to delete GW Service
 * @param {string} serviceIdOrName
 * @returns {AxiosResponse}
 */
export const deleteGatewayService = async (serviceIdOrName: string) => {
  const resp = await axios({
    method: 'delete',
    url: `${getUrl('services')}/${serviceIdOrName}`,
  });
  logResponse(resp);

  expect(resp.status, 'Status should be 204').to.equal(204);
  return resp;
};

/**
 * Adds Route to an existing Gateway Service
 * @param {string} serviceIdOrName
 * @param {string[]} paths - paths of the route
 * @param {object} payload - optional request body for the route
 * @param {string} workspace - name of the worksapce
 * @returns {AxiosResponse}
 */
export const createRouteForService = async (
  serviceIdOrName: string,
  paths?: string[],
  payload?: object,
  workspace?: string
) => {
  const endpoint = `${workspace}/services`;
  const url = workspace
    ? `${getUrl(endpoint)}/${serviceIdOrName}/routes`
    : `${getUrl('services')}/${serviceIdOrName}/routes`;

  payload ? (payload = { name: serviceIdOrName, paths, ...payload }) : null;

  const resp = await axios({
    method: 'post',
    url,
    data: payload || {
      name: randomString(),
      paths: paths ? paths : ['/apitest'],
    },
  });
  logResponse(resp);

  expect(resp.status, 'Status should be 201').to.equal(201);
  return resp.data;
};

/**
 * Delete the target route
 * @param {string} routeIdOrName route id or name
 * @param {AxiosRequestHeaders} headers optional headers
 * @returns {AxiosResponse}
 */
export const deleteGatewayRoute = async (
  routeIdOrName: string,
  headers: AxiosRequestHeaders = {}
) => {
  const resp = await axios({
    method: 'delete',
    url: `${getUrl('routes')}/${routeIdOrName}`,
    headers,
  });
  logResponse(resp);

  expect(resp.status, 'Status should be 204').to.equal(204);

  return resp;
};

/**
 * Create a consumer
 * @param {string} username - optional username
 * @param {object} payload - optional payload
 * @returns {AxiosResponse}
 */
export const createConsumer = async (username?: string, payload?: object) => {
  const resp = await axios({
    method: 'post',
    url: getUrl('consumers'),
    data: payload || {
      username: username ? username : randomString(),
    },
  });
  logResponse(resp);

  expect(resp.status, 'Status should be 201').to.equal(201);

  return resp.data;
};

/**
 * Create a consumer
 * @param {string} usernameOrId
 * @returns {AxiosResponse}
 */
export const deleteConsumer = async (usernameOrId: string) => {
  const resp = await axios({
    method: 'delete',
    url: `${getUrl('consumers')}/${usernameOrId}`,
  });
  logResponse(resp);

  expect(resp.status, 'Status should be 204').to.equal(204);

  return resp;
};

/**
 * Create a consumer group
 * @param {string} consumerGroupName - optional consumer group name
 * @param {object} payload - optional payload
 * @returns {AxiosResponse}
 */
export const createConsumerGroup = async (
  consumerGroupName?: string,
  payload?: object
) => {
  const resp = await axios({
    method: 'post',
    url: getUrl('consumer_groups'),
    data: payload || {
      name: consumerGroupName ? consumerGroupName : randomString(),
    },
  });

  logResponse(resp);

  expect(resp.status, 'Status should be 201').to.equal(201);

  return resp.data;
};

/**
 * Delete a consumer group
 * @param {string} consumerGroupName - consumer group name
 * @returns {AxiosResponse}
 */
export const deleteConsumerGroup = async (consumerGroupNameOrId: string) => {
  const resp = await axios({
    method: 'delete',
    url: `${getUrl('consumer_groups')}/${consumerGroupNameOrId}`,
  });
  logResponse(resp);

  expect(resp.status, 'Status should be 204').to.equal(204);

  return resp;
};

/**
 * Create a consumer group scoped plugin
 * @param {string} consumerGroupNameOrId - consumer group name or id
 * @param {object} payload - payload
 * @returns {AxiosResponse}
 */
export const createConsumerGroupScopedPlugin = async (
  consumerGroupNameOrId: string,
  payload: object
) => {
  const resp = await axios({
    method: 'post',
    url: `${getUrl('consumer_groups')}/${consumerGroupNameOrId}/plugins`,
    data: payload,
  });

  logResponse(resp);

  expect(resp.status, 'Status should be 201').to.equal(201);

  return resp.data;
};

/**
 * Add the given consumer to the given consumer group
 * @param {object} consumerNameOrId - consumer name or id
 * @param {string} consumerGroupNameOrId - consumer group name or id
 * @returns {AxiosResponse}
 */
export const addConsumerToConsumerGroup = async (
  consumerNameOrId: object,
  consumerGroupNameOrId: string
) => {
  const resp = await axios({
    method: 'post',
    url: `${getUrl('consumer_groups')}/${consumerGroupNameOrId}/consumers`,
    data: {
      consumer: consumerNameOrId,
    },
  });

  logResponse(resp);

  expect(resp.status, 'Status should be 201').to.equal(201);

  return resp;
};

/**
 * Remove the given consumer from the given consumer group
 * @param {object} consumerNameOrId - consumer name or id
 * @param {string} consumerGroupNameOrId - consumer group name or id
 * @returns {AxiosResponse}
 */
export const removeConsumerFromConsumerGroup = async (
  consumerNameOrId: object,
  consumerGroupNameOrId: string
) => {
  const resp = await axios({
    method: 'delete',
    url: `${getUrl(
      'consumer_groups'
    )}/${consumerGroupNameOrId}/consumers/${consumerNameOrId}`,
  });

  logResponse(resp);

  expect(resp.status, 'Status should be 204').to.equal(204);

  return resp.data;
};

/**
 * Create a consumer group setting
 * @param {string} consumerGroupNameOrId - consumer group name or id
 * @param {string} pluginName - plugin name
 * @param {string} pluginId - id
 * @param {object} settings - settings
 * @returns {AxiosResponse}
 */
export const createConsumerGroupSettings = async (
  consumerGroupNameOrId: string,
  pluginName: string,
  pluginId: string,
  settings: object
) => {
  const resp = await axios({
    method: 'put',
    url: `${getUrl(
      'consumer_groups'
    )}/${consumerGroupNameOrId}/plugins/${pluginId}`,
    data: {
      name: pluginName,
      config: settings,
    },
  });

  logResponse(resp);

  expect(resp.status, 'Status should be 200').to.equal(200);

  return resp.data;
};

/**
 * Create key-auth credentials for a consumer
 * @param {string} consumerNameOrId- consumer name or id
 * @returns {AxiosResponse}
 */
export const createKeyAuthCredentialsForConsumer = async (
  consumerNameOrId: string
) => {
  const resp = await axios({
    method: 'post',
    url: `${getUrl('consumers')}/${consumerNameOrId}/key-auth-enc`,
  });

  logResponse(resp);

  expect(resp.status, 'Status should be 201').to.equal(201);

  return resp.data;
};

/**
 * Create basic-auth plugin credentials for a given consumer
 * @param consumerNameOrId name or id of the target consumer
 * @param username optional basic-auth username
 * @param password optional basic-auth password
 * @returns {AxiosResponse}
 */
export const createBasicAuthCredentialForConsumer = async (
  consumerNameOrId: string,
  username?: string,
  password?: string
) => {
  const resp = await axios({
    method: 'post',
    url: `${getUrl('consumers')}/${consumerNameOrId}/basic-auth`,
    data: {
      username: username ? username : randomString(),
      password: password ? password : randomString(),
    },
  });
  logResponse(resp);
  expect(resp.status, 'Status should be 201').to.equal(201);

  return resp;
};

/**
 * Get all existing workspaces
 * @returns {AxiosResponse}
 */
export const getWorkspaces = async () => {
  const resp = await axios(`${getUrl('workspaces')}`);
  logResponse(resp);
  expect(resp.status, 'Status should be 200').to.equal(200);

  return resp.data;
};

/**
 * Create a workspace
 * @param {string} workspaceName
 * @returns {AxiosResponse}
 */
export const createWorkspace = async (workspaceName: string) => {
  const resp = await axios({
    method: 'post',
    url: `${getUrl('workspaces')}`,
    data: {
      name: workspaceName,
    },
  });
  logResponse(resp);
  expect(resp.status, 'Status should be 201').to.equal(201);

  return resp.data;
};

/**
 * Delete a workspace
 * @param {string} workspaceNameOrId
 * @returns {AxiosResponse}
 */
export const deleteWorkspace = async (workspaceNameOrId: string) => {
  const resp = await axios({
    method: 'delete',
    url: `${getUrl('workspaces')}/${workspaceNameOrId}`,
  });
  logResponse(resp);
  expect(resp.status, 'Status should be 204').to.equal(204);

  return resp;
};

/**
 * Create a Plugin
 * @param {object} pluginPayload - request body for plugin creation
 * @param {string} workspace - optional name of the workspace to create plugin
 * @returns {AxiosResponse}
 */
export const createPlugin = async (
  pluginPayload: object,
  workspace?: string
) => {
  workspace = workspace ? workspace : 'default';
  const endpoint = `${workspace}/plugins`;

  const resp = await axios({
    method: 'post',
    url: `${getUrl(endpoint)}`,
    data: pluginPayload,
  });
  logResponse(resp);
  expect(resp.status, 'Status should be 201').to.equal(201);

  return resp.data;
};

/**
 * Delete a plugin
 * @param {string} pluginId
 * @returns {AxiosResponse}
 */
export const deletePlugin = async (pluginId: string) => {
  const resp = await axios({
    method: 'delete',
    url: `${getUrl('plugins')}/${pluginId}`,
  });
  logResponse(resp);
  expect(resp.status, 'Status should be 204').to.equal(204);
};

/**
 * Delete kong cache
 */
export const deleteCache = async () => {
  const resp = await axios({
    method: 'delete',
    url: `${getUrl('cache')}`,
  });
  logResponse(resp);
  expect(resp.status, 'Status should be 204').to.equal(204);
};

/**
 * Create a service and a route, send request to route until it is 200
 * after getting 200, delete the service/route, send request again to the route until it is 404
 * This triggers router rebuild making sure all configuration updates have been propagated in kong
 * @param {object} options
 * @property {number} timeout - retryRequest timeout
 * @property {number} interval - retryRequest interval
 * @property {object} proxyReqHeader - custom proxy request header e.g. key-auth key
 */
export const waitForConfigRebuild = async (options: any = {}) => {
  // create a service
  const service = await createGatewayService(`routerRebuild-${randomString()}`);
  const serviceId = service.id;

  // create a route for a service
  const routePath = `/routerRebuild-${randomString()}`;
  const route = await createRouteForService(serviceId, [routePath]);
  const routeId = route.id;

  // send request to route until response is 200
  const reqSuccess = () => getNegative(`${proxyUrl}${routePath}`, options?.proxyReqHeader);
  const assertionsSuccess = (resp) => {
    expect(
      resp.status,
      'waitForConfigRebuild - route should return 200'
    ).to.equal(200);
  };

  await retryRequest(
    reqSuccess,
    assertionsSuccess,
    options?.timeout,
    options?.interval,
    options?.verbose,
  );

  // removing the service and the route
  await deleteGatewayRoute(routeId);
  await deleteGatewayService(serviceId);

  // send request to route until response is 404
  const reqFail = () => getNegative(`${proxyUrl}${routePath}`, options?.proxyReqHeader);
  const assertionsFail = (resp) => {
    expect(
      resp.status,
      'waitForConfigRebuild - route should return 404'
    ).to.equal(404);
  };

  await retryRequest(
    reqFail,
    assertionsFail,
    options?.timeout,
    options?.interval
  );
};
