import { authDetails } from '@fixtures';
import {
  createEncryptedKeysForJweDecryptPlugin,
  createGatewayService,
  createKeySetsForJweDecryptPlugin,
  createRouteForService,
  deleteEncryptedKeysForJweDecryptPlugin,
  deleteGatewayRoute,
  deleteGatewayService,
  deleteKeySetsForJweDecryptPlugin,
  Environment,
  eventually,
  expect,
  getBasePath,
  getNegative,
  logResponse,
  postNegative,
  waitForConfigRebuild,
} from '@support';
import axios from 'axios';

describe('Gateway Plugins: jwe-decrypt JWK', function () {
  const jwkPath = '/jwedecryptjwk';
  const serviceName = 'jwe-decrypt-service';
  const jwkKeySetsName = 'jwk-key-sets';
  const invalidTokenHeaders = {
    Authorization: `${authDetails.jwe['invalid-token']}`,
  };
  const validTokenHeaders = {
    Authorization: authDetails.jwe['valid-token'],
  };

  let serviceId: string;
  let jwkRouteId: string;
  let jwkKeySetsId: string;
  let keysId: string;

  const url = `${getBasePath({
    environment: Environment.gateway.admin,
  })}`;
  const proxyUrl = `${getBasePath({
    environment: Environment.gateway.proxy,
  })}`;

  let basePayload: any;
  let pluginId: string;

  const jwkKeys = {
    name: 'jwk_key',
    set: { name: jwkKeySetsName },
    jwk: authDetails.jwe.jwk,
    kid: '42',
  };

  before(async function () {
    const service = await createGatewayService(serviceName);
    serviceId = service.id;
    const routeJwk = await createRouteForService(serviceId, [jwkPath]);
    jwkRouteId = routeJwk.id;
    const jwkKeySets = await createKeySetsForJweDecryptPlugin(jwkKeySetsName);
    jwkKeySetsId = jwkKeySets.id;
    await createEncryptedKeysForJweDecryptPlugin(jwkKeys);

    basePayload = {
      name: 'jwe-decrypt',
      service: {
        id: serviceId,
      },
      route: {
        id: jwkRouteId,
      },
    };
  });

  it('JWK: should not create jwe-decrypt plugin when config.key_sets is not supplied', async function () {
    const pluginPayload = {
      ...basePayload,
      config: {},
    };
    const resp = await postNegative(`${url}/plugins`, pluginPayload);
    logResponse(resp);

    expect(resp.status, 'Status should be 400').to.equal(400);
    expect(resp.data.name, 'Should indicate schema violation').to.equal(
      'schema violation'
    );
    expect(
      resp.data.fields.config.key_sets,
      'Should indicate key-sets is a required field'
    ).to.equal('required field missing');
  });

  it('JWK: should enable jwt-decrypt plugin with valid jwk config', async function () {
    const pluginPayload = {
      ...basePayload,
      config: { key_sets: [jwkKeySetsName] },
    };

    const resp = await axios({
      method: 'post',
      url: `${url}/plugins`,
      data: pluginPayload,
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 201').to.equal(201);
    expect(resp.data.config.key_sets[0], 'Should list key-sets').to.equal(
      jwkKeySetsName
    );

    pluginId = resp.data.id;

    await waitForConfigRebuild();
  });

  it('JWK: should not proxy request without a token', async function () {
    await eventually(async () => {
      const resp = await getNegative(`${proxyUrl}${jwkPath}`);
      logResponse(resp);
  
      expect(resp.status, 'Status should be 403').to.equal(403);
      expect(resp.data.message, 'Should indicate token missing').to.equal(
        'could not find token'
      );
    });
  });

  it('JWK: should not proxy request with invalid token', async function () {
    console.log(invalidTokenHeaders, validTokenHeaders);
    const resp = await getNegative(
      `${proxyUrl}${jwkPath}`,
      invalidTokenHeaders
    );
    logResponse(resp);

    expect(resp.status, 'Status should be 403').to.equal(403);

    expect(
      resp.data.message,
      'Should indicate token cannot be decrypted'
    ).to.equal('failed to decrypt token');
  });

  //skipped until https://konghq.atlassian.net/browse/KAG-390 is fixed
  xit('JWK: should proxy request with valid token', async function () {
    const resp = await getNegative(`${proxyUrl}${jwkPath}`, validTokenHeaders);
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
  });


  it('JWK: should patch jwe-decrypt plugin to disable auth and allow requests', async function () {
    const resp = await axios({
      method: 'patch',
      url: `${url}/plugins/${pluginId}`,
      data: {
        config: {
          strict: false,
        },
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);

    await waitForConfigRebuild();
  });

  it('JWK: should proxy request without supplying a token', async function () {
    await eventually(async () => {
      const resp = await axios({
        url: `${proxyUrl}${jwkPath}`,
      });
      logResponse(resp);
  
      expect(resp.status, 'Status should be 200').to.equal(200);
    });
  });

  it('should delete the jwe-decrypt plugin', async function () {
    const resp = await axios({
      method: 'delete',
      url: `${url}/plugins/${pluginId}`,
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 204').to.equal(204);
  });

  after(async function () {
    await deleteGatewayRoute(jwkRouteId);
    await deleteGatewayService(serviceId);
    await deleteEncryptedKeysForJweDecryptPlugin(keysId);
    await deleteKeySetsForJweDecryptPlugin(jwkKeySetsId);
  });
});
