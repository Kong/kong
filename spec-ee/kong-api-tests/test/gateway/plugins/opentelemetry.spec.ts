import axios from 'axios';
import {
  expect,
  Environment,
  getBasePath,
  postNegative,
  createGatewayService,
  deleteGatewayService,
  deleteGatewayRoute,
  randomString,
  isGwHybrid,
  wait,
  logResponse,
  deletePlugin,
  createRouteForService,
  setGatewayContainerEnvVariable,
} from '@support';

describe.skip('Gateway Plugins: OpenTelemetry', function () {
  const isHybrid = isGwHybrid();
  const hybridWaitTime = 8000;
  const jaegerWait = 8000;
  const configEndpoint = 'http://jaeger:4318/v1/traces';
  const paths = ['/jaegertest1', '/jaegertest2'];
  let serviceId: string;
  let routeId: string;

  const host = `${getBasePath({
    environment: Environment.gateway.hostName,
  })}`;
  const jaegerTracesEndpoint = `http://${host}:16686/api/traces?service=kong&lookback=2m&limit=10`;

  const url = `${getBasePath({
    environment: Environment.gateway.admin,
  })}/plugins`;
  const proxyUrl = `${getBasePath({
    environment: Environment.gateway.proxy,
  })}`;

  let pluginId: string;

  before(async function () {
    // enable kong opel tracing for requests for this test
    setGatewayContainerEnvVariable({
      KONG_TRACING_INSTRUMENTATIONS: 'request',
    });

    if (isHybrid) {
      setGatewayContainerEnvVariable(
        {
          KONG_TRACING_INSTRUMENTATIONS: 'request',
        },
        'kong-dp1'
      );
    }

    await wait(2000);
    const service = await createGatewayService(randomString());
    serviceId = service.id;
    const route = await createRouteForService(serviceId, ['/']);
    routeId = route.id;
  });

  it('should not create opel plugin with invalid config.endpoint', async function () {
    const pluginPayload = {
      name: 'opentelemetry',
      config: {
        endpoint: 'test',
      },
    };

    const resp = await postNegative(url, pluginPayload);
    logResponse(resp);

    expect(resp.status, 'Status should be 400').to.equal(400);
    expect(resp.data.message, 'Should have correct error message').to.contain(
      `schema violation (config.endpoint: missing host in url)`
    );
  });

  it('should create opel plugin with valid jaeger config.endpoint', async function () {
    const pluginPayload = {
      name: 'opentelemetry',
      config: {
        endpoint: configEndpoint,
      },
    };

    const resp = await axios({
      method: 'post',
      url,
      data: pluginPayload,
    });
    logResponse(resp);

    pluginId = resp.data.id;
    expect(resp.status, 'Status should be 201').to.equal(201);

    await wait(hybridWaitTime);
  });

  it('should send proxy request traces to jaeger', async function () {
    let targetDataset: any;
    let resp = await axios(`${proxyUrl}${paths[0]}`);
    logResponse(resp);
    await wait(jaegerWait);

    resp = await axios(jaegerTracesEndpoint);
    logResponse(resp);

    expect(
      resp.data.data.length,
      'Should send one request trace to jaeger'
    ).to.gte(1);

    let isFound = false;
    for (const data of resp.data.data) {
      if (data.spans[0].operationName.includes(paths[0])) {
        isFound = true;
        targetDataset = data;
        break;
      }
    }

    expect(isFound, 'Should find the target trace in jaeger').to.be.true;

    expect(
      targetDataset.spans[0].operationName,
      'Should have correct operationName'
    ).to.equal(`GET ${paths[0]}`);

    expect(
      targetDataset.processes.p1.serviceName,
      'Should have correct serviceName'
    ).to.equal(`kong`);

    expect(
      targetDataset.processes.p1.tags[0].value,
      'Should have service.instance.id'
    ).to.be.string;
    expect(
      targetDataset.processes.p1.tags[1].value,
      'Should have service.version'
    ).to.be.string;

    const opelTagUrl = `${proxyUrl.split(':8000')[0]}${paths[0]}`;

    expect(
      targetDataset.spans[0].tags.some((tag) => tag.value === opelTagUrl),
      `Should see correct path in jaeger trace span tags`
    ).to.be.true;

    expect(
      targetDataset.spans[0].tags.some((tag) => tag.value === 200),
      `Should see correct status_code in jaeger trace span tags`
    ).to.be.true;
  });

  it('should patch opel plugin resource_attributes', async function () {
    const resp = await axios({
      method: 'patch',
      url: `${url}/${pluginId}`,
      data: {
        config: {
          resource_attributes: {
            'service.instance.id': '8888',
            'service.version': 'kongtest',
          },
        },
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(
      resp.data.config.resource_attributes['service.instance.id'],
      'Should see updated instance id'
    ).to.equal('8888');
    expect(
      resp.data.config.resource_attributes['service.version'],
      'Should see updated instance id'
    ).to.equal('kongtest');

    // await wait(isHybrid ? hybridWaitTime : waitTime);
  });

  // skipping due to https://konghq.atlassian.net/browse/KAG-304
  it.skip('should send updated service instance.id and version metadata to jaeger', async function () {
    let resp = await axios(`${proxyUrl}${paths[1]}`);
    logResponse(resp);
    await wait(jaegerWait);

    resp = await axios(jaegerTracesEndpoint);
    logResponse(resp);

    expect(
      resp.data.data.length,
      'Should see total 2 requests traces in jaeger'
    ).to.be.gte(2);

    let isFound = false;
    for (const data of resp.data.data) {
      if (data.spans[0].operationName.includes(paths[1])) {
        isFound = true;

        expect(
          data.spans[0].operationName,
          'Should have correct operationName'
        ).to.equal(`GET ${paths[1]}`);

        expect(
          data.processes.p1.tags[0].value,
          'Should have correct service.instance.id'
        ).to.equal(`8888`);
        expect(
          data.processes.p1.tags[1].value,
          'Should have correct service.version'
        ).to.equal(`kongtest`);
      }
    }

    expect(isFound, 'Should find the target trace in jaeger').to.be.true;
  });

  after(async function () {
    setGatewayContainerEnvVariable({
      KONG_TRACING_INSTRUMENTATIONS: 'off',
    });
    if (isHybrid) {
      setGatewayContainerEnvVariable(
        {
          KONG_TRACING_INSTRUMENTATIONS: 'off',
        },
        'kong-dp1'
      );
    }
    await deletePlugin(pluginId);
    await deleteGatewayRoute(routeId);
    await deleteGatewayService(serviceId);
  });
});
