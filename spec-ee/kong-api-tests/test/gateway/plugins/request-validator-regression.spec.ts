import axios from 'axios';
import { jsonSchemas } from '@fixtures';
import { execSync } from 'child_process';
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
  deletePlugin,
  randomString,
  isGwHybrid,
  isLocalDatabase,
  wait,
  logResponse,
  waitForConfigRebuild,
  isGateway
} from '@support';

describe('Gateway Plugins: Request Validator Regression Tests', function () {
  const path = `/${randomString()}`;
  const isHybrid = isGwHybrid();
  const isLocalDb = isLocalDatabase();
  const waitTime = 5000;
  const hybridWaitTime = 7000;
  let serviceId: string;
  let routeId: string;

  const url = `${getBasePath({
    environment: Environment.gateway.admin,
  })}/plugins`;
  const proxyUrl = getBasePath({ environment: isGateway() ? Environment.gateway.proxy : undefined });

  let basePayload: any;
  let pluginId: string;

  before(async function () {
    const service = await createGatewayService(randomString());
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
  });

  it('should not create RV Plugin without Body and Parameter Schema', async function () {
    const resp = await postNegative(url, basePayload);
    logResponse(resp);

    expect(resp.status, 'Status should be 400').to.equal(400);
    expect(resp.data.message, 'Should have correct error message').to.contain(
      `at least one of these fields must be non-empty: 'body_schema', 'parameter_schema'`
    );
  });

  it('should not create RV Plugin with non-string body schema', async function () {
    const pluginPayload = {
      ...basePayload,
      config: {
        body_schema: [{ name: { type: 'string', required: true } }],
      },
    };

    const resp = await postNegative(url, pluginPayload);
    logResponse(resp);
    expect(resp.status, 'Status should be 400').to.equal(400);
    expect(resp.data.message, 'Should have correct error message').to.contain(
      `schema violation (config.body_schema: expected a string)`
    );
  });

  it('should create RV plugin with valid draft4 body_schema', async function () {
    const pluginPayload = {
      ...basePayload,
      config: {
        body_schema: jsonSchemas.maxItems,
        version: 'draft4',
      },
    };

    const resp = await axios({
      method: 'post',
      url,
      data: pluginPayload,
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 201').to.equal(201);
    pluginId = resp.data.id;
  });

  it('should pass request body with maxItems 2600 and more', async function () {
    const arrayOf2600 = Array.from(new Array(2600), () => 'a');
    await wait(isHybrid ? 12000 : 6000); // eslint-disable-line no-restricted-syntax

    const reqBody = {
      where: {
        kpiId: arrayOf2600,
      },
    };

    const resp = await axios({
      url: `${proxyUrl}${path}`,
      headers: { 'Content-Type': 'application/json' },
      data: reqBody,
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.eq(200);
  });

  it('should pass request body with duplicate keys', async function () {
    const reqBody = '{"where":{"kpiId":["a"],"kpiId":["a"]}}';
    let response: any = execSync(
      `curl -v -H "Content-Type: application/json" ${proxyUrl}${path} --data '${reqBody}'`,
      { encoding: 'utf8', stdio: 'pipe' }
    );

    response = JSON.parse(response.toString());

    // eslint-disable-next-line prettier/prettier
    expect(response.data, 'Request should pass').to.eq(
      `{"where":{"kpiId":["a"],"kpiId":["a"]}}`
    );
  });

  // existing bug https://konghq.atlassian.net/browse/FTI-2100
  it.skip('should patch the plugin with extra long body_schema', async function () {
    const resp = await postNegative(
      `${url}/${pluginId}`,
      { config: { body_schema: jsonSchemas.longSchema } },
      'patch'
    );
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(400);
  });

  it('should patch the plugin with parameter_schema', async function () {
    const resp = await axios({
      method: 'patch',
      url: `${url}/${pluginId}`,
      data: {
        config: {
          body_schema: null,
          verbose_response: true,
          parameter_schema: [
            {
              name: 'kpiId',
              in: 'query',
              required: false,
              schema: jsonSchemas.paramSchema,
              style: 'form',
              explode: true,
            },
          ],
        },
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.config.body_schema, 'Should have body_schema null').to.be
      .null;
    expect(
      resp.data.config.parameter_schema[0],
      'Should have correct parameter_schema'
    ).to.haveOwnProperty('explode', true);

    // give some time for changes to take effect and avoid flakiness
    await wait(1000); // eslint-disable-line no-restricted-syntax
  });

  it('should validate with explode true in parameter_schema and query params', async function () {
    const queryUrl = `${proxyUrl}${path}?kpiId=ServiceId_marquee-desktop-resource&kpiId=ServiceId_marquee-desktop-resourc2`;
    const resp = await getNegative(queryUrl, {
      'Content-Type': 'application/json',
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
  });

  it('should update the request validator plugin with put request', async function () {
    await wait(isHybrid ? 6000 : 3000); // eslint-disable-line no-restricted-syntax

    const resp = await axios({
      method: 'put',
      url: `${url}/${pluginId}`,
      data: {
        name: 'request-validator',
        config: {
          parameter_schema: null,
          body_schema: jsonSchemas.dateTime,
          version: 'draft4',
        },
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.config.body_schema, 'Should have body_schema null').to.eq(
      jsonSchemas.dateTime
    );
    expect(
      resp.data.config.parameter_schema,
      'Should have correct parameter_schema'
    ).to.be.null;
  });

  it('should validate invalid date format', async function () {
    await wait(waitTime + (isLocalDb ? 0 : hybridWaitTime)); // eslint-disable-line no-restricted-syntax

    const resp = await getNegative(
      `${proxyUrl}${path}`,
      { 'Content-Type': 'application/json' },
      { startTime: '20200-06-05T14:48:00.000Z' }
    );
    logResponse(resp);

    expect(resp.data.message, 'Should have correct error message').to.eq(
      `request body doesn't conform to schema`
    );
  });

  it('should validate correct date format', async function () {
    await wait(waitTime + 1000); // eslint-disable-line no-restricted-syntax

    const resp = await axios({
      url: `${proxyUrl}${path}`,
      headers: { 'Content-Type': 'application/json' },
      data: { startTime: '2020-06-05T14:48:00.000Z' },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
  });

  it('should validate schema with unicode characters in regex and do not throw error', async function () {
    let resp = await axios({
      method: 'patch',
      url: `${url}/${pluginId}`,
      data: {
        config: {
          body_schema: jsonSchemas.unicode,
        },
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);

    resp = await getNegative(
      `${proxyUrl}${path}`,
      { 'Content-Type': 'application/json' },
      {
        context: {
          ip: 'test㍿ㇰㇱ𒐹',
        },
      }
    );
    logResponse(resp);

    expect(resp.data.message, 'Should have correct error message').to.eq(
      `request body doesn't conform to schema`
    );
  });

  it('should delete the Request Validator plugin', async function () {
    const resp = await axios({
      method: 'delete',
      url: `${url}/${pluginId}`,
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 204').to.equal(204);
  });

  it('should create plugin with given body_schema', async function () {
    const pluginPayload = {
      ...basePayload,
      config: {
        body_schema: jsonSchemas.bodySchema,
        verbose_response: true,
        parameter_schema: null,
        allowed_content_types: null,
        version: 'draft4',
      },
    };

    const resp = await axios({ method: 'post', url, data: pluginPayload });
    logResponse(resp);

    expect(resp.status, 'Status should be 201').to.equal(201);
    expect(
      resp.data.config.body_schema,
      'Should have correct body_schema'
    ).to.eq(jsonSchemas.bodySchema);
    pluginId = resp.data.id;
  });

  it('should support multiple headers with same name', async function () {
    const pluginPayload = {
      config: {
        body_schema: null,
        parameter_schema: [
          {
            name: 'testHeader',
            in: 'header',
            required: false,
            schema:
              '{"type":"array","items":{"maxLength":512,"minLength":1,"pattern":"^[\\\\w.,-]*$","type":"string"},"maxItems":5,"minItems":0}',
            style: 'simple',
            explode: false,
          },
        ],
        version: 'kong',
      },
    };

    const resp = await axios({
      method: 'patch',
      url: `${url}/${pluginId}`,
      data: pluginPayload,
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);

    await waitForConfigRebuild();

    let response: any = execSync(
      `curl -v ${proxyUrl}${path} -H 'testHeader:www.example.com' -H 'testHeader:www.sample.com' -H 'myHeader:www.test.com'`,
      { encoding: 'utf8', stdio: 'pipe' }
    );

    response = JSON.parse(response.toString());
    expect(
      response.headers.Testheader,
      'Should see multiple headers with same name'
    ).to.equal('www.example.com,www.sample.com');
    expect(response.headers.Myheader, 'Should see myheader').to.equal(
      'www.test.com'
    );
  });

  after(async function () {
    await deletePlugin(pluginId);
    await deleteGatewayRoute(routeId);
    await deleteGatewayService(serviceId);
  });
});
