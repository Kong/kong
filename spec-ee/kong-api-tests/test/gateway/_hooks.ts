import { createRedisClient, gatewayAuthHeader, isCI, waitForConfigRebuild, eventually } from '@support';
import {
  postGatewayEeLicense,
  deleteGatewayEeLicense,
} from '@shared/gateway_workflows';
import { expect } from '../../support/assert/chai-expect';
import axios from 'axios';

export const mochaHooks: Mocha.RootHookObject = {
  beforeAll: async function (this: Mocha.Context) {
    // Set Auth header for Gateway Admin requests
    const { authHeaderKey, authHeaderValue } = gatewayAuthHeader();
    axios.defaults.headers[authHeaderKey] = authHeaderValue;

    // Gateway for API tests starts without EE_LICENSE in CI, hence, we post license at the beginning of all tests to allow us test the functionality of license endpoint
    try {
      if (isCI()) {
        await postGatewayEeLicense();
        // Wait for the license propagation completes before release to the test
        // configRebuild is wrapped with eventually as sometimes it returns 401 error for route creation
        await eventually(async () => {
          const intitialConfigRebuildSuccess = await waitForConfigRebuild();
          expect(intitialConfigRebuildSuccess).to.be.true
        }, 20000, 3000, true)
        
      }
      createRedisClient();
    } catch (err) {
      console.log(`Something went wrong in beforeAll hook while rebuilding configuration: ${err}`)
      process.exit(1)
    }
  },

  afterAll: async function (this: Mocha.Context) {
    // Gateway for API tests starts without EE_LICENSE in CI, hence, we delete license at the end of all tests to allow test rerun from clean state
    if (isCI()) {
      await deleteGatewayEeLicense();
    }
  },
};
