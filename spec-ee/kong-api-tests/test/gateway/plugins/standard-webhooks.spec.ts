import axios from 'axios';
import {
  expect,
  Environment,
  getBasePath,
  createGatewayService,
  deleteGatewayService,
  createRouteForService,
  deleteGatewayRoute,
  logResponse,
  isGateway,
  waitForConfigRebuild,
  postNegative,
  signWebhook,
  eventually
} from '@support';

describe('@oss: Gateway Plugins: standard webhooks', function () {
  this.timeout(50000)
  const path = '/wh';
  const serviceName = 'webhook-service';
  const webhookSecret = 'webhook_secret';
  const webhookPayload = {foo: 'bar'}
  const webhookId = 'test'
  const webhookDefaultTolerance = 300

  const url = `${getBasePath({
    environment: isGateway() ? Environment.gateway.admin : undefined,
  })}/plugins`;
  const proxyUrl = `${getBasePath({
    app: 'gateway',
    environment: Environment.gateway.proxy,
  })}`;

  let webhookTimestamp = Math.floor(Date.now() / 1000);
  let signature = signWebhook(webhookSecret, webhookPayload, webhookId, webhookTimestamp)
  let serviceId: string;
  let routeId: string;
  let basePayload: any;
  let pluginId: string;


  before(async function () {
    const service = await createGatewayService(serviceName);
    serviceId = service.id;
    const route = await createRouteForService(serviceId, [path]);
    routeId = route.id;

    basePayload = {
      name: 'standard-webhooks',
      service: {
        id: serviceId,
      },
      route: {
        id: routeId,
      },
    };
  });

  it('should not create standard-webhook plugin with decimal point tolerance', async function () {
    const pluginPayload = {
      ...basePayload,
      config: {
        tolerance_second: 15.6,
        secret_v1: webhookSecret
      },
    };

    const resp = await postNegative(url, pluginPayload);
    logResponse(resp);

    expect(resp.status, 'Status should be 400').to.equal(400);
    expect(resp.data.message, 'Should have correct error message').to.contain(
      `schema violation (config.tolerance_second: expected an integer)`
    );
  });

  it('should not create standard-webhook plugin without v1 secret', async function () {
    const pluginPayload = {
      ...basePayload,
      config: {
        tolerance_second: 15
      },
    };

    const resp = await postNegative(url, pluginPayload);
    logResponse(resp);

    expect(resp.status, 'Status should be 400').to.equal(400);
    expect(resp.data.message, 'Should have correct error message').to.contain(
      `schema violation (config.secret_v1: required field missing)`
    );
  });

  it('should create standard-webhook plugin with default parameters', async function () {
    const pluginPayload = {
      ...basePayload,
      config: {
        tolerance_second: webhookDefaultTolerance,
        secret_v1: webhookSecret
      },
    };

    const resp = await axios({ method: 'post', url, data: pluginPayload });
    logResponse(resp);

    expect(resp.status, 'Status should be 201').to.equal(201);
    expect(resp.data.config.tolerance_second, 'Should see correct tolerance').to.equal(webhookDefaultTolerance)
    expect(resp.data.config.secret_v1, 'Should see correct webhook secret').to.equal(webhookSecret)

    pluginId = resp.data.id;
    await waitForConfigRebuild();
  });

  it('should not proxy with wrong webhook signature', async function () {
    const resp = await postNegative(`${proxyUrl}${path}`, webhookPayload, 'post', {
      'webhook-signature': 'wrongSignature',
      'webhook-timestamp': webhookTimestamp,
      'webhook-id': webhookId
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 400').to.equal(400);
  });

  it('should not proxy with missing webhook signature', async function () {
    const resp = await postNegative(`${proxyUrl}${path}`, webhookPayload, 'post', {
      'webhook-timestamp': webhookTimestamp,
      'webhook-id': webhookId
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 400').to.equal(400);
  });

  it('should not proxy with wrong webhook id', async function () {
    const resp = await postNegative(`${proxyUrl}${path}`, webhookPayload, 'post', {
      'webhook-signature': signature,
      'webhook-timestamp': webhookTimestamp,
      'webhook-id': 'wrongId'
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 400').to.equal(400);
  });

  it('should not proxy with missing webhook id', async function () {
    const resp = await postNegative(`${proxyUrl}${path}`, webhookPayload, 'post', {
      'webhook-signature': signature,
      'webhook-timestamp': webhookTimestamp
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 400').to.equal(400);
  });

  it('should not proxy with missing webhook timestamp', async function () {
    const resp = await postNegative(`${proxyUrl}${path}`, webhookPayload, 'post', {
      'webhook-signature': signature,
      'webhook-id': webhookId
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 400').to.equal(400);
  });

  it('should proxy with correct webhook signature', async function () {
    await eventually(async () => {
      // need signature and timestamp here to update every time retry happens
      webhookTimestamp = Math.floor(Date.now() / 1000)
      signature = signWebhook(webhookSecret, webhookPayload, webhookId, webhookTimestamp)
      const resp = await postNegative(`${proxyUrl}${path}`, webhookPayload, 'post', {
        'webhook-signature': signature,
        'webhook-timestamp': webhookTimestamp,
        'webhook-id': webhookId
      });

      logResponse(resp);
      expect(resp.status, 'Status should be 200').to.equal(200);
    });
  });

  it('should not proxy when using different secret in webhook signature', async function () {
    const signature = signWebhook('differentSecret', webhookPayload, webhookId, webhookTimestamp)

    const resp = await postNegative(`${proxyUrl}${path}`, webhookPayload, 'post', {
      'webhook-signature': signature,
      'webhook-timestamp': webhookTimestamp,
      'webhook-id': webhookId
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 400').to.equal(400);
  });

  it('should not proxy with expired webhook timestamp', async function () {
    const expiredTimestamp = webhookTimestamp - 5000
    const signature = signWebhook('differentSecret', webhookPayload, webhookId, expiredTimestamp)

    const resp = await postNegative(`${proxyUrl}${path}`, webhookPayload, 'post', {
      'webhook-signature': signature,
      'webhook-timestamp': expiredTimestamp,
      'webhook-id': webhookId
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 400').to.equal(400);
  });

  it('should not proxy with webhook future timestamp', async function () {
    const expiredTimestamp = webhookTimestamp + 5000
    const signature = signWebhook('differentSecret', webhookPayload, webhookId, expiredTimestamp)

    const resp = await postNegative(`${proxyUrl}${path}`, webhookPayload, 'post', {
      'webhook-signature': signature,
      'webhook-timestamp': expiredTimestamp,
      'webhook-id': webhookId
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 400').to.equal(400);
  });

  it('should not proxy with webhook invalid timestamp', async function () {
    const invalidTimestamp = Math.floor(Date.now());
    const signature = signWebhook('differentSecret', webhookPayload, webhookId, invalidTimestamp)

    const resp = await postNegative(`${proxyUrl}${path}`, webhookPayload, 'post', {
      'webhook-signature': signature,
      'webhook-timestamp': invalidTimestamp,
      'webhook-id': webhookId
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 400').to.equal(400);
  });


  it('should not proxy with empty body', async function () {
    const signature = signWebhook('differentSecret', '', webhookId, webhookTimestamp)

    const resp = await postNegative(`${proxyUrl}${path}`, '', 'post', {
      'webhook-signature': signature,
      'webhook-timestamp': webhookTimestamp,
      'webhook-id': webhookId
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 400').to.equal(400);
  });

  it('should patch standard-webhooks plugin tolerance seconds and secret', async function () {
    const resp = await axios({
      method: 'patch',
      url: `${url}/${pluginId}`,
      data: {
        config: {
          tolerance_second: 50,
          secret_v1: 'test'
        },
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.config.tolerance_second, 'Should see the patched tolerance').to.equal(50)
    expect(resp.data.config.secret_v1, 'Should see the patched webhook secret').to.equal('test')

    await waitForConfigRebuild()
  });

  it('should proxy after patching the plugin tolerance and secret', async function () {
    await eventually(async () => {
      // need signature and timestamp here to update every time retry happens
      webhookTimestamp = Math.floor(Date.now() / 1000)
      signature = signWebhook('test', webhookPayload, webhookId, webhookTimestamp)
      const resp = await postNegative(`${proxyUrl}${path}`, webhookPayload, 'post', {
        'webhook-signature': signature,
        'webhook-timestamp': webhookTimestamp,
        'webhook-id': webhookId
      });

      logResponse(resp);
      expect(resp.status, 'Status should be 200').to.equal(200);
    });
  });

  it('should delete the standard-webhooks plugin', async function () {
    const resp = await axios({
      method: 'delete',
      url: `${url}/${pluginId}`,
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 204').to.equal(204);
  });

  after(async function () {
    await deleteGatewayRoute(routeId);
    await deleteGatewayService(serviceId);
  });
});
