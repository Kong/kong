import axios from 'axios';
import {
  expect,
  Environment,
  getBasePath,
  createGatewayService,
  deleteGatewayService,
  randomString,
  deleteGatewayRoute,
  createRouteForService,
  logResponse,
  isGwHybrid,
  waitForConfigRebuild,
  wait,
  postNegative,
} from '@support';

describe('Gateway Plugins: CORS', function () {
  const url = `${getBasePath({
    environment: Environment.gateway.admin,
  })}/plugins`;
  const proxyUrl = `${getBasePath({
    environment: Environment.gateway.proxy,
  })}`;
  const isHybrid = isGwHybrid();
  const waitTime = 5000;
  const hybridWaitTime = 7000;
  const path = `/${randomString()}`;
  let serviceId: string;
  let routeId: string;
  let pluginId: string;
  let basePayload: any;

  before(async function () {
    const service = await createGatewayService(randomString());
    serviceId = service.id;
    const route = await createRouteForService(serviceId, [path]);
    routeId = route.id;
  });

  it('should not create the CORS plugin with incorrect config', async function () {
    basePayload = {
      name: 'cors',
      service: {
        id: serviceId,
      },
      route: {
        id: routeId,
      },
    };
    const payload = {
      ...basePayload,
      config: {
        origins: ['https://example.com'],
        methods: ['FAKEMETHOD'],
      },
    };

    const resp = await postNegative(url, payload);
    logResponse(resp);
    expect(resp.status).to.equal(400);
    expect(resp.data.message).to.contain(
      'expected one of: GET, HEAD, PUT, PATCH, POST, DELETE, OPTIONS, TRACE, CONNECT'
    );
  });

  it('should create CORS plugin with valid config and default values', async function () {
    const payload = {
      ...basePayload,
      config: {
        origins: ['https://example.com'],
      },
    };

    const resp = await axios.post(url, payload);
    logResponse(resp);
    expect(resp.status).to.equal(201);
    pluginId = resp.data.id;

    await waitForConfigRebuild();
  });

  it('should send request with appropriate CORS headers', async function () {
    const resp = await axios({
      url: `${proxyUrl}${path}`,
      method: 'OPTIONS',
      headers: {
        Origin: 'https://example.com',
        'access-control-request-method': 'OPTIONS',
      },
    });
    logResponse(resp);
    expect(resp.status).to.equal(200);
    expect(resp.headers['access-control-allow-origin']).to.equal(
      'https://example.com'
    );
    expect(resp.headers).to.not.have.key('access-control-allow-credentials');
  });

  it('should set and send CORS Access-Control-Allow-Headers and Access-Control-Expose-Headers', async function () {
    const payload = {
      ...basePayload,
      config: {
        origins: ['https://example.com'],
        headers: ['x-public-header', 'x-private-header'],
        exposed_headers: ['x-public-header'],
      },
    };

    const resp = await axios({
      url: `${url}/${pluginId}`,
      method: 'PATCH',
      data: payload,
    });

    logResponse(resp);
    expect(resp.status).to.equal(200);
    expect(resp.data.config.headers)
      .to.contain('x-public-header')
      .and.contain('x-private-header');
    expect(resp.data.config.exposed_headers).to.contain('x-public-header');

    await waitForConfigRebuild();

    const proxyResp = await axios({
      url: `${proxyUrl}${path}`,
      method: 'OPTIONS',
      headers: {
        Origin: 'https://example.com',
        'access-control-request-method': 'OPTIONS',
      },
    });

    logResponse(proxyResp);
    expect(proxyResp.status).to.equal(200);
    expect(proxyResp.headers['access-control-allow-origin']).to.equal(
      'https://example.com'
    );
    expect(proxyResp.headers['access-control-allow-headers'])
      .to.contain('x-public-header')
      .and.contain('x-private-header');

    const proxyResp2 = await axios({
      url: `${proxyUrl}${path}`,
      method: 'GET',
      headers: {
        Origin: 'https://example.com',
      },
    });

    logResponse(proxyResp2);
    expect(proxyResp2.status).to.equal(200);
    expect(proxyResp2.headers['access-control-allow-origin']).to.equal(
      'https://example.com'
    );
    expect(proxyResp2.headers['access-control-expose-headers']).to.equal(
      'x-public-header'
    );
  });

  it('should toggle CORS Access-Control-Allow-Credentials header', async function () {
    const payload = {
      ...basePayload,
      config: {
        origins: ['https://example.com'],
        credentials: true,
      },
    };

    const resp = await axios({
      url: `${url}/${pluginId}`,
      method: 'PATCH',
      data: payload,
    });

    logResponse(resp);
    expect(resp.status).to.equal(200);
    expect(resp.data.config.credentials).to.equal(true);

    await waitForConfigRebuild();

    const proxyResp = await axios({
      url: `${proxyUrl}${path}`,
      method: 'OPTIONS',
      headers: {
        Origin: 'https://example.com',
        'access-control-request-method': 'OPTIONS',
      },
    });

    logResponse(proxyResp);
    expect(proxyResp.status).to.equal(200);
    expect(proxyResp.headers['access-control-allow-origin']).to.equal(
      'https://example.com'
    );
    expect(proxyResp.headers['access-control-allow-credentials']).to.equal(
      'true'
    );

    const payload2 = {
      ...basePayload,
      config: {
        origins: ['https://example.com'],
        credentials: false,
      },
    };

    const resp2 = await axios({
      url: `${url}/${pluginId}`,
      method: 'PATCH',
      data: payload2,
    });

    logResponse(resp2);
    expect(resp2.status).to.equal(200);
    expect(resp2.data.config.credentials).to.equal(false);

    await waitForConfigRebuild();

    const proxyResp2 = await axios({
      url: `${proxyUrl}${path}`,
      method: 'OPTIONS',
      headers: {
        Origin: 'https://example.com',
        'access-control-request-method': 'OPTIONS',
      },
    });

    logResponse(proxyResp2);
    expect(proxyResp2.status).to.equal(200);
    expect(proxyResp2.headers['access-control-allow-origin']).to.equal(
      'https://example.com'
    );
    expect(proxyResp2.headers).to.not.have.key(
      'access-control-allow-credentials'
    );
  });

  it('should set and send CORS access-control-max-age header', async function () {
    const payload = {
      ...basePayload,
      config: {
        origins: ['https://example.com'],
        max_age: 999,
      },
    };
    const resp = await axios({
      url: `${url}/${pluginId}`,
      method: 'PATCH',
      data: payload,
    });

    logResponse(resp);
    expect(resp.status).to.equal(200);

    await waitForConfigRebuild();

    const proxyResp = await axios({
      url: `${proxyUrl}${path}`,
      method: 'OPTIONS',
      headers: {
        Origin: 'https://example.com',
        'access-control-request-method': 'OPTIONS',
      },
    });

    logResponse(proxyResp);
    expect(proxyResp.status).to.equal(200);
    expect(proxyResp.headers['access-control-allow-origin']).to.equal(
      'https://example.com'
    );
    expect(proxyResp.headers['access-control-max-age']).to.equal('999');
  });

  after(async function () {
    await deleteGatewayRoute(routeId);
    await deleteGatewayService(serviceId);
  });
});
