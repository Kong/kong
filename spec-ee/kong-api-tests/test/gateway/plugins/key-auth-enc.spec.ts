import {
  createConsumer,
  createGatewayService,
  createRouteForService,
  Environment,
  expect,
  getBasePath,
  getNegative,
  logResponse,
  wait,
  waitForConfigRebuild,
  retryRequest,
  clearAllKongResources,
  isGateway
} from '@support';
import axios from 'axios';

describe('Gateway Plugins: key-auth-enc', function () {
  const path = '/key-auth-enc';
  const serviceName = 'key-auth-enc-service';
  const waitTime = 5000;
  const consumerName = 'ted';
  const key = 'apiKey';
  const tagAndTtlPayload = { tags: ['tag1'], ttl: 10 };
  const plugin = 'key-auth-enc';

  const url = `${getBasePath({
    environment: isGateway() ? Environment.gateway.admin : undefined,
  })}`;
  const proxyUrl = `${getBasePath({
    app: 'gateway',
    environment: Environment.gateway.proxy,
  })}`;
  const inValidTokenHeaders = {
    apiKey: 'ZnBckx2rSLCccbnCKRp3BEqzYbyRYTAX',
  };

  let serviceId: string;
  let routeId: string;
  let keyId: string;
  let basePayload: any;
  let pluginId: string;

  before(async function () {
    await clearAllKongResources();
    const service = await createGatewayService(serviceName);
    serviceId = service.id;
    const route = await createRouteForService(serviceId, [path]);
    routeId = route.id;
    await createConsumer(consumerName);

    basePayload = {
      name: plugin,
      service: {
        id: serviceId,
      },
      route: {
        id: routeId,
      },
    };

    await waitForConfigRebuild();
  });

  it('key-auth-enc: should proxy request without supplying apiKey', async function () {
    const assertions = (resp) => {
      expect(resp.status, 'Status should be 200').to.equal(200);
    };
    const req = () => getNegative(`${proxyUrl}${path}`);
    await retryRequest(req, assertions);
  });

  it('key-auth-enc: should enable key-auth-enc plugin with apiKey in header', async function () {
    const pluginPayload = {
      ...basePayload,
      config: { key_names: ['apiKey'] },
    };

    const resp = await axios({
      method: 'post',
      url: `${url}/plugins`,
      data: pluginPayload,
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 201').to.equal(201);
    expect(resp.data.config.key_in_header, 'Default value is True').to.be.true;
    expect(resp.data.config.key_in_body, 'Default value is False').to.be.false;
    expect(resp.data.config.key_in_query, 'Default value is True').to.be.true;
    expect(resp.data.enabled, 'Should be true').to.be.true;
    expect(resp.data.config.key_names[0], 'Header key is apiKey').to.contain(
      key
    );

    pluginId = resp.data.id;
    await waitForConfigRebuild();
  });

  // This test case captures:
  // https://konghq.atlassian.net/browse/FTI-4084
  // https://konghq.atlassian.net/browse/FTI-4066#icft=FTI-4066
  it('key-auth-enc: should create key and add tag using consumer under-test', async function () {
    const resp = await axios({
      method: 'post',
      url: `${url}/consumers/${consumerName}/${plugin}`,
      data: tagAndTtlPayload,
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 201').to.equal(201);
    expect(resp.data.tags, 'Should contain tags').to.contain('tag1');
    expect(resp.data.ttl, 'Should contain ttl value').to.be.a('number');

    keyId = resp.data.key;
    await wait(waitTime); // eslint-disable-line no-restricted-syntax
  });

  it('key-auth-enc: should not proxy request without supplying apiKey', async function () {
    const resp = await getNegative(`${proxyUrl}${path}`);
    logResponse(resp);

    expect(resp.status, 'Status should be 401').to.equal(401);
    expect(resp.data.message, 'Should indicate no api key found').to.equal(
      'No API key found in request'
    );
  });

  it('key-auth-enc: should not proxy request with invalid apiKey', async function () {
    const resp = await getNegative(`${proxyUrl}${path}`, inValidTokenHeaders);
    logResponse(resp);

    expect(resp.status, 'Status should be 401').to.equal(401);
    expect(resp.data.message, 'Should indicate invalid credentials').to.equal(
      'Unauthorized'
    );
  });

  it('key-auth-enc: should proxy request with apiKey in header', async function () {
    const validTokenHeaders = {
      apiKey: keyId,
    };
    const resp = await getNegative(`${proxyUrl}${path}`, validTokenHeaders);
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
  });

  it('key-auth-enc: should proxy request with apiKey in query param', async function () {
    const queryUrl = `${proxyUrl}${path}?apiKey=${keyId}`;

    const resp = await axios({
      method: 'get',
      url: `${queryUrl}`,
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    await wait(waitTime); // eslint-disable-line no-restricted-syntax
  });

  // This test case captures:
  // https://konghq.atlassian.net/browse/FTI-4512
  it('key-auth-enc: should not proxy request with apiKey in header after ttl expiration', async function () {
    const validTokenHeaders = {
      apiKey: keyId,
    };
    const resp = await getNegative(`${proxyUrl}${path}`, validTokenHeaders);
    logResponse(resp);

    expect(resp.status, 'Status should be 401').to.equal(401);
    expect(resp.data.message, 'Should indicate invalid credentials').to.equal(
      'Unauthorized'
    );
  });

  // This test case captures:
  // https://konghq.atlassian.net/browse/FTI-4512
  it('key-auth-enc: should not proxy request with apiKey in query param after ttl expiration', async function () {
    const queryUrl = `${proxyUrl}${path}?apiKey=${keyId}`;

    const resp = await getNegative(`${queryUrl}`);
    logResponse(resp);

    expect(resp.status, 'Status should be 401').to.equal(401);
    expect(resp.data.message, 'Should indicate invalid credentials').to.equal(
      'Unauthorized'
    );
  });

  it('key-auth-enc: should patch key-auth-enc plugin to disable auth and allow requests', async function () {
    const resp = await axios({
      method: 'patch',
      url: `${url}/plugins/${pluginId}`,
      data: {
        enabled: false,
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.enabled, 'Should be false').to.be.false;
    await waitForConfigRebuild();
  });

  it('key-auth-enc: should proxy request without supplying apiKey after disabling plugin', async function () {
    const resp = await getNegative(`${proxyUrl}${path}`);
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
  });

  it('key-auth-enc: should delete the key-auth-enc plugin', async function () {
    const resp = await axios({
      method: 'delete',
      url: `${url}/plugins/${pluginId}`,
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 204').to.equal(204);
  });

  after(async function () {
    await clearAllKongResources();
  });
});
