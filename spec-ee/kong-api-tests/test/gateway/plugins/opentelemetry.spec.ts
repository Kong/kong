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
  isLocalDatabase,
  wait,
  logResponse,
  deletePlugin,
  createRouteForService,
  resetGatewayContainerEnvVariable,
  getKongContainerName,
  logDebug,
  isGateway,
  retryRequest,
} from '@support';

describe('@oss: Gateway Plugins: OpenTelemetry', function () {
  this.timeout(50000);

  const isHybrid = isGwHybrid();
  const isLocalDb = isLocalDatabase();
  const waitTime = 5000;
  const hybridWaitTime = 8000;
  const jaegerWait = 20000;
  const configEndpoint = 'http://jaeger:4318/v1/traces';
  const paths = ['/jaegertest1', '/jaegertest2', '/jaegertest3'];
  const b3Header = '80f198ee56343ba864fe8b2a57d3eff7-e457b5a2e4d86bd1-1-05e3ac9a4f6e3b90'
  const traceparentHeader = '00-80e1afed08e019fc1110464cfa66635c-7a085853722dc6d2-01'
  const amazonHeader = 'Root=1-63441c4a-abcdef012345678912345678'
  const otHeader = 'W31SFeJcgC00L0DFXtsjSmwVwgJB0soF'

  const host = `${getBasePath({
    app: 'gateway',
    environment: Environment.gateway.hostName,
  })}`;
  const jaegerTracesEndpoint = `http://${host}:16686/api/traces?service=kong&lookback=2m`;

  const url = `${getBasePath({
    environment: isGateway() ? Environment.gateway.admin : undefined,
  })}/plugins`;

  const proxyUrl = `${getBasePath({
    app: 'gateway',
    environment: Environment.gateway.proxy,
  })}`;

  const gwContainerName = getKongContainerName();

  let serviceId: string;
  let routeId: string;
  let pluginId: string;
  let totalTraces: number;
  let expectedTraces: number;

  before(async function () {
    // enable kong otel tracing for requests for this test
    await resetGatewayContainerEnvVariable(
      {
        KONG_TRACING_INSTRUMENTATIONS: 'request',
        KONG_TRACING_SAMPLING_RATE: 1,
      },
      gwContainerName
    );
    if (isHybrid) {
      await resetGatewayContainerEnvVariable(
        {
          KONG_TRACING_INSTRUMENTATIONS: 'request',
          KONG_TRACING_SAMPLING_RATE: 1,
        },
        'kong-dp1'
      );
    }

    //  wait longer if running kong natively
    await wait(gwContainerName === 'kong-cp' ? 2000 : 5000); // eslint-disable-line no-restricted-syntax
    const service = await createGatewayService(randomString());
    serviceId = service.id;
    const route = await createRouteForService(serviceId, ['/']);
    routeId = route.id;

    await wait(jaegerWait); // eslint-disable-line no-restricted-syntax
  });

  it('should not create otel plugin with invalid config.endpoint', async function () {
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
      `missing host in url`
    );
  });

  it('should create otel plugin with valid jaeger config.endpoint', async function () {
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

    await wait(hybridWaitTime + (isLocalDb ? 0 : hybridWaitTime)); // eslint-disable-line no-restricted-syntax
  });

  it('should send proxy request traces to jaeger', async function () {
    let targetDataset: any;
    let urlObj;
    let statusObj;
    let resp = await axios(`${proxyUrl}${paths[0]}`);
    logResponse(resp);
    await wait(jaegerWait + (isLocalDb ? 0 : 10000)); // eslint-disable-line no-restricted-syntax

    resp = await axios(jaegerTracesEndpoint);
    logResponse(resp);
    totalTraces = resp.data.data.length;

    expect(
      resp.data.data.length,
      'Should send one request trace to jaeger'
    ).to.gte(1);

    let isFound = false;
    for (const data of resp.data.data) {
      // find the http.url object which value is 'http://localhost/jaegertest1''
      urlObj = data.spans[0].tags.find((obj) => obj.key === 'http.url');
      logDebug('urlObj.value: ' + urlObj.value);
      statusObj = data.spans[0].tags.find((obj) => obj.key === 'http.status_code');
      logDebug('urlStatus.value: ' + statusObj.value);

      if (urlObj.value.includes(paths[0]) && statusObj.value === 200) {
        isFound = true;
        targetDataset = data;
        break;
      }
    }

    expect(isFound, 'Should find the target trace in jaeger').to.be.true;

    expect(
      targetDataset.spans[0].operationName,
      'Should have operationName kong'
    ).to.equal(`kong`);

    expect(
      targetDataset.processes.p1.serviceName,
      'Should have correct serviceName'
    ).to.equal(`kong`);

    const instance_id = targetDataset.processes.p1.tags.find((obj) => {
      return obj.key === 'service.instance.id';
    });
    const version = targetDataset.processes.p1.tags.find((obj) => {
      return obj.key === 'service.version';
    });
    expect(
      instance_id.value,
      'Should have service.instance.id'
    ).to.be.string;
    expect(
      version.value,
      'Should have service.version'
    ).to.be.string;

    const otelTagUrl = `${proxyUrl.split(':8000')[0]}${paths[0]}`;

    expect(urlObj.value, `Should see correct http.url`).to.equal(otelTagUrl);

    expect(
      targetDataset.spans[0].tags.some((tag) => tag.value === 200),
      `Should see correct status_code in jaeger trace span tags`
    ).to.be.true;
  });

  it('should patch otel plugin resource_attributes', async function () {
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

    await wait( // eslint-disable-line no-restricted-syntax
      isHybrid
        ? hybridWaitTime + (isLocalDb ? 0 : hybridWaitTime)
        : waitTime + (isLocalDb ? 0 : waitTime)
    );
  });

  it('should send updated service instance.id and version metadata to jaeger', async function () {
    const resp = await axios(`${proxyUrl}${paths[1]}`);
    logResponse(resp);
    await wait(jaegerWait + (isLocalDb ? 0 : hybridWaitTime)); // eslint-disable-line no-restricted-syntax

    expectedTraces = totalTraces + 1;

    const req = () =>
      axios({
        url: jaegerTracesEndpoint,
      });

    const assertions = (resp) => {
      expect(
        resp.data.data.length,
        'Should see correct number of request traces in jaeger'
      ).to.be.greaterThanOrEqual(expectedTraces);

      // setting new totalTraces number
      totalTraces = resp.data.data.length;

      let isFound = false;
      for (const data of resp.data.data) {
        const urlObj = data.spans[0].tags.find((obj) => obj.key === 'http.url');

        if (urlObj.value.includes(paths[1])) {
          isFound = true;

          expect(urlObj.value, `Should see correct http.url`).to.contain(
            paths[1]
          );

          expect(
            data.spans[0].operationName,
            'Should have kong operationName'
          ).to.equal(`kong`);

          const instance_id = data.processes.p1.tags.find((obj) => {
            return obj.key === 'service.instance.id';
          });
          const version = data.processes.p1.tags.find((obj) => {
            return obj.key === 'service.version';
          });
          expect(
            instance_id.value,
            'Should have correct service.instance.id'
          ).to.equal(`8888`);
          expect(
            version.value,
            'Should have correct service.version'
          ).to.equal(`kongtest`);
        }
      }

      expect(isFound, 'Should find the target trace in jaeger').to.be.true;
    };

    await retryRequest(req, assertions);
  });

  it('should not get 500 when traceparent -00 header is present in the request', async function () {
    // note that traces will not be sent as the header has suffix -00
    const resp = await axios({
      url: `${proxyUrl}${paths[1]}`,
      headers: {
        traceparent: '00-fff379b78684fd43a9e2bba4676ddc90-eb1c7f5c7a2f374f-00',
      },
    });

    logResponse(resp);
    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.headers['Traceparent'], 'Should see Traceparent header being sent').to.contain('00-fff379b78684fd43a9e2bba4676ddc90');
  });

  it('should see only b3 header instead of traceparent when b3 exists in request', async function () {
    const resp = await axios({
      url: `${proxyUrl}${paths[1]}`,
      headers: {
        b3: b3Header,
      },
    });

    logResponse(resp);
    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.headers['Traceparent'], 'Should not see Traceparent header when b3 header exists').to.not.exist
    expect(resp.data.headers['B3'], 'Should see B3 header being sent').to.contain(b3Header.split('-')[0]);
  });

  it('should patch otel plugin header_type to ignore', async function () {
    const resp = await axios({
      method: 'patch',
      url: `${url}/${pluginId}`,
      data: {
        config: {
          resource_attributes: null,
          header_type: 'ignore'
        },
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.config.header_type,'Should see header_type updated').to.equal('ignore')

    await wait( // eslint-disable-line no-restricted-syntax
      isHybrid
        ? hybridWaitTime + (isLocalDb ? 0 : hybridWaitTime)
        : waitTime + (isLocalDb ? 0 : waitTime)
    );
  });

  it('should see a different traceparent header id when header_type is ignore', async function () {
    const resp = await axios({
      url: `${proxyUrl}${paths[1]}`,
      headers: {
        traceparent: traceparentHeader,
      },
    });

    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.headers['Traceparent'], 'Should see Traceparent header with different id').to.not.contain(traceparentHeader.split('-')[1]);
  });

  it('should see the same value for both b3 and traceparent headers with header_type w3c', async function () {
    let resp = await axios({
      method: 'patch',
      url: `${url}/${pluginId}`,
      data: {
        config: {
          header_type: 'w3c'
        },
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.config.header_type,'Should see header_type updated').to.equal('w3c')

    await wait( // eslint-disable-line no-restricted-syntax
      isHybrid
        ? hybridWaitTime + (isLocalDb ? 0 : hybridWaitTime)
        : waitTime + (isLocalDb ? 0 : waitTime)
    );

    resp = await axios({
      url: `${proxyUrl}${paths[1]}`,
      headers: {
        b3: b3Header,
        traceparent: traceparentHeader,
      },
    });

    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.headers['Traceparent'], 'Should see Traceparent header with same value as B3').to.contain(b3Header.split('-')[0]);
    expect(resp.data.headers['B3'], 'Should see B3 header with given value').to.contain(b3Header.split('-')[0]);
    expect(resp.data.headers['B3'], 'Should see B3 header id').to.contain(b3Header.split('-')[1]);
  });

  it('should patch otel plugin propagation configurations', async function () {
    const resp = await axios({
      method: 'patch',
      url: `${url}/${pluginId}`,
      data: {
        config: {
          propagation: {
            clear: null,
            default_format: 'w3c',
            extract: ['w3c'],
            inject: ['w3c']
          }
        },
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.config.propagation.default_format,'Should see correct propagation.default_format').to.equal('w3c')
    expect(resp.data.config.propagation.extract,'Should see updated propagation.extract').to.eql(['w3c'])
    expect(resp.data.config.propagation.inject,'Should see updated propagation.inject').to.eql(['w3c'])

    await wait( // eslint-disable-line no-restricted-syntax
      isHybrid
        ? hybridWaitTime + (isLocalDb ? 0 : hybridWaitTime)
        : waitTime + (isLocalDb ? 0 : waitTime)
    );
  });

  it('should both b3 and traceparent headers preserve their values', async function () {
    const req = () =>
      axios({
        url: `${proxyUrl}${paths[1]}`,
        headers: {
          b3: b3Header,
          traceparent: traceparentHeader,
        },
      });

    const assertions = (resp) => {
      expect(resp.status, 'Status should be 200').to.equal(200);
      expect(resp.data.headers['B3'], 'Should see B3 header with given value').to.contain(b3Header.split('-')[0]);
      expect(resp.data.headers['B3'], 'Should see B3 header id').to.contain(b3Header.split('-')[1]);
      expect(resp.data.headers['B3'], 'Should see B3 header parentSpanId').to.contain(b3Header.split('-')[3]);
      expect(resp.data.headers['Traceparent'], 'Should see Traceparent header with its value').to.contain(traceparentHeader.split('-')[1]);
    };

    await retryRequest(req, assertions);
  });

  it('should propagation.clear the given b3 header', async function () {
    let resp = await axios({
      method: 'patch',
      url: `${url}/${pluginId}`,
      data: {
        config: {
          propagation: {
            clear: ['b3'],
            default_format: 'w3c',
            extract: ['w3c'],
            inject: ['w3c']
          }
        },
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.config.propagation.default_format,'Should see correct propagation.default_format').to.equal('w3c')
    expect(resp.data.config.propagation.extract,'Should see updated propagation.extract').to.eql(['w3c'])
    expect(resp.data.config.propagation.clear,'Should see updated propagation.clear').to.eql(['b3'])

    await wait( // eslint-disable-line no-restricted-syntax
      isHybrid
        ? hybridWaitTime + (isLocalDb ? 0 : hybridWaitTime)
        : waitTime + (isLocalDb ? 0 : waitTime)
    );

    resp = await axios({
      url: `${proxyUrl}${paths[1]}`,
      headers: {
        b3: b3Header,
        traceparent: traceparentHeader,
      },
    });

    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.headers['B3'], 'Should not see B3 header').to.not.exist
    expect(resp.data.headers['Traceparent'], 'Should see Traceparent header with its value').to.contain(traceparentHeader.split('-')[1]);
  });
  
  it('should not replace traceparent value with b3 when propagation.clear contains b3 and both headers exist in the request', async function () {
    let resp = await axios({
      method: 'patch',
      url: `${url}/${pluginId}`,
      data: {
        config: {
          propagation: {
            clear: ['b3'],
            default_format: 'w3c',
            extract: ['w3c', 'b3'],
            inject: ['w3c']
          }
        },
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.config.propagation.extract,'Should see updated propagation.extract').to.eql(['w3c', 'b3'])
    expect(resp.data.config.propagation.clear,'Should see updated propagation.clear').to.eql(['b3'])

    await wait( // eslint-disable-line no-restricted-syntax
      isHybrid
        ? hybridWaitTime + (isLocalDb ? 0 : hybridWaitTime)
        : waitTime + (isLocalDb ? 0 : waitTime)
    );

    resp = await axios({
      url: `${proxyUrl}${paths[1]}`,
      headers: {
        b3: b3Header,
        traceparent: traceparentHeader,
      },
    });

    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.headers['B3'], 'Should not see B3 header').to.not.exist
    expect(resp.data.headers['Traceparent'], 'Should see Traceparent header with its value').to.contain(traceparentHeader.split('-')[1]);
  });

  it('should replace traceparent value with b3 when propagation.clear contains b3 and only b3 header exists in the request', async function () {
    const resp = await axios({
      url: `${proxyUrl}${paths[1]}`,
      headers: {
        b3: b3Header
      },
    });

    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.headers['B3'], 'Should not see B3 header').to.not.exist
    expect(resp.data.headers['Traceparent'], 'Should see Traceparent header with B3 value').to.contain(b3Header.split('-')[0]);
  });

  it('should extract from given header and inject to the target one', async function () {
    let resp = await axios({
      method: 'patch',
      url: `${url}/${pluginId}`,
      data: {
        config: {
          propagation: {
            clear: ['b3'],
            default_format: 'w3c',
            extract: ['aws'],
            inject: ['ot']
          }
        },
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.config.propagation.extract,'Should see updated propagation.extract').to.eql(['aws'])
    expect(resp.data.config.propagation.inject,'Should see updated propagation.inject').to.eql(['ot'])

    await wait( // eslint-disable-line no-restricted-syntax
      isHybrid
        ? hybridWaitTime + (isLocalDb ? 0 : hybridWaitTime)
        : waitTime + (isLocalDb ? 0 : waitTime)
    );

    resp = await axios({
      url: `${proxyUrl}${paths[1]}`,
      headers: {
        "X-Amzn-Trace-Id": amazonHeader,
        "Ot-Tracer-Traceid": otHeader,
      },
    });

    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.headers['X-Amzn-Trace-Id'], 'Should unchanged X-Amzn-Trace-Id header').to.equal(amazonHeader)
    expect(resp.data.headers['Ot-Tracer-Traceid'], 'Should see Ot-Tracer-Traceid header with aws value').to.contain(amazonHeader.split('-')[1]);
  });

  it('should not inject to the target header when extract is not present', async function () {
    const resp = await axios({
      url: `${proxyUrl}${paths[1]}`,
      headers: {
        "Ot-Tracer-Traceid": otHeader,
      },
    });

    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.headers['X-Amzn-Trace-Id'], 'Should not see X-Amzn-Trace-Id header').to.not.exist
    expect(resp.data.headers['Ot-Tracer-Traceid'], 'Should see Ot-Tracer-Traceid header with non aws value').to.not.contain(amazonHeader.split('-')[1]);
    expect(resp.data.headers['Ot-Tracer-Sampled'], 'Should see ot sampled header').to.exist
    expect(resp.data.headers['Ot-Tracer-Spanid'], 'Should see ot Spanid header').to.exist
  });

  it('should use the default header when extract is not present and inject is preserve', async function () {
    let resp = await axios({
      method: 'patch',
      url: `${url}/${pluginId}`,
      data: {
        config: {
          propagation: {
            clear: null,
            default_format: 'ot',
            extract: ['datadog'],
            inject: ['preserve']
          }
        },
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.config.propagation.extract,'Should see updated propagation.extract').to.eql(['datadog'])
    expect(resp.data.config.propagation.inject,'Should see updated propagation.inject').to.eql(['preserve'])

    await wait( // eslint-disable-line no-restricted-syntax
      isHybrid
        ? hybridWaitTime + (isLocalDb ? 0 : hybridWaitTime)
        : waitTime + (isLocalDb ? 0 : waitTime)
    );

    resp = await axios({
      url: `${proxyUrl}${paths[1]}`,
    });

    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.headers['Ot-Tracer-Sampled'], 'Should see ot sampled header').to.exist
    expect(resp.data.headers['Ot-Tracer-Spanid'], 'Should see ot Spanid header').to.exist
    expect(resp.data.headers['Ot-Tracer-Traceid'], 'Should see ot Traceid header').to.exist
  });

  it('should see all specified inject headers added by kong', async function () {
    let resp = await axios({
      method: 'patch',
      url: `${url}/${pluginId}`,
      data: {
        config: {
          propagation: {
            extract: ['w3c', 'b3'],
            inject: ['w3c', 'b3', 'datadog', 'aws', 'gcp', 'jaeger', 'ot'],
            clear: ['b3'],
            default_format: 'w3c',
          }
        },
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.config.propagation.inject,'Should see updated propagation.inject values').to.eql(['w3c', 'b3', 'datadog', 'aws', 'gcp', 'jaeger', 'ot'])

    await wait( // eslint-disable-line no-restricted-syntax
      isHybrid
        ? hybridWaitTime + (isLocalDb ? 0 : hybridWaitTime)
        : waitTime + (isLocalDb ? 0 : waitTime)
    );

    resp = await axios({
      url: `${proxyUrl}${paths[1]}`,
      headers: {
        traceparent: traceparentHeader,
      },
    });

    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.headers['Ot-Tracer-Sampled'], 'Should see ot sampled header').to.exist
    expect(resp.data.headers['Ot-Tracer-Spanid'], 'Should see ot Spanid header').to.exist
    expect(resp.data.headers['Ot-Tracer-Traceid'], 'Should see ot Traceid header').to.exist
    expect(resp.data.headers['Uber-Trace-Id'], 'Should see Uber-Trace-Id header').to.exist
    expect(resp.data.headers['X-Amzn-Trace-Id'], 'Should see X-Amzn-Trace-Id header').to.contain('Root=')
    expect(resp.data.headers['X-B3-Parentspanid'], 'Should see X-B3-Parentspanid header').to.exist
    expect(resp.data.headers['X-B3-Sampled'], 'Should see X-B3-Sampled header').to.exist
    expect(resp.data.headers['X-B3-Spanid'], 'Should see X-B3-Spanid header').to.exist
    expect(resp.data.headers['X-B3-Traceid'], 'Should see X-B3-Traceid header').to.exist
    expect(resp.data.headers['X-Cloud-Trace-Context'], 'Should see X-Cloud-Trace-Context header').to.exist
    expect(resp.data.headers['X-Datadog-Parent-Id'], 'Should see X-Datadog-Parent-Id header').to.exist
    expect(resp.data.headers['X-Datadog-Sampling-Priority'], 'Should see X-Datadog-Sampling-Priority header').to.exist
    expect(resp.data.headers['X-Datadog-Trace-Id'], 'Should see X-Datadog-Trace-Id header').to.exist
    expect(resp.data.headers['X-Datadog-Trace-Id'], 'Should see X-Datadog-Trace-Id header').to.exist
  });

  after(async function () {
    await resetGatewayContainerEnvVariable(
      {
        KONG_TRACING_INSTRUMENTATIONS: 'off',
        KONG_TRACING_SAMPLING_RATE: 0.01,
      },
      gwContainerName
    );
    if (isHybrid) {
      await resetGatewayContainerEnvVariable(
        {
          KONG_TRACING_INSTRUMENTATIONS: 'off',
          KONG_TRACING_SAMPLING_RATE: 0.01,
        },
        'kong-dp1'
      );
    }
    await deletePlugin(pluginId);
    await deleteGatewayRoute(routeId);
    await deleteGatewayService(serviceId);
  });
});
