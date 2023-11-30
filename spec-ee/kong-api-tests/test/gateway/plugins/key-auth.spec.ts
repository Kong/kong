import { checkKonnectCpAndDpConfigHashMatch } from '@shared/konnect_workflows';
import {
  createConsumer,
  createGatewayService,
  createRouteForService,
  Environment,
  expect,
  getBasePath,
  getNegative,
  logResponse,
  clearAllKongResources,
  isGateway,
  isKoko,
  waitForConfigRebuild,
  retryRequest,
  getKonnectControlPlaneId,
} from '@support';
import axios from 'axios';

describe('@smoke: Gateway Plugins: key-auth', function () {
  const path = '/key-auth';
  const serviceName = 'key-auth-service';
  const consumerName = 'bill';
  const key = 'api_key';
  const keyAuthPayload = { tags: ['tag2'], ttl: 10 };
  const keyAuthPayloadKonnect = { tags: ['tag2']};
  const plugin = 'key-auth';

  const inValidTokenHeaders = {
    api_key: 'ZnBckx2rSLCccbnCKRp3BEqzYbyRYTAX',
  };

  let url: string
  let proxyUrl: string
  let serviceId: string;
  let routeId: string;
  let keyId: string;
  let basePayload: any;
  let pluginId: string;
  let consumerId: string

  before(async function () {
    url = `${getBasePath({
      environment: isGateway() ? Environment.gateway.admin : undefined,
    })}`;
    proxyUrl = `${getBasePath({
      app: 'gateway',
      environment: Environment.gateway.proxy,
    })}`;

    await clearAllKongResources();
    const service = await createGatewayService(serviceName);
    serviceId = service.id;
    const route = await createRouteForService(serviceId, [path]);
    routeId = route.id;
    const consumer = await createConsumer(consumerName);
    consumerId = consumer.id
    await waitForConfigRebuild()
    
    basePayload = {
      name: plugin,
      service: {
        id: serviceId,
      },
      route: {
        id: routeId,
      },
    };
  });

  it('should proxy request without supplying apiKey', async function () {
    const resp = await getNegative(`${proxyUrl}${path}`);
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
  });

  it('should enable key-auth plugin with apiKey in header', async function () {
    const pluginPayload = {
      ...basePayload,
      config: { key_names: [key] },
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
    await waitForConfigRebuild()
  });

  it('should create key and add tag using consumer under-test', async function () {
    // *** KOKO DOES NOT ALLOW SETTING TTL VALUE AND USING CONSUMER NAME ***
    const resp = await axios({
      method: 'post',
      url: `${url}/consumers/${isKoko() ? consumerId : consumerName}/${plugin}`,
      data: isKoko() ? keyAuthPayloadKonnect : keyAuthPayload,
    });

    expect(resp.status, 'Status should be 201').to.equal(201);
    expect(resp.data.tags, 'Should contain tags').to.contain('tag2');
    if(isGateway()) {
      expect(resp.data.ttl, 'Should contain ttl value').to.be.a('number');
    }

    keyId = resp.data.key;
    await waitForConfigRebuild()
  });

  it('should not proxy request without supplying apiKey', async function () {
    const resp = await getNegative(`${proxyUrl}${path}`);
    logResponse(resp);

    expect(resp.status, 'Status should be 401').to.equal(401);
    expect(resp.data.message, 'Should indicate no api key found').to.equal(
      'No API key found in request'
    );
  });

  it('should not proxy request with invalid apiKey', async function () {
    const resp = await getNegative(`${proxyUrl}${path}`, inValidTokenHeaders);
    logResponse(resp);

    expect(resp.status, 'Status should be 401').to.equal(401);
    expect(resp.data.message, 'Should indicate invalid credentials').to.equal(
      'Unauthorized'
    );
  });

  it('should proxy request with apiKey in header', async function () {
    const validTokenHeaders = {
      api_key: keyId,
    };
    const resp = await getNegative(`${proxyUrl}${path}`, validTokenHeaders);
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
  });

  it('should proxy request with apiKey in query param', async function () {
    const queryUrl = `${proxyUrl}${path}?api_key=${keyId}`;

    const resp = await axios({
      method: 'get',
      url: `${queryUrl}`,
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
  });

  if(isGateway()) {
    // This test case captures:
    // https://konghq.atlassian.net/browse/FTI-4512
    it('should not proxy request with apiKey in header after ttl expiration', async function () {
      await waitForConfigRebuild()

      const validTokenHeaders = {
        api_key: keyId,
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
    it('should not proxy request with apiKey in query param after ttl expiration', async function () {
      const queryUrl = `${proxyUrl}${path}?api_key=${keyId}`;

      const resp = await getNegative(`${queryUrl}`);
      logResponse(resp);

      expect(resp.status, 'Status should be 401').to.equal(401);
      expect(resp.data.message, 'Should indicate invalid credentials').to.equal(
        'Unauthorized'
      );
    });
  }

  it('should update key-auth plugin to disable auth and allow requests', async function () {
    // *** KOKO DOES NOT PATCH PLUGIN ***
    const resp = await axios({
      method: isKoko() ? 'put' : 'patch',
      url: `${url}/plugins/${pluginId}`,
      data: {
        name: 'key-auth',
        enabled: false,
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.enabled, 'Should be false').to.be.false;

    if(isKoko()) {
      await checkKonnectCpAndDpConfigHashMatch(getKonnectControlPlaneId())
    }
  });

  it('should proxy request without supplying apiKey after disabling plugin', async function () {
    const req = () => getNegative(`${proxyUrl}${path}`);

    const assertionsSuccess = (resp) => {
      logResponse(resp)
      expect(resp.status, 'Status should be 200').to.equal(200);
    }

    await retryRequest(req, assertionsSuccess)
  });

  it('should delete the key-auth plugin', async function () {
    const resp = await axios({
      method: 'delete',
      url: `${url}/plugins/${pluginId}`,
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 204').to.equal(204);
  });

  after(async function () {
    await clearAllKongResources()
  });
});
