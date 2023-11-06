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
  expect,
  getBasePath,
  getNegative,
  logResponse,
  postNegative,
  waitForConfigRebuild,
} from '@support';
import axios from 'axios';

describe('Gateway Plugins: jwe-decrypt PEM', function () {
  const pemPath = '/jwedecryptpem';
  const serviceName = 'jwe-decrypt-service';
  const pemKeySetsName = 'pem-key-sets';
  const invalidTokenHeaders = {
    Authorization: `${authDetails.jwe['invalid-token']}`,
  };
  const validTokenHeaders = {
    Authorization: authDetails.jwe['valid-token'],
  };
  const expiredTokenHeaders = {
    Authorization: `${authDetails.expired_token}`,
  };

  let serviceId: string;
  let pemRouteId: string;
  let pemKeySetsId: string;
  let keysId: string;

  const url = `${getBasePath({
    environment: Environment.gateway.admin,
  })}`;
  const proxyUrl = `${getBasePath({
    environment: Environment.gateway.proxy,
  })}`;

  let basePayload: any;
  let pluginId: string;
  const pemKeys = {
    name: 'pem_key',
    set: { name: pemKeySetsName },
    pem: {
      public_key: authDetails.jwe.public,
      private_key: authDetails.jwe.private,
    },
    kid: '42',
  };

  before(async function () {
    const service = await createGatewayService(serviceName);
    serviceId = service.id;
    const routePem = await createRouteForService(serviceId, [pemPath]);
    pemRouteId = routePem.id;
    const pemKeySets = await createKeySetsForJweDecryptPlugin(pemKeySetsName);
    pemKeySetsId = pemKeySets.id;
    await createEncryptedKeysForJweDecryptPlugin(pemKeys);

    basePayload = {
      name: 'jwe-decrypt',
      service: {
        id: serviceId,
      },
      route: {
        id: pemRouteId,
      },
    };
  });

  it('PEM: should not create jwe-decrypt plugin when config.key_sets is not supplied', async function () {
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

  it('PEM: should enable jwt-decrypt plugin with valid pem config on a service', async function () {
    const pluginPayload = {
      ...basePayload,
      config: { key_sets: [pemKeySetsName] },
    };

    const resp = await axios({
      method: 'post',
      url: `${url}/plugins`,
      data: pluginPayload,
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 201').to.equal(201);
    expect(resp.data.config.key_sets[0], 'Should list key-sets').to.equal(
      pemKeySetsName
    );

    pluginId = resp.data.id;
    await waitForConfigRebuild();
  });

  it('PEM: should not proxy request without a token', async function () {
    const resp = await getNegative(`${proxyUrl}${pemPath}`);
    logResponse(resp);

    expect(resp.status, 'Status should be 403').to.equal(403);

    expect(resp.data.message, 'Should indicate token missing').to.equal(
      'could not find token'
    );
  });

  it('PEM: should not proxy request with invalid token', async function () {
    console.log(invalidTokenHeaders, validTokenHeaders);
    const resp = await getNegative(
      `${proxyUrl}${pemPath}`,
      invalidTokenHeaders
    );
    logResponse(resp);

    expect(resp.status, 'Status should be 403').to.equal(403);

    expect(
      resp.data.message,
      'Should indicate token cannot be decrypted'
    ).to.equal('failed to decrypt token');
  });

  it('PEM: should proxy request with valid token', async function () {
    const resp = await getNegative(`${proxyUrl}${pemPath}`, validTokenHeaders);
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
  });

  it('PEM: should patch jwe-decrypt plugin to disable auth and allow requests', async function () {
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

  it('PEM: should proxy request without supplying a token', async function () {
    const resp = await axios({
      url: `${proxyUrl}${pemPath}`,
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
  });

  it('PEM: should delete the jwe-decrypt plugin', async function () {
    const resp = await axios({
      method: 'delete',
      url: `${url}/plugins/${pluginId}`,
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 204').to.equal(204);
  });

  after(async function () {
    await deleteGatewayRoute(pemRouteId);
    await deleteGatewayService(serviceId);
    await deleteEncryptedKeysForJweDecryptPlugin(keysId);
    await deleteKeySetsForJweDecryptPlugin(pemKeySetsId);
  });
});
