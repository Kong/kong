import { execSync } from 'child_process';
import { getNegative } from './negative-axios';
import { wait } from './random';
import { logResponse } from './logging';
import { expect } from '../assert/chai-expect';

/**
 * Calculates the wait time to send a request based on the desired window ("current" or "next"),
 * ensuring there's a safe buffer before the next window starts.
 * The function is optimized for window lengths between 10 and 60 seconds, with a default of 10 seconds.
 * 
 * @param {string} containerName - The name of the Docker container to check the current UTC time in.
 * @param {number} windowLengthInSeconds - Length of the time window in seconds, defaulting to 10 seconds.
 * @param {number} safeTimeBeforeNextWindowInSeconds - The safe time buffer before the next window starts, in seconds.
 * @returns {Promise<object>} - A promise that resolves with the number of milliseconds to wait before sending the request.
 */
export const calculateWaitTimeForWindow = async (containerName, windowLengthInSeconds = 10, safeTimeBeforeNextWindowInSeconds = 3) => {
  // Ensure windowLength is within the supported range.
  if (windowLengthInSeconds < 10 || windowLengthInSeconds > 60) {
    throw new Error("Window length must be between 10 and 60 seconds.");
  }

  const currentUTCTimeStr = execSync(`docker exec $(docker ps -aqf name="${containerName}") date -u +%s`).toString().trim();
  const currentUTCTime = parseInt(currentUTCTimeStr, 10);
  const timeSinceWindowStart = currentUTCTime % windowLengthInSeconds;
  let waitTimeInSeconds:number;
  let shallRetrigger = false;

  // Define a minimal buffer time (in seconds) to avoid sending at the exact start of the next window.
  const startWindowBufferInSeconds = 3;

  if(timeSinceWindowStart <= 1){
    waitTimeInSeconds = 0;
    shallRetrigger = true;
  } else if (timeSinceWindowStart < (windowLengthInSeconds - safeTimeBeforeNextWindowInSeconds) - startWindowBufferInSeconds) {
    // If within the safe period and not too close to the window's end, no need to wait.
    waitTimeInSeconds = 0;
  } else {
    // If too close to the window's end or at the start of the next window, calculate wait time to ensure we're in the safe period of the next window.
    waitTimeInSeconds = windowLengthInSeconds - timeSinceWindowStart + startWindowBufferInSeconds;
    shallRetrigger = true;
  }

  // Calculate sendWindow in seconds for the next safe request send out time, but will be rounded down to the window time
  // math.floor(time / size) * size here copied window calculation logic in RLA
  const sendWindow = Math.floor((currentUTCTime + waitTimeInSeconds)/windowLengthInSeconds)*windowLengthInSeconds;

  // Return the object with sendWindow and waitTime details.
  return {
    sendWindow: sendWindow.toString(), // Keep it in epoch time format, converted to string to match your initial format request.
    waitTimeInSeconds: waitTimeInSeconds,
    waitTimeInMilliseconds: waitTimeInSeconds * 1000,
    shallRetrigger
  };
};
/**
 * Sends an HTTP request at a targeted time window, ensuring the request lands safely within the specified window.
 * 
 * @param {string} urlProxy - The proxy URL to which the request will be sent.
 * @param {Object} headers - The headers to be included in the request.
 * @param {string} containerName - The name of the container being used.
 * @param {string} [targetWindow="current"] - Specifies whether to target the "current" or "next" window for sending the request.
 * @param {number} [windowLengthInSeconds=10] - Optional. The length of the time window in seconds. Defaults to 10.
 * @param {number} [safeTimeBeforeNextWindowInSeconds=4] - Optional. The safe time buffer before the next window starts, in seconds. Defaults to 4.
 * @param {number} [rateLimit=1] - Optional. The number of requests to send within the rate limit.
 * 
 * @returns {Promise<{response: any, waited: boolean}>} - A promise that resolves to an object containing:
 *   - `response`: The HTTP response from the final request.
 *   - `waited`: A boolean indicating whether there was a delay before sending the request.
 */
export const sendRequestInWindow = async ({
  url,
  headers,
  containerName,
  windowLengthInSeconds = 10,
  safeTimeBeforeNextWindowInSeconds = 4,
  rateLimit = 1
}:{url:string, 
  headers?:object, 
  containerName:string, 
  windowLengthInSeconds?:number, 
  safeTimeBeforeNextWindowInSeconds?:number, 
  rateLimit?:number}) => {
  type RequestResult = { response: any; waited: boolean; sendWindow: string};
  let waited = false;
  const calculate: any = await calculateWaitTimeForWindow(containerName, windowLengthInSeconds, safeTimeBeforeNextWindowInSeconds);
  const waitTime = calculate.waitTimeInMilliseconds;
  const shallRetrigger = calculate.shallRetrigger;
  const sendWindow = calculate.sendWindow;
  console.log(`Waiting for ${waitTime} milliseconds before sending the request to ensure it lands in the same window, retrigger option is ${shallRetrigger}.`);

  // Use the wait function to delay the request sending.
  await wait(waitTime);// eslint-disable-line no-restricted-syntax
  if (shallRetrigger === true) {
    for (let i = 0; i <= rateLimit; i++) {
      //Send request to reach rate limit
      const resp = await getNegative(url, headers);
      logResponse(resp);
    }
    waited = true;
  }
  //Send request for final check
  const response = await getNegative(url, headers);
  logResponse(response);
  const result: RequestResult = { response, waited, sendWindow };
  return result;
};

/**
* Verifies the effect of rate limiting by sending multiple requests to the specified URL.
* It checks if the requests are rejected with a specific status code after exceeding the rate limit.
*
* @param {Object} params - The parameters for the verification function.
* @param {number} params.rateLimit - The maximum allowed number of requests before triggering rate limiting.
* @param {number} [params.rejectCode=429] - The expected status code when rate limiting is triggered (default is 429).
* @param {number} [params.passCode=200] - The expected status code when requests are under the rate limit (default is 200).
* @param {string} params.url - The URL to send the requests to for rate limit verification.
* @param {object} [params.headers] - Optional headers to include with each request.
* 
* @returns {Promise<void>} - Resolves if the rate limit verification is successful, otherwise throws an error.
*
* @example
* // Verifies that the rate limit is enforced with a 429 status code after 5 requests
* await verifyRateLimitingEffect({ rateLimit: 5, url: "https://api.example.com", headers: { "Authorization": "Bearer token" } });
*/
export const verifyRateLimitingEffect = async ({
  rateLimit,
  rejectCode = 429,
  passCode = 200,
  url,
  headers
}: {
  rateLimit: number;
  rejectCode?: number;
  passCode?: number;
  url: string;
  headers?: object;
}) => {
  for (let i = 0; i <= rateLimit; i++) {
    const resp: any = await getNegative(url, headers);
    logResponse(resp);

    if (i === rateLimit) {
      expect(resp.status, `Status should be ${rejectCode}`).to.equal(rejectCode);
    } else {
      expect(resp.status, `Status should be ${rejectCode}`).to.equal(passCode);
    }
  }
};