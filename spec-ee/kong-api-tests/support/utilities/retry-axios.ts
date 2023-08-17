import { AxiosResponse } from 'axios';
import { logResponse } from './logging';

/**
 * Retry the given Axios request to match the status code using a timeout and interval
 * @param {Promise<AxiosResponse>} axiosRequest request to perform
 * @param {(response: AxiosResponse) => void} assertions assertions to match
 * @param {number} timeout timeout of retry loop
 * @param {number} interval interval between tries
 * @returns {Promise<AxiosResponse>} axios response object
 */
export const retryRequest = async (
  axiosRequest: () => Promise<AxiosResponse>,
  assertions: (response: AxiosResponse) => void,
  timeout = 15000,
  interval = 3000,
  verbose = false,
): Promise<AxiosResponse> => {
  let response: AxiosResponse = {} as any;
  let errorMsg = '';
  while (timeout >= 0) {
    response = await axiosRequest();
    logResponse(response);
    try {
      assertions(response);
      return response;
    } catch (error: any) {
      if (verbose) {
        errorMsg = error.message;
        console.log(errorMsg);
        console.log(
            `** Assertion(s) Failed -- Retrying in ${interval / 1000} seconds **`
        );
      }
      await new Promise((resolve) => setTimeout(resolve, interval));
      timeout -= interval;
    }
  }

  /*
    * The last try.
    *
    * If we get here, we've timed out,
    * but we might miss a try in some cases,
    * For example, if the timeout is 10 seconds,
    * and the interval is 3 seconds,
    * we'll try 3 times, the last try will be at 9 seconds.
    * But the condition might be true at 10 seconds,
    * and the timeout not is less than 0,
    * so we'll exit the above loop,
    * and we'll miss the last try.
  */
  try {
    assertions(response);
    return response;
  } catch (error: any) {
    errorMsg = error.message;
    console.log(errorMsg);
    console.log(
      `** Assertion(s) Failed -- Retrying in ${interval / 1000} seconds **`
    );
  }

  throw new Error(errorMsg);
};
