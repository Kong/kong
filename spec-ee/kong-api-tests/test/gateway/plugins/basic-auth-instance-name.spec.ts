import {
  createBasicAuthCredentialForConsumer,
  createConsumer,
  createGatewayService,
  createRouteForService,
  deleteConsumer,
  deleteGatewayRoute,
  deleteGatewayService,
  Environment,
  expect,
  getBasePath,
  getNegative,
  isGateway,
  isGwHybrid,
  logResponse,
  postNegative,
  randomString,
  wait,
} from '@support';
import axios from 'axios';

describe('Gateway Plugins: basic-auth using plugin instance name', function () {
  const path = '/basic-auth';
  const serviceName = 'basic-auth-service';
  const isHybrid = isGwHybrid();
  const hybridWaitTime = 8000;
  const waitTime = 5000;
  const shortWaitTime = 2500;
  const consumerName = 'iggy';
  const basicAuthPassword = randomString();
  const instanceName = 'My-Plugin_720.~';
  const invalidInstanceName = 'MoMonay$$$!';
  const patchInstanceNameOnPlugin = 'Plugin-Patch-My-Plugin_720.~';
  const patchInstanceNameOnService = 'Service-Patch-My-Plugin_720.~';
  const patchInstanceNameOnRoute = 'Route-Patch-My-Plugin_720.~';
  const plugin = 'basic-auth';

  const url = `${getBasePath({
    environment: isGateway() ? Environment.gateway.admin : undefined,
  })}`;
  const proxyUrl = `${getBasePath({
    app: 'gateway',
    environment: Environment.gateway.proxy,
  })}`;

  let serviceId: string;
  let routeId: string;
  let consumerDetails: any;
  let consumerId: string;
  let base64credentials: string;

  let basePayload: any;
  let pluginId: string;

  before(async function () {
    const service = await createGatewayService(serviceName);
    serviceId = service.id;
    const route = await createRouteForService(serviceId, [path]);
    routeId = route.id;
    const consumer = await createConsumer(consumerName);
    consumerId = consumer.id;
    consumerDetails = {
      id: consumer.id,
      username: consumer.username,
    };
    await wait(isHybrid ? hybridWaitTime : waitTime); // eslint-disable-line no-restricted-syntax

    basePayload = {
      name: plugin,
      service: {
        id: serviceId,
      },
      route: {
        id: routeId,
      },
    };
  });

  it('should not enable basic-auth plugin using invalid instance name ', async function () {
    const pluginPayload = {
      ...basePayload,
      instance_name: invalidInstanceName,
    };

    const resp = await postNegative(`${url}/plugins`, pluginPayload);
    logResponse(resp);

    expect(resp.status, 'Status should be 400').to.equal(400);
    expect(resp.data.message, 'Should indicate invalid values supplied').to.eq(
      `schema violation (instance_name: invalid value '${invalidInstanceName}': the only accepted ascii characters are alphanumerics or ., -, _, and ~)`
    );
    expect(
      resp.data.fields.instance_name,
      'Should indicate which field is in violation'
    ).to.eq(
      `invalid value '${invalidInstanceName}': the only accepted ascii characters are alphanumerics or ., -, _, and ~`
    );
    expect(resp.data.name, 'Should indicate schema violation').to.eq(
      'schema violation'
    );
  });

  it('should enable basic-auth plugin using valid instance name', async function () {
    const pluginPayload = {
      ...basePayload,
      instance_name: instanceName,
      config: { anonymous: consumerId },
    };

    const resp = await axios({
      method: 'post',
      url: `${url}/plugins`,
      data: pluginPayload,
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 201').to.equal(201);
    expect(resp.data.instance_name, 'Default value is True').to.eq(
      instanceName
    );

    pluginId = resp.data.id;
    await wait(isHybrid ? hybridWaitTime : waitTime); // eslint-disable-line no-restricted-syntax
  });

  it('should not enable basic-auth plugin if instance name exists', async function () {
    const pluginPayload = {
      name: plugin,
      instance_name: instanceName,
    };

    const resp = await postNegative(`${url}/plugins`, pluginPayload);
    logResponse(resp);

    expect(resp.status, 'Status should be 409').to.equal(409);
    expect(resp.data.message, 'Should indicate a violation').to.eq(
      `UNIQUE violation detected on '{instance_name="${instanceName}"}'`
    );
  });

  it('should provision new credentials for consumer under-test', async function () {
    const resp = await createBasicAuthCredentialForConsumer(
      consumerDetails.id,
      consumerDetails.username,
      basicAuthPassword
    );
    logResponse(resp);

    expect(resp.status, 'Status should be 201').to.equal(201);

    // base64 encode credentials
    base64credentials = Buffer.from(
      `${consumerDetails.username}:${basicAuthPassword}`
    ).toString('base64');

    await wait(isHybrid ? hybridWaitTime : waitTime); // eslint-disable-line no-restricted-syntax
  });

  it('should proxy request using consumer credentials', async function () {
    const validTokenHeaders = {
      Authorization: `Basic ${base64credentials}`,
    };
    const resp = await getNegative(`${proxyUrl}${path}`, validTokenHeaders);
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(
      resp.data.headers.Authorization,
      'Should see credentials in headers'
    ).to.eq(`Basic ${base64credentials}`);
  });

  it('should get plugin using instance name', async function () {
    const resp = await axios({
      method: 'get',
      url: `${url}/plugins/${instanceName}`,
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.name, 'Should equal plugin name (basic-auth) ').to.equal(
      plugin
    );
    expect(
      resp.data.instance_name,
      'Should equal plugin instance name'
    ).to.equal(instanceName);
  });

  it('should get plugin using id', async function () {
    const resp = await axios({
      method: 'get',
      url: `${url}/plugins/${pluginId}`,
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.name, 'Should equal plugin name (basic-auth) ').to.equal(
      plugin
    );
    expect(
      resp.data.instance_name,
      `Should equal plugin instance name`
    ).to.equal(instanceName);
  });

  it('should not get plugin using incorrect instance name', async function () {
    const resp = await getNegative(`${url}/plugins/my-plugin`);
    logResponse(resp);

    expect(resp.status, 'Status should be 404').to.equal(404);
  });

  it('should patch the plugin by updating the instance name', async function () {
    const resp = await axios({
      method: 'patch',
      url: `${url}/plugins/${instanceName}`,
      data: { instance_name: patchInstanceNameOnPlugin },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(
      resp.data.instance_name,
      'Should equal plugin patch instance name'
    ).to.eq(patchInstanceNameOnPlugin);
    await wait(isHybrid ? hybridWaitTime : shortWaitTime); // eslint-disable-line no-restricted-syntax
  });

  it('should get plugin using updated instance name', async function () {
    const resp = await axios(`${url}/plugins/${patchInstanceNameOnPlugin}`);
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.id, 'Should retain existing plugin id').to.eq(pluginId);
    expect(resp.data.name, 'Should equal plugin name (basic-auth) ').to.equal(
      plugin
    );
    expect(
      resp.data.instance_name,
      `Should equal plugin instance name`
    ).to.equal(patchInstanceNameOnPlugin);
  });

  it('should patch the plugin by updating the instance name via the service', async function () {
    const resp = await axios({
      method: 'patch',
      url: `${url}/services/${serviceId}/plugins/${patchInstanceNameOnPlugin}`,
      data: { instance_name: patchInstanceNameOnService },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(
      resp.data.instance_name,
      'Should equal plugin patch instance name'
    ).to.eq(patchInstanceNameOnService);
    await wait(isHybrid ? hybridWaitTime : shortWaitTime); // eslint-disable-line no-restricted-syntax
  });

  it('should get plugin using updated instance name on service', async function () {
    const resp = await axios({
      method: 'get',
      url: `${url}/plugins/${patchInstanceNameOnService}`,
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.id, 'Should retain existing plugin id').to.eq(pluginId);
    expect(resp.data.name, 'Should equal plugin name (basic-auth) ').to.equal(
      plugin
    );
    expect(
      resp.data.instance_name,
      `Should equal plugin instance name`
    ).to.equal(patchInstanceNameOnService);
  });

  it('should patch plugin by updating the instance name via the route', async function () {
    const resp = await axios({
      method: 'patch',
      url: `${url}/routes/${routeId}/plugins/${patchInstanceNameOnService}`,
      data: { instance_name: patchInstanceNameOnRoute },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(
      resp.data.instance_name,
      'Should equal plugin patch instance name'
    ).to.eq(patchInstanceNameOnRoute);
    await wait(isHybrid ? hybridWaitTime : shortWaitTime); // eslint-disable-line no-restricted-syntax
  });

  it('should get plugin using updated instance name on route', async function () {
    const resp = await axios({
      method: 'get',
      url: `${url}/plugins/${patchInstanceNameOnRoute}`,
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.id, 'Should retain existing plugin id').to.eq(pluginId);
    expect(resp.data.name, 'Should equal plugin name (basic-auth) ').to.equal(
      plugin
    );
    expect(
      resp.data.instance_name,
      `Should equal plugin instance name`
    ).to.equal(patchInstanceNameOnRoute);
  });

  it('should continue to proxy request after multiple updates', async function () {
    const validTokenHeaders = {
      Authorization: `Basic ${base64credentials}`,
    };
    const resp = await getNegative(`${proxyUrl}${path}`, validTokenHeaders);
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
  });

  it('should patch the basic-auth plugin enabling the hide credentials flag', async function () {
    const resp = await axios({
      method: 'patch',
      url: `${url}/routes/${routeId}/plugins/${patchInstanceNameOnRoute}`,
      data: { config: { hide_credentials: true } },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(
      resp.data.instance_name,
      'Should equal plugin patch instance name'
    ).to.eq(patchInstanceNameOnRoute);
    expect(resp.data.config.hide_credentials, 'Should be true').to.be.true;
    await wait(isHybrid ? hybridWaitTime : shortWaitTime); // eslint-disable-line no-restricted-syntax
  });

  it('should proxy request while hiding credentials from upstream service', async function () {
    const validTokenHeaders = {
      Authorization: `Basic ${base64credentials}`,
    };
    const resp = await getNegative(`${proxyUrl}${path}`, validTokenHeaders);
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.headers).to.not.have.key('Authorization');
  });

  it('should delete the basic-auth plugin', async function () {
    const resp = await axios({
      method: 'delete',
      url: `${url}/plugins/${pluginId}`,
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 204').to.equal(204);
  });

  after(async function () {
    await deleteGatewayRoute(routeId);
    await deleteGatewayService(serviceId);
    await deleteConsumer(consumerId);
  });
});
