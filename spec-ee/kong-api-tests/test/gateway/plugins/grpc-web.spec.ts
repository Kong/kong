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
  waitForConfigRebuild,
  updateGatewayService,
  logResponse,
} from '@support';

describe('Gateway Plugins: gRPC-web', function () {
  const grpcUrl = 'grpc://grpcbin:9000';
  const grpcSecureUrl = 'grpcs://grpcbin:9001';
  const protoFile = 'hello.proto';
  const protoPath = '/usr/local/kong/protos/';
  const path = '/grpcweb';
  const unaryRpc = '/hello.HelloService/SayHello';
  const serverStreaming = '/hello.HelloService/LotsOfReplies';
  const grpcResponse = 'hello ';
  const grpcMessage = 'Kong3.0.x.x.x';
  const protocols = ['grpc', 'grpcs', 'http', 'https'];
  const serviceName = 'grpcbin-web-service';

  let serviceId: string;
  let routeId: string;

  const url = `${getBasePath({
    environment: Environment.gateway.admin,
  })}/plugins`;
  const proxyUrl = `${getBasePath({
    environment: Environment.gateway.proxy,
  })}`;
  const proxyUrlSecure = `${getBasePath({
    environment: Environment.gateway.proxySec,
  })}`;
  // This is needed in order to send a secure request to the upstream
  const agent = new https.Agent({
    rejectUnauthorized: false,
  });

  let basePayload: any;
  let pluginId: string;

  //We need to use a gRPC service
  before(async function () {
    const service = await createGatewayService(serviceName, {
      url: `${grpcUrl}`,
    });
    serviceId = service.id;
    const route = await createRouteForService(serviceId, [path]);
    routeId = route.id;

    basePayload = {
      name: 'grpc-web',
      service: {
        id: serviceId,
      },
      route: {
        id: routeId,
      },
    };

    await waitForConfigRebuild();
  });

  it('should create grpc-web plugin', async function () {
    const pluginPayload = {
      ...basePayload,
      config: {
        proto: `${protoPath}${protoFile}`,
        pass_stripped_path: true,
      },
    };

    const resp = await axios({ method: 'post', url, data: pluginPayload });
    logResponse(resp);

    expect(resp.status, 'Status should be 201').to.equal(201);
    expect(resp.data.config.proto, 'Should have correct path').to.eq(
      `${protoPath}${protoFile}`
    );
    expect(resp.data.protocols, 'Should have correct protocols').to.eql(
      protocols
    );
    pluginId = resp.data.id;
    await waitForConfigRebuild();
  });

  it('should validate unary response with greeting', async function () {
    const resp = await axios({
      url: `${proxyUrl}${path}${unaryRpc}`,
      method: 'post',
      headers: {
        'x-grpc': true,
      },
      data: { greeting: `${grpcMessage}`, test: true },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.reply, 'Should have correct message').to.eq(
      `${grpcResponse}${grpcMessage}`
    );
  });

  it('should validate unary response w/o greeting', async function () {
    const resp = await axios({
      url: `${proxyUrl}${path}${unaryRpc}`,
      method: 'post',
      headers: {
        'x-grpc': true,
      },
      data: { greeting: '', test: true },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.reply, 'Should have correct message').to.eq(
      `${grpcResponse}`
    );
  });

  it('should validate server streaming response', async function () {
    const resp = await axios({
      url: `${proxyUrl}${path}${serverStreaming}`,
      method: 'post',
      headers: {
        'x-grpc': true,
      },
      data: { greeting: `${grpcMessage}`, test: true },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data, 'Should have correct message').to.contain(
      `${grpcResponse}${grpcMessage}`
    );
    // the strategy here is to ensure the stream returns more than a single response
    expect(
      resp.data,
      'Should have more than one message response'
    ).length.above(11);
  });

  it('should patch the service to allow ssl', async function () {
    const patchService = await updateGatewayService(serviceName, {
      url: `${grpcSecureUrl}`,
    });

    expect(patchService.id, 'Service id should match').to.equal(serviceId);

    await waitForConfigRebuild();
  });

  it('should validate unary response with greeting using secure connection', async function () {
    const resp = await axios({
      url: `${proxyUrlSecure}${path}${unaryRpc}`,
      httpsAgent: agent,
      method: 'post',
      headers: {
        'x-grpc': true,
      },
      data: { greeting: `${grpcMessage}`, test: true },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.reply, 'Should have correct message').to.eq(
      `${grpcResponse}${grpcMessage}`
    );
  });

  it('should delete the gRPC-web plugin', async function () {
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
