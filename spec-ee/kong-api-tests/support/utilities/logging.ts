import { AxiosResponse } from 'axios';

/**
 * Define whether to verbose log request responses or not
 */
const isLoggingEnabled = () => {
  return process.env.VERBOSE_RESPONSE_LOGS !== 'false';
};

/**
 * Log the axios response details (url, status, headers, body)
 * @param {AxiosResponse} response axios response
 */
export const logResponse = (response: AxiosResponse): void => {
  if (isLoggingEnabled()) {
    console.log('\n');
    console.log(`URL: ${response.config.url}`);
    console.log(`METHOD: ${response.config.method?.toUpperCase()}`);
    console.log(`STATUS: ${response.status}`);
    console.log('HEADERS:');
    console.log(response.headers);
    console.log('BODY:');
    console.log(JSON.stringify(response.data, null, 2));
    console.log('\n');
  }
};

/**
 * Conditional debug logging to console
 * @param {string} msg message to be logged
 */
export const logDebug = (msg: string): void => {
  if (isLoggingEnabled()) {
    console.log('DEBUG: ', String(msg));
  }
};
