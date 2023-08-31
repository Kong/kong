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
  deleteGatewayService,
  deleteGatewayRoute,
  deleteConsumer,
  deleteConsumerGroup,
  postNegative,
  logResponse,
  createPlugin,
  deletePlugin,
  getNegative,
  waitForConfigRebuild,
} from '@support';

describe('Plugin Scope Precedence Model', () => {
  const url = `${getBasePath({
    environment: Environment.gateway.admin,
  })}`;
  const proxyUrl = getBasePath({
    environment: Environment.gateway.proxy,
  });
  let serviceId;
  let routeId;
  let consumerId;
  let consumerGroupId;
  let basicAuthPluginId;
  let pluginIdList;

  // array containing each scope array in order of precedence
  const scopes = [
    ['consumer', 'route', 'service'],
    ['consumer_group', 'service', 'route'],
    ['consumer', 'route'],
    ['consumer', 'service'],
    ['consumer_group', 'route'],
    ['consumer_group', 'service'],
    ['route', 'service'],
    ['consumer'],
    ['consumer_group'],
    ['route'],
    ['service'],
    ['global'],
  ];

  const scopesConsumerGroups = scopes.filter((scope) => {
    return scope.includes('consumer_group');
  });

  const scopesOther = scopes.filter((scope) => {
    return !scope.includes('consumer_group');
  });

  before(async function () {
    const service = await createGatewayService('PrecedenceService');
    serviceId = service.id;
    const route = await createRouteForService(serviceId, ['/precedence_test']);
    routeId = route.id;
    const consumer = await createConsumer();
    consumerId = consumer.id;
    const consumerGroup = await createConsumerGroup('PrecedenceGroup');
    consumerGroupId = consumerGroup.id;
    await addConsumerToConsumerGroup(consumerId, consumerGroupId);

    // set up basic-auth plugin and add credentials for consumer
    const basicAuthPlugin = await createPlugin({
      name: 'basic-auth',
      service: { id: serviceId },
    });
    basicAuthPluginId = basicAuthPlugin.id;

    await axios({
      url: `${url}/consumers/${consumerId}/basic-auth`,
      method: 'post',
      data: {
        username: 'test',
        password: 'test',
      },
    });

    await waitForConfigRebuild();
  });

  function buildPayload(scope) {
    const payload = {
      name: 'request-transformer-advanced',
      config: {
        add: {
          headers: [`x-test-header:${scope}`],
        },
      },
    };
    if (scope.includes('global')) {
      return payload;
    } else {
      if (scope.includes('consumer')) {
        payload['consumer'] = {
          id: consumerId,
        };
      }
      if (scope.includes('consumer_group')) {
        payload['consumer_group'] = {
          id: consumerGroupId,
        };
      }
      if (scope.includes('route')) {
        payload['route'] = {
          id: routeId,
        };
      }
      if (scope.includes('service')) {
        payload['service'] = {
          id: serviceId,
        };
      }
      return payload;
    }
  }

  async function deletePlugins(idArray) {
    if (!idArray) return;
    idArray.map(async (id) => {
      if (id) await deletePlugin(id);
    });

    await waitForConfigRebuild();
  }

  it('should check that consumer group exists', async function () {
    const resp = await getNegative(`${url}/consumer_groups/${consumerGroupId}`);
    expect(resp.status, 'Status should be 200').equal(200);
    expect(resp.data.consumer_group.name).equal('PrecedenceGroup');
  });

  scopesConsumerGroups.forEach(async (scopeConsumer) => {
    scopesOther.forEach(async (scopeOther) => {
      const firstScope =
        scopes.indexOf(scopeConsumer) < scopes.indexOf(scopeOther)
          ? scopeConsumer
          : scopeOther;
      const secondScope =
        firstScope === scopeConsumer ? scopeOther : scopeConsumer;

      // these tests should be run manually upon release rather than in CI
      it.skip(`should check that ${firstScope} takes precedence over ${secondScope}`, async function () {
        const firstPayload = buildPayload(firstScope);
        const secondPayload = buildPayload(secondScope);

        const respFirst = await postNegative(`${url}/plugins`, firstPayload);
        expect(respFirst.status, 'Status should be 201').equal(201);
        const firstPluginId = respFirst.data.id;

        const respSecond = await postNegative(`${url}/plugins`, secondPayload);
        expect(respSecond.status, 'Status should be 201').equal(201);
        const secondPluginId = respSecond.data.id;

        pluginIdList = [firstPluginId, secondPluginId];

        await waitForConfigRebuild();

        const resp = await getNegative(`${proxyUrl}/precedence_test`, {
          authorization: `Basic ${Buffer.from('test:test').toString('base64')}`,
        });

        expect(resp.status, 'Status should be 200').equal(200);

        expect(resp.data.headers['X-Test-Header']).equal(firstScope.join(','));
      });
    });
  });

  it('should create one plugin with each scope and ensure [consumer, route, service] takes precedence', async function () {
    // create list comprehension of payloads for each scope
    const payloads = scopes.map((scope) => {
      return buildPayload(scope);
    });

    // create plugins for each scope
    payloads.map(async (payload) => {
      pluginIdList.push((await createPlugin(payload)).id);
      const resp = await postNegative(`${url}/plugins`, payload);
      expect(resp.status, 'Status should be 201').equal(201);
    });

    await waitForConfigRebuild();

    const resp = await getNegative(`${proxyUrl}/precedence_test`, {
      authorization: `Basic ${Buffer.from('test:test').toString('base64')}`,
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').equal(200);
    expect(resp.data.headers['X-Test-Header']).equal('consumer,route,service');
  });

  // select 3 indices from scopes array at random
  const randomIndices: number[] = [];
  while (randomIndices.length < 3) {
    const randomIndex = Math.floor(Math.random() * scopes.length);
    if (!randomIndices.includes(randomIndex)) {
      randomIndices.push(randomIndex);
    }
  }

  const randomScopes = randomIndices.map((index) => {
    return scopes[index];
  });

  it(`should create 3 plugins with scopes: [${randomScopes[0]}], [${randomScopes[1]}], [${randomScopes[2]}] and ensure correct precedence`, async function () {
    // create list comprehension of payloads for each scope
    const payloads = randomScopes.map((scope) => {
      return buildPayload(scope);
    });

    // create plugins for each scope
    payloads.map(async (payload) => {
      pluginIdList.push((await createPlugin(payload)).id);
      const resp = await postNegative(`${url}/plugins`, payload);
      expect(resp.status, 'Status should be 201').equal(201);
    });

    await waitForConfigRebuild();

    const resp = await getNegative(`${proxyUrl}/precedence_test`, {
      authorization: `Basic ${Buffer.from('test:test').toString('base64')}`,
    });
    expect(resp.status, 'Status should be 200').equal(200);
    // first scope in list is the one with highest precedence
    expect(resp.data.headers['X-Test-Header']).equal(`${randomScopes[0]}`);
  });

  afterEach(async function () {
    await deletePlugins(pluginIdList);
    pluginIdList = [];
  });

  after(async function () {
    await deleteGatewayRoute(routeId);
    await deleteGatewayService(serviceId);
    await deleteConsumer(consumerId);
    await deleteConsumerGroup(consumerGroupId);
    await deletePlugin(basicAuthPluginId);
  });
});
