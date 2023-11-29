import axios from 'axios';
import {
  expect,
  Environment,
  getBasePath,
  postNegative,
  createGatewayService,
  deleteGatewayService,
  createRouteForService,
  deleteGatewayRoute,
  randomString,
  logResponse,
  getHttpLogServerLogs,
  eventually,
  waitForConfigRebuild,
  deleteHttpLogServerLogs
} from '@support';

describe('Gateway Plugins: http-log', function () {
  const path = `/${randomString()}`;

  let serviceId: string;
  let routeId: string;
  let pluginId: string;
  let basePayload: any;
  let mockbinUrl: string;
  let mockbinLogs: any;

  const url = `${getBasePath({
    environment: Environment.gateway.admin,
  })}/plugins`;
  const proxyUrl = `${getBasePath({
    environment: Environment.gateway.proxy,
  })}`;

  const forbiddenHeaders = ['Host', 'Content-Length', 'Content-Type'];
  const pluginConfigHeaders = ['PUT', 'PATCH'];
  const customHeaderName = 'X-Custom-Myheader';

  before(async function () {
    const service = await createGatewayService(randomString());
    serviceId = service.id;
    const route = await createRouteForService(serviceId, [path]);
    routeId = route.id;
    await deleteHttpLogServerLogs()

    mockbinUrl = 'http://http-log-server:9300/logs';

    basePayload = {
      name: 'http-log',
      service: {
        id: serviceId,
      },
      route: {
        id: routeId,
      },
    };
  });

  it('should not create http-log plugin without config.http_endpoint', async function () {
    const resp = await postNegative(url, basePayload);
    logResponse(resp);

    expect(resp.status, 'Status should be 400').to.equal(400);
    expect(resp.data.message, 'Should have correct error message').to.contain(
      `schema violation (config.http_endpoint: required field missing)`
    );
  });

  it('should not create http-log plugin with both Authorization header and userinfo in URL', async function () {
    const pluginPayload = {
      ...basePayload,
      config: {
        http_endpoint: 'http://hi:there@myservice.com/path',
        // must also validate casing
        headers: { AuthoRIZATion: 'test' },
      },
    };
    const resp = await postNegative(url, pluginPayload);
    logResponse(resp);

    expect(resp.status, 'Status should be 400').to.equal(400);
    expect(resp.data.message, 'Should have correct error message').to.contain(
      `specifying both an 'Authorization' header and user info in 'http_endpoint' is not allowed`
    );
  });

  forbiddenHeaders.forEach((header) => {
    it(`should not create http-log plugin with ${header} header`, async function () {
      const pluginPayload = {
        ...basePayload,
        config: {
          http_endpoint: mockbinUrl,
          headers: { [header]: 'test' },
        },
      };
      const resp = await postNegative(url, pluginPayload);
      logResponse(resp);

      expect(resp.status, 'Status should be 400').to.equal(400);
      expect(resp.data.message, 'Should have correct error message').to.contain(
        `schema violation (config.headers: cannot contain '${header}' header)`
      );
    });
  });

  it('should create http-log plugin with mockbin endpoint', async function () {
    const pluginPayload = {
      ...basePayload,
      config: {
        http_endpoint: mockbinUrl,
      },
    };

    const resp = await axios({ method: 'post', url, data: pluginPayload });
    logResponse(resp);

    expect(resp.status, 'Status should be 201').to.equal(201);
    expect(
      resp.data.config.http_endpoint,
      'Should have correct http_endpoint'
    ).to.eq(mockbinUrl);

    pluginId = resp.data.id;
    await waitForConfigRebuild()
  });

  it('should send http request logs to http_endpoint', async function () {
    const resp = await axios(`${proxyUrl}${path}`);
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);

    await eventually(async () => {
      mockbinLogs = await getHttpLogServerLogs()
      expect(
        mockbinLogs[0].reqMethod,
        'Should use POST method to log request data'
      ).to.eq('POST');
    });
  });

  it('should send http request random header details to http_endpoint', async function () {
    const resp = await axios({
      url: `${proxyUrl}${path}`,
      headers: { test: 'test' },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);

    await eventually(async () => {
      mockbinLogs = await getHttpLogServerLogs();
      // always take the last item of mockbin entries as it represents the last request logs
      const requestDetails = mockbinLogs[mockbinLogs.length - 1].reqBody

      expect(
        requestDetails.request.method,
        'Should see correct kong request method in logs'
      ).to.eq('GET');
      expect(
        requestDetails.request.headers.test,
        'Should see correct kong request header in logs'
      ).to.eq('test');
      expect(
        requestDetails.route.paths[0],
        'Should see correct kong request route path in logs'
      ).to.eq(path);
      expect(
        requestDetails.service.path,
        'Should see correct kong request service path in logs'
      ).to.eq('/anything');
    });
  });

  pluginConfigHeaders.forEach((pluginConfigHeader) => {
    it(`should patch the http-log plugin method to ${pluginConfigHeader}`, async function () {
      const resp = await axios({
        method: 'patch',
        url: `${url}/${pluginId}`,
        data: {
          config: {
            method: pluginConfigHeader,
          },
        },
      });
      logResponse(resp);

      expect(resp.status, 'Status should be 200').to.equal(200);
      expect(
        resp.data.config.method,
        'Should see correct patched method'
      ).to.eq(pluginConfigHeader);

      await waitForConfigRebuild()
    });

    it(`should see request logs in http_endpoint with the new ${pluginConfigHeader} method`, async function () {
      const resp = await axios({
        url: `${proxyUrl}${path}`,
      });
      logResponse(resp);

      expect(resp.status, 'Status should be 200').to.equal(200);

      await eventually(async () => {
        mockbinLogs = await getHttpLogServerLogs();

        expect(
          mockbinLogs[mockbinLogs.length - 1].reqMethod,
          `Should use ${pluginConfigHeader} method to log request data`
        ).to.eq(pluginConfigHeader);
      });
    });
  });

  it('should send resolved custom_fields_by_lua value to http_endpoint', async function () {
    let resp = await axios({
      method: 'patch',
      url: `${url}/${pluginId}`,
      data: {
        config: {
          custom_fields_by_lua: {
            kong: `return 'http-log plugin api test'`,
          },
          headers: { [customHeaderName]: 'test2' },
        },
      },
    });
    logResponse(resp);

    expect(
      resp.data.config.custom_fields_by_lua.kong,
      'Should see correct patched method'
    ).to.eq(`return 'http-log plugin api test'`);

    await waitForConfigRebuild()

    resp = await axios(`${proxyUrl}${path}`);
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);

    await eventually(async () => {
      mockbinLogs = await getHttpLogServerLogs();
      const requestDetails =  mockbinLogs[mockbinLogs.length - 1].reqBody

      expect(
        requestDetails.kong,
        'Should see return value of custom_fields_by_lua'
      ).to.eq('http-log plugin api test');
    }, 19000);
  });

  // skipped due to https://konghq.atlassian.net/browse/KAG-503
  it.skip('should see http-log plugin X-header log in http_endpoint', async function () {
    mockbinLogs = await getHttpLogServerLogs();
    // always take the last item of mockbin entries as it represents the last request logs
    const logHeaders = mockbinLogs[mockbinLogs.length - 1].reqBody.request.headers;

    expect(
      logHeaders.some((headerObject) => {
        return (
          headerObject.name === customHeaderName.toLowerCase() &&
          headerObject.value === 'test2'
        );
      }),
      `Should see the correct plugin custom x header in request logs`
    ).to.be.true;
  });

  it('should delete the http-log plugin by id', async function () {
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
    await deleteHttpLogServerLogs()
  });
});
