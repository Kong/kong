import axios, { AxiosRequestHeaders, Method } from 'axios';
import https from 'https';

const agent = new https.Agent({
  rejectUnauthorized: false,
});

/**
 * Sends axios GET request which is expected to fail,
 * the request promise will always be reject so that test authors can perform checks on the failed response
 * @param {string} url - Axios request url
 * @param {AxiosRequestHeaders} headers - otpional request headers
 * @param {object|string} body - request body
 * @param {object} additionalOptions - { rejectUnauthorized: true } to ignore self-signed cert error
 * @returns {Object} - response property of the axios error response object
 */
export const getNegative = async (
  url: string,
  headers: AxiosRequestHeaders = {},
  body?: object | string,
  additionalOptions?: object | any
) : Promise<any> =>
    axios({
        url,
        headers,
        data: body,
        // Don't raise errors for any status code
        validateStatus: null,
        httpsAgent: additionalOptions?.rejectUnauthorized ? agent : null,
    });

/**
 * Sends post request which expected to fail,
 * the request promise will always be rejected so that test authors can perform checks on the failed response
 * @param {string} url - Axios request url
 * @param {object} data - Axios request data, defaults to empty object
 * @param {Method} method - Axios request method, defaults to post
 * @param {AxiosRequestHeaders} headers - Axios request headers, deafults to empty object
 * @param {object} additionalOptions - { rejectUnauthorized: true } to ignore self-signed cert error
 * @returns {Object} - response property of the axios error response object
 */
export const postNegative = async (
  url: string,
  data: object = {},
  method: Method = 'post',
  headers: AxiosRequestHeaders = {},
  additionalOptions?: object | any
) : Promise<any> =>
    axios({
        method,
        headers,
        url,
        data,
        // Don't raise errors for any status code
        validateStatus: null,
        httpsAgent: additionalOptions?.rejectUnauthorized ? agent : null,
    });
