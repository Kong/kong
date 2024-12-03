/* eslint-disable no-prototype-builtins */
import axios from 'axios';
import {
  expect,
  Environment,
  getBasePath,
  createGatewayService,
  randomString,
  logResponse,
  createRouteForService,
  isGateway,
  clearAllKongResources,
  postNegative,
  getNegative,
  eventually,
  waitForConfigRebuild
} from '@support';

describe('Gateway Plugins: DeGraphQL', function () {
  const degraphqlEndpoint = 'http://graphql-server:4000';
  const routePath = '/testdegraphql';
  const simpleQuery = 'query { categories { id speciesType beasts { id commonName legs } } }';
  const complexQuery = 'query($categoryId: String!, $id: String!) {beast(categoryId: $categoryId, id: $id) {\
                        id \
                        commonName \
                        binomial \
                        legs\
                        } \
                      }';
  const url = `${getBasePath({
    environment: isGateway() ? Environment.gateway.admin : undefined,
  })}`;

  const proxyUrl = `${getBasePath({
    app: 'gateway',
    environment: Environment.gateway.proxy,
  })}`;

  let serviceId: string;
  let routeId: string;
  let pluginId: string;

  before(async function () {
    const service = await createGatewayService(randomString(), {
        url: degraphqlEndpoint,
      });
    serviceId = service.id;
    const route = await createRouteForService(serviceId, [routePath]);
    routeId = route.id;
  });

  it('should not proxy the traffic without plugin enabled', async function () {
    await eventually(async () => {
      const resp = await getNegative(`${proxyUrl}${routePath}`);
      logResponse(resp);
      expect(resp.status, 'Status should be 400').to.equal(400);
    });
  });

  it('should not create degraphql plugin with incorrect configs', async function () {
    const pluginPayload = {
      name: 'degraphql',
      route: {
        id: routeId,
      },
      config: {
        graphql_server_path: 'invalid_path', // invalid path                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 1
      },
    };

    const resp = await postNegative(`${url}/plugins`, pluginPayload);
    logResponse(resp);

    expect(resp.status, 'Status should be 400').to.equal(400);
    expect(resp.data.message, 'Should have correct error message').to.contain(
      "schema violation (config.graphql_server_path: should start with: /)"
    );
  });

  it('should create degraphql plugin with correct configs', async function () {
    const pluginPayload = {
      name: 'degraphql',
      route: {
        id: routeId,
      },
      config: {
        graphql_server_path: '/graphql', // valid path                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 1
      },
    };

    const resp = await axios({
      method: 'post',
      url: `${url}/plugins`,
      data: pluginPayload,
    });
    logResponse(resp);

    pluginId = resp.data.id;
    expect(resp.status, 'Status should be 201').to.equal(201);
  });

  it('should configure DeGraphQL routes on the service', async function () {
    await eventually(async () => {
        const resp = await axios({
            method: 'post',
            url: `${url}/services/${serviceId}/degraphql/routes`,
            data: { 
              uri: '/test',
              query: simpleQuery },
            headers: {
              'Content-Type': 'application/json',
            },
          });
        logResponse(resp);
        expect(resp.status, 'Status should be 201').to.equal(201);
    });

    await waitForConfigRebuild();
  });

  it('should proxy DeGraphQL routes on the service', async function () {
    await eventually(async () => {
        const resp = await axios({
          url: `${proxyUrl}${routePath}/test`
        });
        logResponse(resp);
    
        expect(resp.status, 'Status should be 200').to.equal(200);
        expect(resp.data.data.categories, 'Should include expected data').to.have.length(3);
    });
  });

it('should be able to disable degraphql plugin', async function () {
  const resp = await axios({
    method: 'patch',
    url: `${url}/plugins/${pluginId}`,
    data: {
      enabled: false,
    },
  });
  logResponse(resp);

  expect(resp.status, 'Status should be 200').to.equal(200);
  expect(resp.data.enabled, 'Should be false').to.be.false;
});

it('should not proxy DeGraphQL routes when plugin is disabled', async function () {
  await eventually(async () => {
      const resp = await getNegative(`${proxyUrl}${routePath}/test`);
      logResponse(resp);

      expect(resp.status, 'Status should be 400').to.equal(400);
  });
});

it('should proxy DeGraphQL routes again on the service after plugin is re-enabled', async function () {
  await eventually(async () => {
    const resp = await axios({
      method: 'patch',
      url: `${url}/plugins/${pluginId}`,
      data: {
        enabled: true,
      },
    });
    logResponse(resp);
  
    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.enabled, 'Should be true').to.be.true;
  });

  await waitForConfigRebuild();

  await eventually(async () => {
      const resp = await axios({
        url: `${proxyUrl}${routePath}/test`
      });
      logResponse(resp);
  
      expect(resp.status, 'Status should be 200').to.equal(200);
      expect(resp.data.data.categories, 'Should include expected data').to.have.length(3);
  });
});

it('should be able to add query variables to URIs', async function () {
  await eventually(async () => {
        const resp = await axios({
            method: 'post',
            url: `${url}/services/${serviceId}/degraphql/routes`,
            data: { 
              uri: '/beast/:categoryId/:id',
              query: complexQuery },
            headers: {
              'Content-Type': 'application/json',
            },
          });

        logResponse(resp);
  });

  await waitForConfigRebuild();
});

it('should proxy DeGraphQL routes with multiple variable', async function () {
  await eventually(async () => {
      const resp = await axios({
        url: `${proxyUrl}${routePath}/beast/insects/md`
      });
      logResponse(resp);

      expect(resp.status, 'Status should be 200').to.equal(200);
      expect(resp.data.data.beast.id, 'Should have correct data').to.equal('md');
  });
});
 
it('should not return anything when the variable is not in the query', async function () {
  await eventually(async () => {
      const resp = await getNegative(`${proxyUrl}${routePath}/beast/insects`);
      logResponse(resp);

      expect(resp.status, 'Status should be 404').to.equal(404);
      expect(resp.data.message, 'Should have correct error message').to.equal(
        'Not Found'
      );
  });
});

it('should not proxy DeGraphQL routes with wrong multiple variable', async function () {
  await eventually(async () => {
      const resp = await axios({
        url: `${proxyUrl}${routePath}/beast/invalid/md`
      });
      logResponse(resp);

      expect(resp.status, 'Status should be 200').to.equal(200);
      expect(resp.data.data.beast, 'Should return null as data').to.be.null;
  });
});


it('should proxy DeGraphQL routes when query with GET arguments', async function () {
  await eventually(async () => {
    const resp = await axios({
        method: 'post',
        url: `${url}/services/${serviceId}/degraphql/routes`,
        data: { 
          uri: '/beast',
          query: complexQuery },
        headers: {
          'Content-Type': 'application/json',
        },
      });
      logResponse(resp);
  });

  await waitForConfigRebuild();

  await eventually(async () => {
      const resp = await axios({
        url: `${proxyUrl}${routePath}/beast?categoryId=insects&id=md`
      });
      logResponse(resp);

      expect(resp.status, 'Status should be 200').to.equal(200);
      expect(resp.data.data.beast.id, 'Should have correct data').to.equal('md');
  });
});

it('should not proxy DeGraphQL routes when query with wrong GET arguments', async function () {
  await eventually(async () => {
      const resp = await getNegative(`${proxyUrl}${routePath}/beast?categoryId=test&id=md&legs=4`);
      logResponse(resp);

      expect(resp.status, 'Status should be 200').to.equal(200);
      expect(resp.data.data.beast, 'Should return null as data').to.be.null;
  });
});

it('should return 400 for additional routes created for the same service', async function () {
  await createRouteForService(serviceId, ['/newroute']);

  await eventually(async () => {
      const resp = await getNegative(`${proxyUrl}/newroute/beast?categoryId=insects&id=md`);
      logResponse(resp);

      expect(resp.status, 'Status should be 400').to.equal(400);
  });
});

it('should not proxy traffic after deleting the route', async function () {
  const resp = await axios({
    method: 'delete',
    url: `${url}/services/${serviceId}/routes/${routeId}`,
  });
  expect(resp.status, 'Status should be 204').to.equal(204);

  await eventually(async () => {
      const resp = await getNegative(`${proxyUrl}${routePath}/beast?categoryId=insects&id=md`);
      logResponse(resp);

      expect(resp.status, 'Status should be 404').to.equal(404);
  });
});

after(async function () {
    await clearAllKongResources()
  });
});
