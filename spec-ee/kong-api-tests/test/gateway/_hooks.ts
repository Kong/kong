import { createRedisClient, gatewayAuthHeader, isCI, waitForConfigRebuild } from '@support';
import {
  postGatewayEeLicense,
  deleteGatewayEeLicense,
} from '@shared/gateway_workflows';
import axios from 'axios';

export const mochaHooks: Mocha.RootHookObject = {
  beforeAll: async function (this: Mocha.Context) {
    // Set Auth header for Gateway Admin requests
    const { authHeaderKey, authHeaderValue } = gatewayAuthHeader();
    axios.defaults.headers[authHeaderKey] = authHeaderValue;

    // Gateway for API tests starts without EE_LICENSE in CI, hence, we post license at the beggining of all teststo allow us test the functionality of license endpoint
    if (isCI()) {
      await postGatewayEeLicense();
      // Wait for the license propagation completes before release to the test
      await waitForConfigRebuild();
    }
    createRedisClient();
  },

  afterAll: async function (this: Mocha.Context) {
    // Gateway for API tests starts without EE_LICENSE in CI, hence, we delete license at the end of all tests to allow test rerun from clean state
    if (isCI()) {
      await deleteGatewayEeLicense();
    }
  },
};
