import axios from 'axios';
import {
  createGatewayService,
  createRouteForService,
  Environment,
  expect,
  getBasePath,
  logResponse,
  waitForConfigRebuild,
  isGateway,
  queryPrometheusMetrics,
  getAllMetrics,
  eventually,
  isGwHybrid,
  createConsumer,
  createBasicAuthCredentialForConsumer,
  clearAllKongResources,
  createPlugin,
  createUpstream,
  updateGatewayService,
  addTargetToUpstream,
  deletePlugin,
  isGwNative,
  deleteConsumer,
  reloadGateway
} from '@support';


describe('Gateway Plugins: Prometheus', function () {
  const serviceName = 'prometheus-service';
  const routeName = 'prometheus-route';
  const routePath = '/api-prom'
  const upstreamName = 'httpbinUpstream'
  const target = 'httpbin:80'
  const targetStates = ['healthchecks_off', 'dns_error', 'healthy', 'unhealthy']

  let serviceId: string;
  let routeId: string;
  let pluginId: string;
  let url: string;
  let proxyUrl: string;
  let consumer: any;
  let pluginPayload: object;
  let base64credentials: string;
  let upstreamId: string;
  let basicAuthPluginId: string;

  before(async function () {
    url = `${getBasePath({
      environment: isGateway() ? Environment.gateway.admin : undefined,
    })}`;
    proxyUrl = `${getBasePath({
      app: 'gateway',
      environment: Environment.gateway.proxy,
    })}`;

    const service = await createGatewayService(serviceName);
    serviceId = service.id;
    const route = await createRouteForService(serviceId, [routePath], { name: routeName});
    routeId = route.id;
    const upstream = await createUpstream(upstreamName)
    upstreamId = upstream.id
    await addTargetToUpstream(upstreamId, target)

    const consumerReq = await createConsumer();
    consumer = {
      id: consumerReq.id,
      username: consumerReq.username,
      username_lower: consumerReq.username.toLowerCase(),
    };

    pluginPayload = {
      name: 'prometheus', 
      service: {
        id: serviceId,
      },
      route: {
        id: routeId,
      } 
    }
  });

  it('should see kong metrics in 8100/metrics', async function () {
    const kongData = await getAllMetrics()
    expect(kongData.includes('kong_node_info{node_id='), 'should see kong_node_info in control plane metrics').to.be.true

    if(isGwHybrid()) {
      const kongDpData = await getAllMetrics("dp")
      expect(kongDpData.includes('kong_node_info{node_id='), 'should see kong_node_info in data plane metrics').to.be.true
    }
  });

  it('should see kong_node_info in prometheus without plugin created', async function () {
    const nodeData = await queryPrometheusMetrics('kong_node_info')

    for(const result of nodeData.result) {
      // response differs for classic and hybrid modes as well as during package tests
      if(isGwHybrid() && result.metric.instance.includes('dp')) {
        expect(result.metric.job, "should see kong data plane job in prometheus metrics").to.equal('kong-dp1')
        expect(result.metric.version, "should see kong version in data plane prometheus metrics").to.be.string
      } else {
        expect(result.metric.job, "should see kong control plane job in prometheus metrics").to.equal('kong-cp')
        expect(result.metric.version, "should see kong version in control plane prometheus metrics").to.be.string
      }
    }
  });

  it('should create the prometheus plugin', async function () {
    const resp = await axios({
      method: 'post',
      url: `${url}/plugins`,
      data: pluginPayload,
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 201').to.equal(201);
    pluginId = resp.data.id;

    await waitForConfigRebuild();
  });

  it('should see kong_db_entities_total metric after enabling prometheus plugin', async function () {
    await eventually(async () => {
      let resp: any
      // the initial metrics differ in case of traditional and hybrid gateway modes
      // here we assert that a metric exists which is unique to each gateway mode
      if(isGwHybrid()) {
        resp = await queryPrometheusMetrics('kong_data_plane_version_compatible')
      } else {
        resp = await queryPrometheusMetrics('kong_db_entities_total')
      }

      expect(JSON.parse(resp.result[0].value[1]), 'should kong_db_entities_total number').to.be.gte(1)
    });
  });

  it('should see kong_enterprise_license_features metric after enabling prometheus plugin', async function () {
    await eventually(async () => {
      const resp = await queryPrometheusMetrics('kong_enterprise_license_features')
      expect(resp.result.length).to.equal(2)
      expect(resp.result[0].metric.feature).to.equal("ee_entity_read")
      expect(resp.result[1].metric.feature).to.equal("ee_entity_write")
    });
  });

  it('should enable the prometheus plugin latency_metrics', async function () {
    pluginPayload = { ...pluginPayload, config: { latency_metrics: true } }

    let resp = await axios({
      method: 'put',
      url: `${url}/plugins/${pluginId}`,
      data: pluginPayload
    });
    logResponse(resp);
    
    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.config.latency_metrics, 'should see latency_metrics enabled').to.be.true
    await waitForConfigRebuild();

    // send request to upstream to log request latency metrics
    resp = await axios(`${proxyUrl}/${routePath}`)
    logResponse(resp);
    expect(resp.status, 'Status should be 200').to.equal(200);
  });

  ['kong_kong_latency_ms_count', 'kong_request_latency_ms_count', 'kong_upstream_latency_ms_count', 'kong_kong_latency_ms_bucket', 'kong_request_latency_ms_bucket', 'kong_upstream_latency_ms_bucket'].forEach((metric) => {
    it(`should see the new ${metric} metric after request to upstream`, async function () {
      await eventually(async () => {
        const resp = await queryPrometheusMetrics(metric)
        expect(resp.result[0].metric.service, 'should see correct service name in metrics').to.equal(serviceName)

        if(metric.includes("bucket")) {
          expect(resp.result.length, 'should see multiple latency metadata for buckets').to.be.gte(12)
        } else {
          expect(JSON.parse(resp.result[0].value[1]), 'should see the value of count').to.be.gte(1)
        }
      });
    });
  })

  it('should enable the prometheus plugin bandwidth_metrics', async function () {
    pluginPayload = { ...pluginPayload, config: { bandwidth_metrics: true } }

    const resp = await axios({
      method: 'put',
      url: `${url}/plugins/${pluginId}`,
      data: pluginPayload
    });
    logResponse(resp);
    
    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.config.bandwidth_metrics, 'should see bandwidth_metrics enabled').to.be.true
    await waitForConfigRebuild();
  });

  it(`should see the new kong_bandwidth_bytes metric after request to upstream`, async function () {
    // send request to upstream to log request bandwidth_metrics
    const resp = await axios(`${proxyUrl}/${routePath}`)
    logResponse(resp);
    expect(resp.status, 'Status should be 200').to.equal(200);

    await eventually(async () => {
      const resp = await queryPrometheusMetrics('kong_bandwidth_bytes')
      expect(resp.result.length, 'should see 2 bandwidth results').to.be.gte(2)
      expect(JSON.parse(resp.result[0].value[1]), 'should see bandwidth value').to.be.gte(1)

      resp.result.some((result) => {
        expect(result.metric.route, 'should see correct route name').to.equal(routeName)
        expect(result.metric.service, 'should see correct service name').to.equal(serviceName)
      })
    });
  });

  // skipped due to https://konghq.atlassian.net/browse/KAG-3332
  it.skip(`should see the new kong_stream_session_total bandwidth metric after request to upstream`, async function () {
    await eventually(async () => {
      const resp = await queryPrometheusMetrics('kong_stream_session_total')
      expect(resp.result.length, 'should see stream_session_total results').to.be.gte(2)
    });
  });

  it('should enable the prometheus plugin status_code_metrics', async function () {
    pluginPayload = { ...pluginPayload, config: { status_code_metrics: true } }

    const resp = await axios({
      method: 'put',
      url: `${url}/plugins/${pluginId}`,
      data: pluginPayload
    });
    logResponse(resp);
    
    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.config.status_code_metrics, 'should see status_code_metrics enabled').to.be.true
    await waitForConfigRebuild();
  });

  it(`should see the new kong_http_requests_total metric after requests to upstream`, async function () {
    // send requests to upstream to log request status_code_metrics
    for(let i = 1; i <= 2; i++) {
      const resp = await axios(`${proxyUrl}/${routePath}`)
      logResponse(resp);
      expect(resp.status, 'Status should be 200').to.equal(200);
    }

    const totalValues = new Set()

    await eventually(async () => {
      const resp = await queryPrometheusMetrics('kong_http_requests_total')
      resp.result.forEach((result) => {
        totalValues.add(result.value[1])
      })
    });

    // expecting at least 2 total requests as we have made 2 requests after enabling the status_code_metrics
    // the below assertion is made dynamic, meaning if you rerun the test it will find a total greater than 2 from all values
    const totalExists = Array.from(totalValues).some((value) => Number(value) >= 2)
    expect(totalExists, 'should see correct kong_http_requests_total value').to.be.true
  });

  // 
  // TODO add a test for stream_session_total (status_code_metrics) metric after the issue in kong is resolved and metric is exported
  // https://konghq.atlassian.net/browse/KAG-3332
  // 

  it('should enable the prometheus plugin per_consumer metric', async function () {
    // Note that for per_consumer metric to work we need status_code_metrics and bandwidth_metrics enabled as well
    // This is required for kong_http_requests_total and kong_bandwidth_bytes metrics to be exported so that per_consumer can fill consumer label in these
    pluginPayload = { ...pluginPayload, consumer: { id: consumer.id }, config: { status_code_metrics: true, per_consumer: true,  bandwidth_metrics: true } }

    let resp = await axios({
      method: 'put',
      url: `${url}/plugins/${pluginId}`,
      data: pluginPayload
    });
    logResponse(resp);
    
    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.config.status_code_metrics, 'should see status_code_metrics enabled').to.be.true
    expect(resp.data.config.per_consumer, 'should see per_consumer enabled').to.be.true
    expect(resp.data.config.bandwidth_metrics, 'should see bandwidth_metrics enabled').to.be.true

    // create basic-auth plugin for consumer
    const basicAuthResp = await createPlugin({ name: 'basic-auth' });
    basicAuthPluginId = basicAuthResp.id;

    await createBasicAuthCredentialForConsumer(
      consumer.id,
      consumer.username,
      consumer.username
    );

    // base64 encode credentials
    base64credentials = Buffer.from(
      `${consumer.username}:${consumer.username}`
    ).toString('base64');

    await waitForConfigRebuild();

    // send requests to upstream to log request upstream_target_health
    resp = await axios({
      url: `${proxyUrl}/${routePath}`,
      headers: {
        Authorization: `Basic ${base64credentials}`,
      },
    })
  
    logResponse(resp);
    expect(resp.status, 'Status should be 200').to.equal(200);
  });


  ['kong_http_requests_total', 'kong_bandwidth_bytes'].forEach((metric) => {
    it(`should see consumer label added in ${metric} metric`, async function () {
      let foundMatch = false

      await eventually(async () => {
        const resp = await queryPrometheusMetrics(metric)
        resp.result.some((result) => {
          if(result.metric.consumer === consumer.username) {
            foundMatch = true
          }
        })
        expect(foundMatch, `should see correct consumer label in ${metric} metric`).to.be.true
      });
    });
  })

  // 
  // TODO find a way to make the below tests less flkay, currently they fail often
  // Enable test run for native gateway after https://konghq.atlassian.net/browse/KAG-3333 is resolved
  // 

  if(!isGwNative()) {
    it.skip('should enable the prometheus plugin upstream_health_metrics', async function () {
      pluginPayload = { ...pluginPayload, consumer: null, config: { upstream_health_metrics: true } }

      // change service host to point to upstream
      const serviceResp = await updateGatewayService(serviceId, {  host: upstreamName, path: null  })
      expect(serviceResp.host, 'Should have upstream as service host').to.equal(upstreamName);
  
      const resp = await axios({
        method: 'put',
        url: `${url}/plugins/${pluginId}`,
        data: pluginPayload
      });
      logResponse(resp);
      
      expect(resp.status, 'Status should be 200').to.equal(200);
      expect(resp.data.config.upstream_health_metrics, 'should see upstream_health_metrics enabled').to.be.true

      // delete basic-auth plugin and consumer
      await deletePlugin(basicAuthPluginId)
      await deleteConsumer(consumer.id)
      // for the kong_upstream_target_health metric to start appear and avoid flakiness
      reloadGateway()
      await waitForConfigRebuild();
    });
  
    it.skip(`should see the new kong_upstream_target_health metric after requests to upstream`, async function () {
      // send request to upstream to log the request's upstream_target_health metric
      for(let i = 1; i <= 2; i++) {
        const resp = await axios({
          url: `${proxyUrl}/${routePath}`
        })
        logResponse(resp);
        expect(resp.status, 'Status should be 200').to.equal(200);
      }
  
      const promTargetResults = new Set()
    
      await eventually(async () => {
        const resp = await queryPrometheusMetrics('kong_upstream_target_health')
        expect(resp.result.length, 'should see 4 results for target health').to.be.gte(4)
        expect(resp.result[0].metric.upstream, 'should see correct upstream name in metrics').to.equal(upstreamName)
        expect(resp.result[0].metric.target, 'should see correct target address').to.equal(target)
      
        resp.result.forEach((result) => {
          promTargetResults.add(result.metric.state)
        })
      });
  
      targetStates.every((state) => {
        expect(promTargetResults.has(state), `Should see ${state} state in the target health array`).to.be.true
      })
    });
  }

  it('should delete the prometheus plugin', async function () {
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
