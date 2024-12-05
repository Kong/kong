import { AxiosResponse } from 'axios';
import { logResponse } from './logging';
import { eventually } from '@support';

/**
 * Retry the given Axios request to match the status code using a timeout and interval
 * @param axiosRequest - request to perform
 * @param assertions - assertions to match
 * @param timeout - max amount of time before raising an assertion error
 * @param delay - initial delay between request retries
 * @returns {Promise<AxiosResponse>} axios response object
 */
export const retryRequest = async (
  axiosRequest: () => Promise<AxiosResponse>,
  assertions: (response: AxiosResponse) => void,
  timeout = 30000,
  delay = 100,
  verbose = false,
): Promise<AxiosResponse> => {
  const wrapper: () => Promise<AxiosResponse> = async () => {
    const response = await axiosRequest();
    logResponse(response);
    assertions(response);
    return response;
  };

  return await eventually(wrapper, timeout, delay, verbose);
};
