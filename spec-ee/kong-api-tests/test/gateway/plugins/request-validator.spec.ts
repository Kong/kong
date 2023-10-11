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
  getNegative,
  randomString,
  wait,
  logResponse,
  waitForConfigHashUpdate,
  getMetric,
  isGwHybrid,
} from '@support';

describe('Gateway Plugins: Request Validator', function () {
  this.timeout(20000);
  const path = `/${randomString()}`;
  const isHybrid = isGwHybrid();
  const paramPath = '~/status/(?<status_code>[a-z0-9]+)';
  const classicWait = 5000;
  let serviceId: string;
  let routeId: string;
  let configHash: string;

  const url = `${getBasePath({
    environment: Environment.gateway.admin,
  })}/plugins`;
  const proxyUrl = `${getBasePath({
    environment: Environment.gateway.proxy,
  })}`;

  let basePayload: any;
  let pluginId: string;

  before(async function () {
    const service = await createGatewayService(randomString(), {
      url: `http://httpbin`,
    });
    serviceId = service.id;
    const route = await createRouteForService(serviceId, [path]);
    routeId = route.id;

    basePayload = {
      name: 'request-validator',
      service: {
        id: serviceId,
      },
      route: {
        id: routeId,
      },
    };

    // configuration hash change can be spotted only in hybrid mode
    if (isHybrid) {
      configHash = await getMetric('kong_data_plane_config_hash');
    }
  });

  it('should not create RV Plugin with non-array parameter_schema', async function () {
    const pluginPayload = {
      ...basePayload,
      config: {
        parameter_schema: { name: { type: 'string', required: true } },
      },
    };

    const resp = await postNegative(url, pluginPayload);
    logResponse(resp);

    expect(resp.status, 'Status should be 400').to.equal(400);
    expect(resp.data.message, 'Should have correct error message').to.contain(
      `schema violation (config.parameter_schema: expected an array)`
    );
  });

  it('should not create RV Plugin with version other than draft4 or kong', async function () {
    const pluginPayload = {
      ...basePayload,
      config: {
        body_schema: "[{ name: { type: 'string', required: true } }]",
        version: 'draft55',
      },
    };

    const resp = await postNegative(url, pluginPayload);
    logResponse(resp);

    expect(resp.status, 'Status should be 400').to.equal(400);
    expect(resp.data.message, 'Should have correct error message').to.contain(
      `(config.version: expected one of: kong, draft4)`
    );
  });

  it('should create plugin with version kong', async function () {
    const pluginPayload = {
      ...basePayload,
      config: {
        body_schema: '[{"name":{"type": "string", "required": true}}]',
        verbose_response: true,
        version: 'kong',
      },
    };
    const resp = await axios({ method: 'post', url, data: pluginPayload });
    logResponse(resp);

    expect(resp.status, 'Status should be 201').to.equal(201);
    expect(
      resp.data.config.body_schema,
      'Should have correct body_schema'
    ).to.eq('[{"name":{"type": "string", "required": true}}]');
    expect(resp.data.config.version, 'Should have correct version').to.eq(
      'kong'
    );
    pluginId = resp.data.id;

    if (isHybrid) {
      configHash = await waitForConfigHashUpdate(configHash, {
        targetNumberOfConfigHashChanges: 2,
      });
    } else {
      await wait(classicWait); // eslint-disable-line no-restricted-syntax
    }
  });

  it('should validate request body with wrong key', async function () {
    const resp = await getNegative(
      `${proxyUrl}${path}`,
      {
        'Content-Type': 'application/json',
      },
      { notype: 'test' }
    );
    logResponse(resp);

    expect(resp.status, 'Status should be 400').to.equal(400);
    expect(
      resp.data.message.name,
      'Should have correct error message'
    ).to.contain(`required field missing`);
  });

  it('should validate request body with wrong key type', async function () {
    const resp = await getNegative(
      `${proxyUrl}${path}`,
      {
        'Content-Type': 'application/json',
      },
      { name: true }
    );
    logResponse(resp);

    expect(resp.status, 'Status should be 400').to.equal(400);
    expect(
      resp.data.message.name,
      'Should have correct error message'
    ).to.contain(`expected a string`);
  });

  it('should not pass request with wrong content-type', async function () {
    const resp = await getNegative(
      `${proxyUrl}${path}`,
      {
        'Content-Type': 'text/plain',
      },
      { name: true }
    );
    logResponse(resp);

    expect(resp.status, 'Status should be 400').to.equal(400);
    expect(resp.data.message, 'Should have correct error message').to.contain(
      `specified Content-Type is not allowed`
    );
  });

  it('should validate and pass correct request body', async function () {
    const resp = await axios({
      url: `${proxyUrl}${path}`,
      headers: {
        'Content-Type': 'application/json',
      },
      data: { name: 'test' },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
  });

  it('should update and see request validator plugin config with GET /pluginId', async function () {
    let resp = await axios({
      method: 'patch',
      url: `${url}/${pluginId}`,
      data: {
        config: {
          body_schema: null,
          version: 'draft4',
          parameter_schema: [
            {
              required: true,
              style: 'simple',
              explode: false,
              schema: '{"type": "number"}',
              name: 'status_code',
              in: 'path',
            },
          ],
        },
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);

    if (isHybrid) {
      configHash = await waitForConfigHashUpdate(configHash);
    } else {
      await wait(classicWait); // eslint-disable-line no-restricted-syntax
    }

    resp = await axios(`${url}/${pluginId}`);
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.config.body_schema, 'Should have body_schema null').to.be
      .null;
    expect(resp.data.config.version, 'Should have correct version').to.eq(
      'draft4'
    );
    expect(
      resp.data.config.parameter_schema[0].name,
      'Should have correct parameter_schema name'
    ).to.eq('status_code');
  });

  it('should validate wrong path parameter', async function () {
    let resp = await postNegative(
      `${url}/${pluginId}/route`,
      {
        strip_path: false,
        paths: [paramPath],
      },
      'patch',
      {}
    );
    logResponse(resp);

    if (isHybrid) {
      configHash = await waitForConfigHashUpdate(configHash);
    } else {
      await wait(classicWait); // eslint-disable-line no-restricted-syntax
    }

    expect(resp.status, 'Status should be 200').to.equal(200);

    resp = await getNegative(`${proxyUrl}/status/abc`, {}, {});
    logResponse(resp);

    expect(resp.status, 'Status should be 400').to.equal(400);
    expect(resp.data.message, 'Should have correct error message').to.contain(
      "path 'status_code' validation failed, [error] wrong type: expected number, got string"
    );
  });

  it('should validate and pass correct path parameter', async function () {
    const resp = await axios(`${proxyUrl}/status/200`);
    logResponse(resp);
    expect(resp.status, 'Status should be 200').to.equal(200);
  });

  it('should delete the Request Validator plugin', async function () {
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
