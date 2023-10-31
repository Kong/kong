import axios from 'axios';
import { expect } from '../assert/chai-expect';
import { logResponse } from './logging';

export const getHttpLogServerLogs = async () => {
  const resp = await axios('http://localhost:9300/logs');
  logResponse(resp);

  expect(resp.status, 'Status should be 200').equal(200);

  return resp.data;
};

export const deleteHttpLogServerLogs = async () => {
  const resp = await axios({
    method: 'delete',
    url: 'http://localhost:9300/logs'
  });
  logResponse(resp);

  expect(resp.status, 'Status should be 204').equal(204);
};
