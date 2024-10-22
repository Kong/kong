import { clearAllKongResources, createRedisClient, gatewayAuthHeader, isCI, isKongOSS, waitForConfigRebuild } from '@support';
import {
  postGatewayEeLicense,
  deleteGatewayEeLicense,
} from '@shared/gateway_workflows';
import axios from 'axios';

export const mochaHooks: Mocha.RootHookObject = {
  beforeAll: async function (this: Mocha.Context) {
    try {
        // Set Auth header for Gateway Admin requests
        const { authHeaderKey, authHeaderValue } = gatewayAuthHeader();
        axios.defaults.headers[authHeaderKey] = authHeaderValue;
        createRedisClient();

      if (isCI() && !isKongOSS()) {
        // Gateway for API tests starts without EE_LICENSE in CI, hence, we post license at the beginning of all tests to allow us test the functionality of license endpoint
        await postGatewayEeLicense();
        // Wait for the license propagation to complete before release to the test
        await waitForConfigRebuild();
        console.info('waitForConfigRebuild successfully executed after posting the ee license\n')
      }
    } catch (err) {
      console.error(`Something went wrong in beforeAll hook while rebuilding configuration: ${err}\n`)

      // remove all possible remnant entities from failed waitForConfigRebuild above to start tests from clean state and avoid flakiness
      await clearAllKongResources();
    }
  },

  afterAll: async function (this: Mocha.Context) {
    // Gateway for API tests starts without EE_LICENSE in CI, hence, we delete license at the end of all tests to allow test rerun from clean state
    // Skipping this step for OSS tests
    if (isCI() && !isKongOSS()) {
      await deleteGatewayEeLicense();
    }
  },
};
