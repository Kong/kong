import axios from 'axios';
import { authDetails } from '@fixtures';
import {
  expect,
  Environment,
  getBasePath,
  isGwHybrid,
  isLocalDatabase,
  createGatewayService,
  deleteGatewayService,
  createRouteForService,
  deleteGatewayRoute,
  wait,
  logResponse,
  createConsumer,
  deleteConsumer,
  getNegative,
  retryRequest,
} from '@support';

describe('Gateway Plugins: jwt-signer', function () {
  this.timeout(30000);
  const path = '/jwtsigner';
  const serviceName = 'jwt-signer-service';
  const consumerName = 'demo';
  const upstreamConsumerHeaderName = 'X-Consumer-Username';
  const upstreamConsumerHeaderId = 'X-Consumer-Id';
  const isHybrid = isGwHybrid();
  const islocalDb = isLocalDatabase();
  const waitTime = 5000;
  const hybridWaitTime = 10000;
  const expiredTokenHeaders = {
    Authorization: `bearer ${authDetails.expired_token}`,
  };
  const validTokenHeaders = {
    Authorization: `bearer ${authDetails.valid_token}`,
  };

  let serviceId: string;
  let routeId: string;
  let consumerId: string;

  const url = `${getBasePath({
    environment: Environment.gateway.admin,
  })}/plugins`;
  const proxyUrl = `${getBasePath({
    environment: Environment.gateway.proxy,
  })}`;
  const jwksServer = `${getBasePath({
    environment: Environment.gateway.ec2TestServer,
  })}`;
  const jwksUri = `http://${jwksServer}:3000/db`;

  let basePayload: any;
  let pluginId: string;

  before(async function () {
    const service = await createGatewayService(serviceName);
    serviceId = service.id;
    const route = await createRouteForService(serviceId, [path]);
    routeId = route.id;
    const consumer = await createConsumer(consumerName);
    consumerId = consumer.id;

    basePayload = {
      name: 'jwt-signer',
      service: {
        id: serviceId,
      },
      route: {
        id: routeId,
      },
    };
  });

  it('should create jwt-signer plugin with default parameters when config payload is not supplied by the user', async function () {
    basePayload = {
      name: 'jwt-signer',
      service: {
        id: serviceId,
      },
      route: {
        id: routeId,
      },
    };
    const pluginPayload = {
      ...basePayload,
      config: {},
    };
    const resp = await axios({ method: 'post', url, data: pluginPayload });
    logResponse(resp);

    expect(resp.status, 'Status should be 201').to.equal(201);
    expect(resp.data.config.verify_access_token_expiry, 'Expiry should be true')
      .to.true;

    expect(
      resp.data.config.access_token_issuer,
      'Issuer should be kong'
    ).to.equal('kong');

    expect(
      resp.data.config.access_token_signing_algorithm,
      'Algorithm should be RS256'
    ).to.equal('RS256');

    expect(resp.data.config.access_token_jwks_uri, 'Jwks uri should be null').to
      .be.null;

    expect(resp.data.config.access_token_optional, 'Should be false').to.false;

    expect(resp.data.config.channel_token_optional, 'Should be false').to.false;

    pluginId = resp.data.id;
  });

  it('should not proxy request when JWKS_URI parameter is null preventing token validation', async function () {
    const req = () => getNegative(`${proxyUrl}${path}`);

    const assertions = (resp) => {
      expect(resp.status, 'Status should be 401').to.equal(401);
      expect(resp.data.message, 'Message should be unauthorized').to.equal(
        'Unauthorized'
      );
    };

    await retryRequest(req, assertions);
  });

  it.skip('should patch jwt-signer plugin to set JWKS_URI allowing token validation', async function () {
    const resp = await axios({
      method: 'patch',
      url: `${url}/${pluginId}`,
      data: {
        config: {
          channel_token_optional: true,
          access_token_jwks_uri: jwksUri,
          access_token_consumer_claim: ['username'],
        },
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(
      resp.data.config.access_token_jwks_uri,
      'Jwks uri should not be null'
    ).to.equal(jwksUri);
    await wait(isHybrid ? hybridWaitTime : waitTime);
  });

  it.skip('should proxy request with a valid token', async function () {
    const resp = await axios({
      headers: validTokenHeaders,
      url: `${proxyUrl}${path}`,
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(
      resp.data.headers[upstreamConsumerHeaderName],
      'Should see consumer username in upstream request'
    ).to.equal(consumerName);
    expect(
      resp.data.headers[upstreamConsumerHeaderId],
      'Should see consumer id in upstream request'
    ).to.equal(consumerId);
  });

  it('should not proxy request with a expired token ', async function () {
    const resp = await getNegative(`${proxyUrl}${path}`, expiredTokenHeaders);
    logResponse(resp);

    expect(resp.status, 'Status should be 401').to.equal(401);
    expect(resp.data.message, 'Should be Unauthorized').to.equal(
      'Unauthorized'
    );
  });

  it('should patch jwt-signer plugin to disable auth and allow requests', async function () {
    const resp = await axios({
      method: 'patch',
      url: `${url}/${pluginId}`,
      data: {
        config: {
          channel_token_optional: true,
          access_token_optional: true,
        },
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.config.access_token_optional, 'Should be true').to.be.true;
    expect(resp.data.config.channel_token_optional, 'Should be true').to.be
      .true;
    await wait(waitTime + (islocalDb ? 0 : waitTime));
  });

  it('should proxy request without token', async function () {
    const req = () =>
      axios({
        url: `${proxyUrl}${path}`,
      });

    const assertions = (resp) => {
      expect(resp.status, 'Status should be 200').to.equal(200);
    };

    await retryRequest(req, assertions, 20000, 4000);
  });

  it('should delete the jwt-signer plugin', async function () {
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
    await deleteConsumer(consumerId);
  });
});
