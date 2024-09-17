import axios from 'axios';
import { expect } from '../assert/chai-expect';
import { logResponse } from './logging';
import { App, Environment, getBasePath } from '../config/environment';

const getUrl = (endpoint: string) => {
  const basePath = getBasePath({
    app: App.gateway,
    environment: Environment.gateway.admin,
  });
  return `${basePath}/${endpoint}`;
};

/**
 * Create a user
 * @param {string} name
 * @param {string} token - user token used in API request headers to auth the user
 * @param {boolean} enabled - enabled by-deafult
 * @param {object} payload - optional request body
 * @returns {AxiosResponse}
 */
export const createUser = async (
  name: string,
  token: string,
  enabled?: boolean,
  payload?: object
) => {
  const resp = await axios({
    method: 'post',
    url: `${getUrl('rbac/users')}`,
    data: payload || {
      name,
      user_token: token,
      enabled,
    },
  });
  expect(resp.status, 'Status should be 201').to.equal(201);

  return resp.data;
};

/**
 * Delete a user
 * @param {string} userNameOrId
 * @returns {AxiosResponse}
 */
export const deleteUser = async (userNameOrId: string) => {
  const resp = await axios({
    method: 'delete',
    url: `${getUrl('rbac/users')}/${userNameOrId}`,
  });
  expect(resp.status, 'Status should be 204').to.equal(204);
  logResponse(resp);
  return resp;
};

/**
 * Create a Role
 * @param {string} name - role name
 * @param {string} comment - optional role comment
 * @returns {AxiosResponse}
 */
export const createRole = async (name: string, comment?: string) => {
  const resp = await axios({
    method: 'post',
    url: `${getUrl('rbac/roles')}`,
    data: {
      name,
      comment,
    },
  });
  expect(resp.status, 'Status should be 201').to.equal(201);

  return resp.data;
};

/**
 * Delete a Role
 * @param {string} roleNameOrId
 * @returns {AxiosResponse}
 */
export const deleteRole = async (roleNameOrId: string) => {
  const resp = await axios({
    method: 'delete',
    url: `${getUrl('rbac/roles')}/${roleNameOrId}`,
  });
  expect(resp.status, 'Status should be 204').to.equal(204);

  return resp;
};

/**
 * Create a Role Endpoint Permission
 * @param {string} roleNameOrId - role name or id
 * @param {string} endpoint - target endpoint for permission
 * @param {string} actions - comma separated actions, default all of ('create,update,read,delete')
 * @param {boolean} negative - optional negative boolean, false is default
 * @param {string} workspace - optional workspace name, 'default' is default
 * @returns {AxiosResponse}
 */
export const createRoleEndpointPermission = async (
  roleNameOrId: string,
  endpoint: string,
  actions?: string,
  negative?: boolean,
  workspace?: string
) => {
  actions = actions ? actions : '*';
  const resp = await axios({
    method: 'post',
    url: `${getUrl('rbac/roles')}/${roleNameOrId}/endpoints`,
    data: {
      workspace,
      endpoint,
      negative,
      actions,
    },
  });

  expect(resp.status, 'Status should be 201').to.equal(201);

  return resp.data;
};

/**
 * Delete a Role Endpoint Permission
 * @param {string} roleNameOrId
 * @param {string} endpoint - target permission endpoint
 * @param {string} workspace - optional workspace name, 'default' is default
 * @returns {AxiosResponse}
 */
export const deleteRoleEndpointPermission = async (
  roleNameOrId: string,
  endpoint: string,
  workspace?: string
) => {
  workspace = workspace ? workspace : 'default';

  const resp = await axios({
    method: 'delete',
    url: `${getUrl(
      'rbac/roles'
    )}/${roleNameOrId}/endpoints/${workspace}${endpoint}`,
  });

  expect(resp.status, 'Status should be 204').to.equal(204);

  return resp;
};

/**
 * Add Role to a User
 * @param {string} userNameOrId - user name or id
 * @param {string|Array<string>} roleNames - comma separated list of role names or a single string
 * @returns {AxiosResponse}
 */
export const addRoleToUser = async (
  userNameOrId: string,
  roleNames: string | string[]
) => {
  const resp = await axios({
    method: 'post',
    url: `${getUrl('rbac/users')}/${userNameOrId}/roles`,
    data: {
      roles: roleNames,
    },
  });

  expect(resp.status, 'Status should be 201').to.equal(201);

  return resp.data;
};

/**
 * Delete User role
 * @param {string} userNameOrId - user name or id
 * @param {string|Array<string>} roleNames - comma separated list of role names or a single string
 * @returns {AxiosResponse}
 */
export const deleteUserRole = async (
  userNameOrId: string,
  roleNames: string | string[]
) => {
  const resp = await axios({
    method: 'delete',
    url: `${getUrl('rbac/users')}/${userNameOrId}/roles`,
    data: {
      roles: roleNames,
    },
  });

  expect(resp.status, 'Status should be 204').to.equal(204);

  return resp;
};

/**
 * Create a Role Entity Permission
 * @param {string} roleNameOrId - role name or id
 * @param {string} entity_id - id of the target entity
 * @param {string} entity_type - type of the target entity e.g. 'services'
 * @param {string} actions - optional comma-separated list of actions, 'create,read,update,delete' is default
 * @param {boolean} negative - optional negative boolean, false is default
 * @returns {AxiosResponse}
 */
export const createRoleEntityPermission = async (
  roleNameOrId: string,
  entity_id: string,
  entity_type: string,
  actions?: string,
  negative?: boolean
) => {
  actions = actions ? actions : '*';

  const resp = await axios({
    method: 'post',
    url: `${getUrl('rbac/roles')}/${roleNameOrId}/entities`,
    data: {
      entity_id,
      entity_type,
      actions,
      negative,
    },
  });

  expect(resp.status, 'Status should be 201').to.equal(201);

  return resp.data;
};

/**
 * Delete a Role Entity Permission
 * @param {string} roleNameOrId
 * @param {string} entity_id - id of the target entity
 * @returns {AxiosResponse}
 */
export const deleteRoleEntityPermission = async (
  roleNameOrId: string,
  entity_id: string
) => {
  const resp = await axios({
    method: 'delete',
    url: `${getUrl('rbac/roles')}/${roleNameOrId}/entities/${entity_id}`,
  });

  expect(resp.status, 'Status should be 204').to.equal(204);

  return resp;
};
