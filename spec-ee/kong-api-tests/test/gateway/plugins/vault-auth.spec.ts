import axios from 'axios';
import {
  expect,
  getBasePath,
  Environment,
  createGatewayService,
  createRouteForService,
  deleteGatewayRoute,
  deleteGatewayService,
  getNegative,
  randomString,
  wait,
  createHcvMountWithTargetKvEngine,
  createVaultAuthVaultEntity,
  deleteVaultAuthPluginVaultEntity,
  deleteHcvSecretMount,
  createConsumer,
  deleteConsumer,
  createHcvVaultSecrets,
  isLocalDatabase,
  logResponse,
  retryRequest,
  waitForCacheInvalidation,
} from '@support';

const kvEngineVersions = ['v1', 'v2'];
const islocalDB = isLocalDatabase();

kvEngineVersions.forEach((kvVersion) => {
  describe(`Vault-Auth Plugin Tests with HCV kv engine '${kvVersion}'`, function () {
    let serviceId = '';
    let routeId = '';
    let vaPluginId = '';
    let vaultEntityId = '';
    let consumerId = '';

    const credentials: any = {};
    const customCredentials = {
      access_token: '7pC8fPiL022kX5MZviUXVF0JaHOeb5JG',
      created_at: 1660654457,
      secret_token: 'egapdBDCPGUPQJzEXc2Kzy0ktcirIskx',
      ttl: 1,
    };

    const vaultName = 'kong-auth';
    const waitTime = 5000;
    const longWaitTime = 8000;
    const path = `/${randomString()}`;
    const url = `${getBasePath({
      environment: Environment.gateway.admin,
    })}`;

    const proxyUrl = getBasePath({ environment: Environment.gateway.proxy });

    before(async function () {
      const service = await createGatewayService('VaultAuthService');
      serviceId = service.id;
      const route = await createRouteForService(serviceId, [path]);
      routeId = route.id;
      const consumer = await createConsumer();
      consumerId = consumer.id;

      // creating kong-auth kv engine 1 mount in hcv vault
      await createHcvMountWithTargetKvEngine(
        vaultName,
        Number(kvVersion.slice(1))
      );
    });

    it(`should create hcv vault entity for kong-auth with kv '${kvVersion}'`, async function () {
      const resp = await createVaultAuthVaultEntity(
        vaultName,
        vaultName,
        kvVersion
      );
      logResponse(resp);

      expect(resp.status, 'Status should be 201').to.equal(201);
      vaultEntityId = resp.data.id;
      expect(vaultEntityId, 'Vault id should be a string').to.be.string;
    });

    it('should not create hcv vault entity with wrong kv value', async function () {
      const resp = await createVaultAuthVaultEntity(
        vaultName,
        vaultName,
        'v111'
      );
      logResponse(resp);

      expect(resp.status, 'Status should be 400').to.equal(400);
      expect(resp.data.message, 'Should have correct error message').to.include(
        'schema violation (kv: expected one of: v1, v2)'
      );
    });

    it('should create vault-auth plugin with reference to vault entity', async function () {
      const pluginPayload = {
        name: 'vault-auth',
        service: {
          id: serviceId,
        },
        route: {
          id: routeId,
        },
        config: {
          vault: {
            id: vaultEntityId,
          },
        },
      };

      const resp: any = await axios({
        method: 'post',
        url: `${url}/plugins`,
        data: pluginPayload,
      });
      logResponse(resp);

      expect(resp.status, 'Status should be 201').to.equal(201);
      vaPluginId = resp.data.id;

      expect(vaPluginId, 'Plugin Id should be a string').to.be.string;
      expect(
        resp.data.config.vault.id,
        'Should have correct vault id'
      ).to.equal(vaultEntityId);

      await wait(islocalDB ? 0 : longWaitTime); // eslint-disable-line no-restricted-syntax
    });

    it('should not proxy a request without access/secret token pair', async function () {
      const req = () => getNegative(`${proxyUrl}${path}`);

      const assertions = (resp) => {
        expect(resp.status, 'Status should be 401').to.equal(401);
        expect(resp.data.message, 'should have correct error message').to.eq(
          'No access token found'
        );
      };

      await retryRequest(req, assertions);
    });

    it('should create access/secret token pair for a consumer', async function () {
      const resp = await axios({
        method: 'post',
        url: `${url}/vault-auth/${vaultName}/credentials/${consumerId}`,
      });
      logResponse(resp);

      expect(resp.status, 'Status should be 201').to.equal(201);
      expect(resp.data.data.access_token, 'should see access_token in response')
        .to.be.string;
      expect(resp.data.data.secret_token, 'should see secret_token in response')
        .to.be.string;

      credentials['access_token'] = resp.data.data.access_token;
      credentials['secret_token'] = resp.data.data.secret_token;

      await wait(islocalDB ? 0 : longWaitTime); // eslint-disable-line no-restricted-syntax
    });

    it('should proxy a request with correct secrets as querystring parameters', async function () {
      const req = () =>
        axios({
          method: 'get',
          url: `${proxyUrl}${path}?access_token=${credentials.access_token}&secret_token=${credentials.secret_token}`,
        });

      const assertions = (resp) => {
        expect(resp.status, 'Status should be 200').to.equal(200);
      };

      await retryRequest(req, assertions);
    });

    it('should proxy a request with correct secrets in request header', async function () {
      const req = () =>
        axios({
          method: 'get',
          url: `${proxyUrl}${path}`,
          headers: {
            access_token: credentials.access_token,
            secret_token: credentials.secret_token,
          },
        });

      const assertions = (resp) => {
        expect(resp.status, 'Status should be 200').to.equal(200);
      };

      await retryRequest(req, assertions);
    });

    it('should not proxy a request with incorrect secrets in request header', async function () {
      const resp = await getNegative(`${proxyUrl}${path}`, {
        // vault-auth plugin cache authentication results by access_token
        // make sure to use a different access_token in this request
        access_token: '11XYyybbu3Ty0Qt4ImIshPGQ0WsvjLzx',
        secret_token: credentials.secret_token,
      });
      logResponse(resp);

      expect(resp.status, 'Status should be 401').to.equal(401);
      expect(resp.data.message, 'should have correct error message').to.eq(
        'Unauthorized'
      );
    });

    it('should GET access/secret credentials when they exist', async function () {
      const resp = await axios(`${url}/vault-auth/kong-auth/credentials`);
      logResponse(resp);

      expect(resp.status, 'Status should be 200').to.equal(200);
      expect(resp.data.data.access_token, 'should see access_token in response')
        .to.be.string;
      expect(resp.data.data.secret_token, 'should see secret_token in response')
        .to.be.string;
    });

    it('should delete access/secret token pair', async function () {
      const resp = await axios({
        method: 'delete',
        url: `${url}/vault-auth/${vaultName}/credentials/token/${credentials.access_token}`,
      });
      logResponse(resp);

      expect(resp.status, 'Status should be 204').to.equal(204);

      await wait(islocalDB ? waitTime : longWaitTime); // eslint-disable-line no-restricted-syntax
    });

    it('should not see access/secret credentials when they have been deleted', async function () {
      const resp = await getNegative(`${url}/vault-auth/kong-auth/credentials`);
      logResponse(resp);

      if (kvVersion === 'v1') {
        expect(resp.status, 'Status should be 404').to.equal(404);
      } else {
        expect(resp.status, 'Status should be 200').to.equal(200);
        expect(
          resp.data.data,
          'Should not see access/secret token after deletion'
        ).to.be.empty;
      }
    });

    it('should not proxy a request after secrets have been deleted', async function () {
      await waitForCacheInvalidation(`vault-auth:${credentials.access_token}:${vaultEntityId}`, 8000)

      const resp = await getNegative(
        `${proxyUrl}${path}?access_token=${credentials.access_token}&secret_token=${credentials.secret_token}`
      );
      logResponse(resp);

      expect(resp.status, 'Status should be 401').to.equal(401);
      expect(resp.data.message, 'should have correct error message').to.eq(
        'Unauthorized'
      );
    });

    it('should proxy a request with secrets created directly in HCV', async function () {
      await createHcvVaultSecrets(
        {
          ...customCredentials,
          consumer: {
            id: consumerId,
          },
        },
        'kong-auth',
        customCredentials.access_token
      );

      const resp = await axios({
        method: 'get',
        url: `${proxyUrl}${path}`,
        headers: {
          access_token: customCredentials.access_token,
          secret_token: customCredentials.secret_token,
        },
      });
      logResponse(resp);

      expect(resp.status, 'Status should be 200').to.equal(200);
      expect(
        resp.data.headers['Secret-Token'],
        'should see secret token sent to upstream'
      ).to.equal(customCredentials.secret_token);
    });

    it('should patch the plugin and hide credentials from upstream', async function () {
      const resp = await axios({
        method: 'patch',
        url: `${url}/plugins/${vaPluginId}`,
        data: {
          config: {
            hide_credentials: true,
          },
        },
      });
      logResponse(resp);

      expect(resp.status, 'Status should be 200').to.equal(200);
      expect(
        resp.data.config.hide_credentials,
        'should see hide_credentials enabled'
      ).to.be.true;

      const req = () =>
        axios({
          method: 'get',
          url: `${proxyUrl}${path}`,
          headers: {
            access_token: customCredentials.access_token,
            secret_token: customCredentials.secret_token,
          },
        });

      const assertions = (resp) => {
        expect(resp.status, 'Status should be 200').to.equal(200);
        expect(
          resp.data.headers,
          'should hide secret token from upstream'
        ).to.not.haveOwnProperty('Secret-Token');
        expect(
          resp.data.headers,
          'should hide access token from upstream'
        ).to.not.haveOwnProperty('Access-Token');
      };

      await retryRequest(req, assertions);
    });

    it('should read tokens from request body', async function () {
      let resp = await axios({
        method: 'patch',
        url: `${url}/plugins/${vaPluginId}`,
        data: {
          config: {
            tokens_in_body: true,
          },
        },
      });
      logResponse(resp);

      expect(resp.status, 'Status should be 200').to.equal(200);
      expect(
        resp.data.config.tokens_in_body,
        'should see tokens_in_body enabled'
      ).to.be.true;

      await wait(islocalDB ? waitTime : longWaitTime); // eslint-disable-line no-restricted-syntax

      resp = await axios({
        method: 'get',
        url: `${proxyUrl}${path}`,
        data: {
          access_token: customCredentials.access_token,
          secret_token: customCredentials.secret_token,
        },
      });
      logResponse(resp);

      expect(resp.status, 'Status should be 200').to.equal(200);
    });

    it('should proxy the request with token pair in request body and hide_credentials true', async function () {
      const resp = await axios({
        method: 'get',
        url: `${proxyUrl}${path}`,
        data: {
          access_token: customCredentials.access_token,
          secret_token: customCredentials.secret_token,
        },
      });
      logResponse(resp);

      expect(resp.status, 'Status should be 200').to.equal(200);
    });

    it('should read new token name from request body', async function () {
      let resp = await axios({
        method: 'patch',
        url: `${url}/plugins/${vaPluginId}`,
        data: {
          config: {
            hide_credentials: false,
            access_token_name: 'test',
            secret_token_name: 'foo',
          },
        },
      });
      logResponse(resp);

      expect(resp.status, 'Status should be 200').to.equal(200);
      expect(
        resp.data.config.access_token_name,
        'should see updated access_token_name'
      ).to.eq('test');

      await wait(islocalDB ? waitTime : longWaitTime); // eslint-disable-line no-restricted-syntax

      resp = await axios({
        method: 'get',
        url: `${proxyUrl}${path}`,
        data: {
          test: customCredentials.access_token,
          foo: customCredentials.secret_token,
        },
      });
      logResponse(resp);

      expect(resp.status, 'Status should be 200').to.equal(200);
    });

    it('should fail to send request as ttl is reached and secret was updated in hcv', async function () {
      // updating secret_token in hcv vault while still using the old one in request to make sure ttl works
      await createHcvVaultSecrets(
        {
          ...customCredentials,
          secret_token: 'updated',
          consumer: {
            id: consumerId,
          },
        },
        'kong-auth',
        customCredentials.access_token
      );

      // wait for ttl to expire which is 1 second
      await wait(2000); // eslint-disable-line no-restricted-syntax

      const resp = await getNegative(
        `${proxyUrl}${path}`,
        {},
        {
          test: customCredentials.access_token,
          foo: customCredentials.secret_token,
        }
      );
      logResponse(resp);

      expect(resp.status, 'Status should be 401').to.equal(401);
      expect(resp.data.message, 'should have correct error text').to.equal(
        'Invalid secret token'
      );
    });

    it('should not proxy the request with wrong vault id in plugin', async function () {
      let resp = await axios({
        method: 'patch',
        url: `${url}/plugins/${vaPluginId}`,
        data: {
          config: {
            access_token_name: 'access_token',
            secret_token_name: 'secret_token',
            tokens_in_body: false,
            vault: {
              id: '3f840fe4-583b-4747-8a90-adec2e2bbb22',
            },
          },
        },
      });
      logResponse(resp);

      expect(resp.status, 'Status should be 200').to.equal(200);
      expect(resp.data.config.vault.id, 'should see updated vault id').to.eq(
        '3f840fe4-583b-4747-8a90-adec2e2bbb22'
      );

      await wait(islocalDB ? waitTime : longWaitTime); // eslint-disable-line no-restricted-syntax

      resp = await getNegative(
        `${proxyUrl}${path}?access_token=${customCredentials.access_token}&secret_token=${customCredentials.secret_token}`
      );
      logResponse(resp);
      expect(resp.status, 'Status should be 500').to.equal(500);
    });

    after(async function () {
      await deleteVaultAuthPluginVaultEntity();
      await deleteHcvSecretMount(vaultName);
      await deleteGatewayRoute(routeId);
      await deleteGatewayService(serviceId);
      await deleteConsumer(consumerId);
    });
  });
});
