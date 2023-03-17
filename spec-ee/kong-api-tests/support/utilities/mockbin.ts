import axios from 'axios';
import { expect } from '../assert/chai-expect';
import { logResponse } from './logging';

const mockbinUrl = 'https://mockbin.org/bin';

/**
 * Create mockbin bin
 */
export const createMockbinBin = async () => {
  const url = `${mockbinUrl}/create`;

  const requestPayload = {
    status: 200,
    statusText: 'OK',
    httpVersion: 'HTTP/1.1',
    headers: [
      {
        name: 'Date',
        value: 'Wed, 21 Jan 2015 23:36:35 GMT',
      },
      {
        name: 'Cache-Control',
        value: 'max-age=7200',
      },
      {
        name: 'Connection',
        value: 'Keep-Alive',
      },
      {
        name: 'Expires',
        value: 'Thu, 22 Jan 2023 01:36:35 GMT',
      },
    ],
    cookies: [],
    content: {
      size: 70972,
      mimeType: 'application/json',
      compression: -21,
    },
    redirectURL: '',
    headersSize: 323,
    bodySize: 70993,
  };

  const resp = await axios({
    method: 'post',
    url,
    data: requestPayload,
    headers: { Host: 'mockbin.org', Accept: 'application/json' },
  });
  logResponse(resp);
  expect(resp.status, 'Status should be 201').equal(201);

  return resp.data;
};

/**
 * Get target mockbin bin http request logs
 * @param binId - mockbin bin id
 */
export const getMockbinLogs = async (binId) => {
  const resp = await axios(`${mockbinUrl}/${binId}/log`);
  logResponse(resp);

  expect(resp.status, 'Status should be 200').equal(200);

  return resp.data;
};
