import axios from 'axios';
import { expect } from '../assert/chai-expect';
import { getUrl } from './entities-gateway';
import { logResponse } from './logging';

/**
 * Create a key-set
 * @param {string} name - key set name, default is null
 * @returns {AxiosResponse}
 */
export const createKeySetsForJweDecryptPlugin = async (name?: string) => {
  const resp = await axios({
    method: 'post',
    url: getUrl('key-sets'),
    data: { name: name ? name : null },
  });
  logResponse(resp);

  expect(resp.status, 'Status should be 201').to.equal(201);

  return resp.data;
};
/**
 * Reusable request to delete a Key-Set for jwe-decrypt plugin
 * @param {string} keySetIdOrName
 * @returns {AxiosResponse}
 */
export const deleteKeySetsForJweDecryptPlugin = async (
  keySetIdOrName: string
) => {
  const resp = await axios({
    method: 'delete',
    url: `${getUrl('key-sets')}/${keySetIdOrName}`,
  });
  logResponse(resp);

  expect(resp.status, 'Status should be 204').to.equal(204);
  return resp.data;
};

/**
 * Create keys
 * @param {object} keysPayload - request body for keys creation
 * @returns {AxiosResponse}
 */
export const createEncryptedKeysForJweDecryptPlugin = async (
  keysPayload: object
) => {
  const resp = await axios({
    method: 'post',
    url: getUrl('keys'),
    data: keysPayload,
  });
  logResponse(resp);

  expect(resp.status, 'Status should be 201').to.equal(201);

  return resp.data;
};

/**
 * Reusable request to delete Keys for jwe-decrypt plugin
 * @param {string} keysIdOrName
 * @returns {AxiosResponse}
 */
export const deleteEncryptedKeysForJweDecryptPlugin = async (
  keysIdOrName: string
) => {
  const resp = await axios({
    method: 'delete',
    url: `${getUrl('key-sets')}/${keysIdOrName}`,
  });
  logResponse(resp);

  expect(resp.status, 'Status should be 204').to.equal(204);
  return resp.data;
};
