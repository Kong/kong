import axios from 'axios';
import * as https from 'https';
import {
  expect,
  Environment,
  getBasePath,
  createGatewayService,
  deleteGatewayService,
  createRouteForService,
  deleteGatewayRoute,
  wait,
  updateGatewayService,
  logResponse,
  isLocalDatabase,
  isGateway,
} from '@support';

describe('Gateway Plugins: gRPC-gateway', function () {
  const grpcUrl = 'grpc://grpcbin:9000';
  const grpcSecureUrl = 'grpcs://grpcbin:9001';
  const protoFile = 'hello-gateway.proto';
  const protoPath = '/usr/local/kong/protos/';
  const alternateProtoFile = 'hello-gateway-2.proto';
  const path = '/grpcgateway';
  const grpcMapping1 = '/messages/';
  const grpcMapping2 = '/messages/legacy/';
  const addPaths = '/more/paths';
  const grpcResponse = 'hello ';
  const grpcMessage = 'Kong3.0.x.x.x';
  const protocols = ['grpc', 'grpcs', 'http', 'https'];
  const serviceName = 'grpcbin-gateway-service';

  const isLocalDb = isLocalDatabase();
  const shortWait = 5000;
  const longWait = 10000;

  let serviceId: string;
  let routeId: string;

  const url = `${getBasePath({
    environment: isGateway() ? Environment.gateway.admin : undefined,
  })}/plugins`;
  const proxyUrl = `${getBasePath({
    app: 'gateway',
    environment: Environment.gateway.proxy,
  })}`;
  const proxyUrlSecure = `${getBasePath({
    app: 'gateway',
    environment: Environment.gateway.proxySec,
  })}`;
  // This is needed in order to send a secure request to the upstream
  const agent = new https.Agent({
    rejectUnauthorized: false,
  });

  let basePayload: any;
  let pluginId: string;

  before(async function () {
    const service = await createGatewayService(serviceName, {
      url: `${grpcUrl}`,
    });
    serviceId = service.id;
    const route = await createRouteForService(serviceId, [path]);
    routeId = route.id;

    basePayload = {
      name: 'grpc-gateway',
      service: {
        id: serviceId,
      },
      route: {
        id: routeId,
      },
    };
  });

  it('should create grpc-gateway plugin', async function () {
    const pluginPayload = {
      ...basePayload,
      config: {
        proto: `${protoPath}${protoFile}`,
      },
    };
    const resp = await axios({ method: 'post', url, data: pluginPayload });

    expect(resp.status, 'Status should be 201').to.equal(201);
    expect(resp.data.config.proto, 'Should have correct path').to.eq(
      `${protoPath}${protoFile}`
    );
    expect(resp.data.protocols, 'Should have correct protocols').to.eql(
      protocols
    );
    pluginId = resp.data.id;
    await wait(isLocalDb ? 7000 : longWait); // eslint-disable-line no-restricted-syntax
  });

  it('should validate mapping rule 1', async function () {
    const resp = await axios({
      url: `${proxyUrl}${path}${grpcMapping1}${grpcMessage}`,
      headers: {
        'x-grpc': true,
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.reply, 'Should have correct message').to.eq(
      `${grpcResponse}${grpcMessage}`
    );
  });

  it('should validate mapping rule 2', async function () {
    const resp = await axios({
      url: `${proxyUrl}${path}${grpcMapping2}${grpcMessage}`,
      headers: {
        'x-grpc': true,
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.reply, 'Should have correct message').to.eq(
      `${grpcResponse}${grpcMessage}`
    );
  });

  it('should validate additional pathing', async function () {
    const resp = await axios({
      url: `${proxyUrl}${path}${grpcMapping2}${grpcMessage}${addPaths}`,
      headers: {
        'x-grpc': true,
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.reply, 'Should have correct message').to.eq(
      `${grpcResponse}${grpcMessage}${addPaths}`
    );
  });

  //This test is failing due to https://konghq.atlassian.net/browse/FTI-3335
  xit('should validate bool datatype can be set', async function () {
    const resp = await axios({
      url: `${proxyUrl}${path}${grpcMapping2}${grpcMessage}`,
      params: {
        test: true,
      },
      headers: {
        'x-grpc': true,
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.reply, 'Should have correct message').to.eq(
      `${grpcResponse}${grpcMessage}`
    );
    expect(resp.data.test, 'Bool should be set to True').to.be.true;
  });

  it('should update and set grpc-gateway plugin to select an alternate proto', async function () {
    const resp = await axios({
      method: 'patch',
      url: `${url}/${pluginId}`,
      data: {
        config: {
          proto: `${protoPath}${alternateProtoFile}`,
        },
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.config.proto, 'Should have correct path').to.eq(
      `${protoPath}${alternateProtoFile}`
    );
    expect(resp.data.protocols, 'Should have correct protocols').to.eql(
      protocols
    );
    expect(resp.status, 'Status should be 200').to.equal(200);
    await wait(isLocalDb ? shortWait : longWait); // eslint-disable-line no-restricted-syntax
  });

  it('should validate new proto POST bindings', async function () {
    const resp = await axios({
      url: `${proxyUrl}${path}${grpcMapping1}`,
      method: 'post',
      headers: {
        'x-grpc': true,
      },
      data: {
        name: `${grpcMessage}`,
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.reply, 'Should have correct message').to.eq(
      `${grpcResponse}${grpcMessage}`
    );
  });

  it('should validate new proto POST bindings where message is optional', async function () {
    const resp = await axios({
      url: `${proxyUrl}${path}${grpcMapping1}`,
      method: 'post',
      headers: {
        'x-grpc': true,
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.reply, 'Should have correct message').to.eq(
      `${grpcResponse}noname`
    );
  });

  it('should patch the service to allow ssl', async function () {
    const patchService = await updateGatewayService(serviceName, {
      url: `${grpcSecureUrl}`,
    });

    expect(patchService.id, 'Service id should match').to.equal(serviceId);
  });

  it('should validate new proto POST bindings using secure connection', async function () {
    const resp = await axios({
      url: `${proxyUrlSecure}${path}${grpcMapping1}`,
      method: 'post',
      httpsAgent: agent,
      headers: {
        'x-grpc': true,
      },
      data: {
        name: `${grpcMessage}`,
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.reply, 'Should have correct message').to.eq(
      `${grpcResponse}${grpcMessage}`
    );
  });

  it('should delete the gRPC-gateway plugin', async function () {
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
