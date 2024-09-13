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
  clearAllKongResources,
  queryAppdynamicsMetrics,
  randomString,
  createConsumer,
  createKeyAuthCredentialsForConsumer,
  wait,
  checkGwVars,
  checkForArm64
} from '@support'


(checkForArm64() ? describe.skip : describe)('Gateway Plugins: AppDynamics', function () {
  let serviceName = randomString()
  let consumerName = randomString()

  const consumerServiceName = randomString()
  const nonScopedConsumerName = randomString()
  const routeName = 'appD-route'
  const routePath = '/app-dynamics'
  const appName = 'SDET'

  let serviceId: string
  let consumerServiceId: string
  let routeId: string
  let consumerId: string
  let nonScopedConsumerId: string
  let pluginId: string
  let url: string
  let proxyUrl: string
  let pluginPayload: object
  let apiKeyScoped: string
  let apiKeyUnscoped: string

  const sendRequestsAndReturnLastResp = async function (numRequests, key) {
    let resp
    for (let i = 0; i < numRequests; i++) {
      // eslint-disable-next-line no-restricted-syntax
      await wait(2000)
      resp = await axios({
        method: 'get',
        // if key is not an empty object, add key to the URL
        url: `${proxyUrl}${routePath}`,
        headers: key != '' ? {apiKey: key} : {},
        validateStatus: null,
      });
      logResponse(resp)

      expect(resp.status, 'Status should be 200').to.equal(200)
    }
    return resp
  }

  before(async function () {
    checkGwVars('app_dynamics')

    url = `${getBasePath({
      environment: isGateway() ? Environment.gateway.admin : undefined,
    })}`;
    proxyUrl = `${getBasePath({
      app: 'gateway',
      environment: Environment.gateway.proxy,
    })}`;

    const service = await createGatewayService(serviceName)
    serviceId = service.id
    serviceName = service.name
    const route = await createRouteForService(serviceId, [routePath], { name: routeName})
    routeId = route.id
    const consumerService = await createGatewayService(consumerServiceName)
    consumerServiceId = consumerService.id
    const consumer = await createConsumer(consumerName)
    consumerId = consumer.id
    consumerName = consumer.username
    const nonScopedConsumer = await createConsumer(nonScopedConsumerName)
    nonScopedConsumerId = nonScopedConsumer.id    

    const pluginResp = await axios({
      method: 'post',
      url: `${url}/services/${consumerServiceId}/plugins`,
      data: {
        name: 'key-auth-enc',
      },
    });
    logResponse(pluginResp);
    expect(pluginResp.status, 'Status should be 201').to.equal(201);

    const keyAuth = await createKeyAuthCredentialsForConsumer(consumerId)
    apiKeyScoped = keyAuth.key
    const keyAuthUnscoped = await createKeyAuthCredentialsForConsumer(nonScopedConsumerId)
    apiKeyUnscoped = keyAuthUnscoped.key

    pluginPayload = {
      name: 'app-dynamics', 
      service: {
        id: serviceId,
      },
      route: {
        id: routeId,
      }, 
    }
  });

  it('should create the app-dynamics plugin successfully', async function () {
    const resp = await axios({
      method: 'post',
      url: `${url}/plugins`,
      data: pluginPayload,
      validateStatus: null,
    });
    logResponse(resp)
    expect(resp.status, 'Status should be 201').to.equal(201)
    pluginId = resp.data.id

    await waitForConfigRebuild({ proxyReqHeader: { 'apiKey': apiKeyScoped } })
  });

  //skip until we renew app dynamics license. Progress tracked at https://konghq.atlassian.net/browse/KAG-5367
  it.skip('should send request and see the Singularityheader when AppDynamics plugin is enabled', async function () {
    let resp;

    // send 150 requests to seed data for the plugin
    // it appears the Sigularityheader is not always present in the first 5 requests, so try 30 times
    for (let i = 0; i < 100; i++) {
      // eslint-disable-next-line no-restricted-syntax
      resp = await sendRequestsAndReturnLastResp(5, '')

      if (resp.data.headers.Singularityheader) {
        break
      }    
    }

    expect(resp.data.headers.Singularityheader, 'Should see the Singularityheader').to.exist
  });

  // skipping until we can set up mocking
  // TODO: mock appdynamics response
  it.skip('should be able to access app-dynamics metrics', async function () {
    await queryAppdynamicsMetrics(serviceName, appName, 5)
  });

  it('should scope plugin to consumer', async function() {
    const resp = await axios({
      method: 'patch',
      url: `${url}/plugins/${pluginId}`,
      data: {
        consumer: {
          id: consumerId,
        },
        service: {
          id: consumerServiceId,
        },
      },
    })
    logResponse(resp)

    await waitForConfigRebuild({ proxyReqHeader: { 'apiKey': apiKeyScoped } })
  })

  // skipping next 3 tests until https://konghq.atlassian.net/browse/KAG-3803 is resolved
  it.skip('should send requests as scoped consumer and see Singularityheader', async function () {
    const resp = await sendRequestsAndReturnLastResp(5, apiKeyScoped)
    expect(resp.data.headers.Singularityheader, 'Should see the Singularityheader').to.exist
  })


  it.skip('should send requests as different consumer and not see Singularityheader', async function () {
    const resp = await sendRequestsAndReturnLastResp(5, apiKeyUnscoped)
    logResponse(resp)

    expect(resp.status, 'Status should be 200').to.equal(200)
    expect(resp.data.headers, 'Should not see the Singularityheader').to.not.have.property('Singularityheader')
  })

  it.skip('should see data only from the scoped consumer in AppDynamics', async function () {
    // although 10 total requests were sent under this service, only 5 should appear
    await queryAppdynamicsMetrics(consumerServiceId, appName, 5)
  })

  it('should delete the app-dynamics plugin', async function () {
    const resp = await axios({
      method: 'delete',
      url: `${url}/plugins/${pluginId}`,
    })
    logResponse(resp)

    expect(resp.status, 'Status should be 204').to.equal(204)
  })

  after(async function () {
    await clearAllKongResources()
  })
})
