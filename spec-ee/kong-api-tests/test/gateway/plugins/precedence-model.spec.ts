import axios from 'axios';
import {
  Environment,
  expect,
  getBasePath,
  createGatewayService,
  createRouteForService,
  addConsumerToConsumerGroup,
  createConsumer,
  createConsumerGroup,
  logResponse,
  createPlugin,
  isGateway,
  waitForConfigRebuild,
  clearAllKongResources,
} from '@support';

describe('Plugin Scope Precedence Model', () => {
  const url = `${getBasePath({
    environment: isGateway() ? Environment.gateway.admin : undefined,
  })}`;
  const proxyUrl = getBasePath({
    app: 'gateway',
    environment: Environment.gateway.proxy,
  });
  let serviceId
  let routeId
  let consumerId
  let consumerGroupId

  function buildPayload(scope) {
    const payload = {
      name: 'request-transformer-advanced',
      config: {
        append: {
          headers: [`x-test-header:${scope}`],
        },
      },
    };
    if (scope.includes('global')) {
      return payload;
    } else {
      if (scope.includes('consumer')) {
        payload['consumer'] = { id: consumerId };
      }
      if (scope.includes('consumer_group')) {
        payload['consumer_group'] = { id: consumerGroupId };
      }
      if (scope.includes('route')) {
        payload['route'] = { id: routeId };
      }
      if (scope.includes('service')) {
        payload['service'] = { id: serviceId };
      }
      return payload
    }
  }

  before(async function () {
    const service = await createGatewayService('PrecedenceService')
    serviceId = service.id
    const route = await createRouteForService(serviceId, ['/precedence_test'])
    routeId = route.id
    const consumer = await createConsumer()
    consumerId = consumer.id
    const consumerGroup = await createConsumerGroup('PrecedenceGroup')
    consumerGroupId = consumerGroup.id
    await addConsumerToConsumerGroup(consumerId, consumerGroupId);

    // set up basic-auth plugin and add credentials for consumer
    await createPlugin({ name: 'basic-auth' });

    await axios({
      url: `${url}/consumers/${consumerId}/basic-auth`,
      method: 'post',
      data: {
        username: 'test',
        password: 'test',
      },
    });
    
    await waitForConfigRebuild()
  });

  it('should check that consumer group exists', async function () {
    const resp = await axios.get(`${url}/consumer_groups/${consumerGroupId}`)
    logResponse(resp)
    expect(resp.status, 'Status should be 200').equal(200)
    expect(resp.data.consumer_group.name).equal('PrecedenceGroup')
  });

  it(`should check that route scope takes precedence over global scope`, async function () {
    await createPlugin(buildPayload(['route']))
    await createPlugin(buildPayload(['global']))
    await waitForConfigRebuild()

    const resp = await axios.get(`${proxyUrl}/precedence_test`, {headers: {authorization: `Basic ${Buffer.from('test:test').toString('base64')}`}})

    logResponse(resp)
    expect(resp.status, 'Status should be 200').equal(200)
    expect(resp.data.headers['X-Test-Header']).contain('route')
  });

  it('should check that consumer_group scope takes precedence over route scope', async function () {
    // create consumer_group scoped plugin
    await createPlugin(buildPayload(['consumer_group']))
    await waitForConfigRebuild()

    const resp = await axios.get(`${proxyUrl}/precedence_test`, {headers: {authorization: `Basic ${Buffer.from('test:test').toString('base64')}`}})

    expect(resp.status, 'Status should be 200').equal(200)
    expect(resp.data.headers['X-Test-Header']).equal('consumer_group')
  })

  it('should check that consumer scope takes precedence over consumer_group scope', async function () {
    // create consumer scoped plugin
    await createPlugin(buildPayload(['consumer']))
    await waitForConfigRebuild()

    const resp = await axios.get(`${proxyUrl}/precedence_test`, {headers: {authorization: `Basic ${Buffer.from('test:test').toString('base64')}`}})

    expect(resp.status, 'Status should be 200').equal(200)
    expect(resp.data.headers['X-Test-Header']).equal('consumer')
  })

  it('should check that 2-entity scope takes precedence over single-entity scope', async function () {
    // create consumer_group and service scoped plugin
    await createPlugin(buildPayload(['consumer_group', 'service']))
    await waitForConfigRebuild()

    const resp = await axios.get(`${proxyUrl}/precedence_test`, {headers: {authorization: `Basic ${Buffer.from('test:test').toString('base64')}`}})

    expect(resp.status, 'Status should be 200').equal(200)
    expect(resp.data.headers['X-Test-Header']).equal('consumer_group,service')
  })

  it('should check that 3-entity scope takes precedence over 2-entity scope', async function () {
    // create consumer, route, and service scoped plugin
    await createPlugin(buildPayload(['consumer', 'route', 'service']))
    await waitForConfigRebuild()

    const resp = await axios.get(`${proxyUrl}/precedence_test`, {headers: {authorization: `Basic ${Buffer.from('test:test').toString('base64')}`}})

    expect(resp.status, 'Status should be 200').equal(200)
    expect(resp.data.headers['X-Test-Header']).equal('consumer,route,service')
  })

  after(async function () {
    await clearAllKongResources();
  })
})