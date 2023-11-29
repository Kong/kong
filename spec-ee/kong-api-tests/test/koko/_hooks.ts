import { registerOrgAndAuthenticateAdmin } from '@shared/kauth_workflows';
import { getDefaultRuntimeGroup, setupKonnectDataPlane } from '@shared/konnect_workflows';
import { getAuthOptions, removeCertficatesAndKeys, stopAndRemoveTargetContainer, KokoAuthHeaders  } from '@support';
import axios from 'axios';

export const mochaHooks: Mocha.RootHookObject = {
  beforeAll: async function (this: Mocha.Context) {
    try {
      await registerOrgAndAuthenticateAdmin();
      // get the deafult runtime group id which is being created automatically with the Organization
      await getDefaultRuntimeGroup();

      const kokoAuthHeaders: KokoAuthHeaders = getAuthOptions()?.headers;
      Object.entries(kokoAuthHeaders).forEach(([key, value]) => {
        axios.defaults.headers[key] = value;
      });

      // setup the local Data Plane for Konnect
      await setupKonnectDataPlane()
      
    } catch (error) {
      console.error(error);
      process.exit(1);
    }
  },

  afterAll: async function (this: Mocha.Context) {
    stopAndRemoveTargetContainer('konnect-dp1')

    // remove the generated certificates and keys for konnect data plane
    removeCertficatesAndKeys()
  },
};
