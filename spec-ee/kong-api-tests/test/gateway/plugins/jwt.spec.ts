import axios from 'axios';
import * as jwt from 'jsonwebtoken';
import { authDetails } from '@fixtures';
import {
  expect,
  Environment,
  getBasePath,
  createGatewayService,
  deleteGatewayService,
  createRouteForService,
  deleteGatewayRoute,
  logResponse,
  createConsumer,
  deleteConsumer,
  getNegative,
  retryRequest,
  isGateway,
  waitForConfigRebuild,
} from '@support';

describe('@oss: Gateway Plugins: jwt', function () {
  const path = '/jwt';
  const serviceName = 'jwt-service';
  const algorithms = ['ES512', 'PS256', 'PS384', 'PS512', 'RS256', 'RS384', 'RS512', 'ES256', 'ES384'];

  let serviceId: string;
  let routeId: string;
  let consumerId: string;
  let iss: string;
  let secret: string;
  let basePayload: any;
  let pluginId: string;

  const url = `${getBasePath({
    environment: isGateway() ? Environment.gateway.admin : undefined,
  })}/plugins`;
  const proxyUrl = `${getBasePath({
    app: 'gateway',
    environment: Environment.gateway.proxy,
  })}`;
  const consumerUrl = `${getBasePath({
    environment: isGateway() ? Environment.gateway.admin : undefined,
  })}/consumers`;


  before(async function () {
    const service = await createGatewayService(serviceName);
    serviceId = service.id;
    const route = await createRouteForService(serviceId, [path]);
    routeId = route.id;
    const consumerName = 'jwt-consumer';
    const consumer = await createConsumer(consumerName);
    consumerId = consumer.id;

    basePayload = {
      name: 'jwt',
      service: {
        id: serviceId,
      },
      route: {
        id: routeId,
      },
    };
  });

  it('should create jwt plugin with default parameters', async function () {
    basePayload = {
      name: 'jwt',
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

    pluginId = resp.data.id;
  });

  it('should not proxy request without token', async function () {
    await waitForConfigRebuild();

    const req = () => getNegative(`${proxyUrl}${path}`);

    const assertions = (resp) => {
      logResponse(resp);
      expect(resp.status, 'Status should be 401').to.equal(401);
      expect(resp.data.message, 'Message should be unauthorized').to.equal(
        'Unauthorized'
      );
    };

    await retryRequest(req, assertions);
  });

  it('should not proxy request with iss claim absent from token', async function () {
    let resp;

    resp = await axios({
        method: 'post',
        url: `${consumerUrl}/${consumerId}/jwt`,
        headers: {'Content-Type': 'application/x-www-form-urlencoded'}
      });
    
    logResponse(resp);

    expect(resp.status, 'Status should be 201').to.equal(201);

    iss = resp.data.key;
    secret = resp.data.secret;

    const claims = {
        'name': `${consumerId}`,
    };
    const jwt_token = jwt.sign(claims, secret, { algorithm: 'HS256' });

    resp = await getNegative(`${proxyUrl}${path}`, {
        'Authorization': `Bearer ${jwt_token}`
    });

    logResponse(resp);
    expect(resp.data.message, 'Message should be unauthorized').to.equal(
        "No mandatory 'iss' in claims"
    );
  
    expect(resp.status, 'Status should be 401').to.equal(401);
  });

  it('should create HS256 JWT credential and proxy with the HS256 token', async function () {
    let resp;

    resp = await axios({
        method: 'post',
        url: `${consumerUrl}/${consumerId}/jwt`,
        headers: {'Content-Type': 'application/x-www-form-urlencoded'}
    });
    
    logResponse(resp);
    expect(resp.status, 'Status should be 201').to.equal(201);

    iss = resp.data.key;
    secret = resp.data.secret;

    const claims = {
        'iss': iss,
    };
    const jwt_token = jwt.sign(claims, secret, { algorithm: 'HS256' });

    await waitForConfigRebuild();

    resp = await axios({
        headers: {'Authorization': `Bearer ${jwt_token}`},
        url: `${proxyUrl}${path}`,
    });

    logResponse(resp);
  
    expect(resp.status, 'Status should be 200').to.equal(200);
  });

  it('should be able to add exp to the claims', async function () {
    const patchResp = await axios({
        method: 'patch',
        url: `${url}/${pluginId}`,
        data: {
            name: 'jwt',
            config: {
            claims_to_verify: ['exp'],
            },
        },
    });
    logResponse(patchResp);    
    
    expect(patchResp.status, 'Status should be 200').to.equal(200);
    expect(
        patchResp.data.config.claims_to_verify[0],
        'Should add exp to the claims'
    ).to.equal('exp');
    await waitForConfigRebuild();
  });
    
  it('should not proxy traffic if exp is absent from token', async function () {
    const claims = {
        'iss': `${iss}`,
    };
    const jwt_token = jwt.sign(claims, secret, { algorithm: 'HS256' });

    const resp = await getNegative(`${proxyUrl}${path}`, {
        'Authorization': `Bearer ${jwt_token}`
    });

    logResponse(resp);
    expect(resp.data.exp, 'exp should be a number').to.equal(
        'must be a number'
    );

    expect(resp.status, 'Status should be 401').to.equal(401); 
  });

  it('should not proxy traffic if invalid exp is present in token', async function () {
    const now = new Date();
    // Calculate the date 30 days away from now
    const daysToSubstract = 30;
    const futureDate = new Date(now.getTime() - daysToSubstract * 24 * 60 * 60 * 1000);   

    const claims = {
        'iss': `${iss}`,
        'exp': Math.floor(futureDate.getTime() / 1000)
    };
    const jwt_token = jwt.sign(claims, secret, { algorithm: 'HS256' });

    const resp = await getNegative(`${proxyUrl}${path}`, {
        'Authorization': `Bearer ${jwt_token}`
    });

    logResponse(resp);
    expect(resp.data.exp, 'Token is expired').to.equal('token expired');
    expect(resp.status, 'Status should be 401').to.equal(401);   
  });

  it('should proxy traffic if valid exp is present in token', async function () {
    const now = new Date();
    // Calculate the date 30 days from now
    const daysToAdd = 30;
    const futureDate = new Date(now.getTime() + daysToAdd * 24 * 60 * 60 * 1000);   

    const claims = {
        'iss': `${iss}`,
        'exp': Math.floor(futureDate.getTime() / 1000)
    };

    const jwt_token = jwt.sign(claims, secret, { algorithm: 'HS256' });

    const resp = await axios({
        headers: {'Authorization': `Bearer ${jwt_token}`},
        url: `${proxyUrl}${path}`,
    });
    logResponse(resp);
    
    expect(resp.status, 'Status should be 200').to.equal(200);

    await deleteConsumer(consumerId);
  });

  it('should be able to remove exp from the claims', async function () {
    const patchResp = await axios({
        method: 'patch',
        url: `${url}/${pluginId}`,
        data: {
            name: 'jwt',
            config: {
            claims_to_verify: [],
            },
        },
    });
    logResponse(patchResp);    
    
    expect(patchResp.status, 'Status should be 200').to.equal(200);

    await waitForConfigRebuild();
  });

  algorithms.forEach((algorithm) => {
    it(`should proxy traffic with ${algorithm} algorithm`, async function () {
        const publicKey = authDetails.jwt[`${algorithm}`]['public_key']
        const privateKey = authDetails.jwt[`${algorithm}`]['private_key']

        // create a consumer
        const consumerName = `jwt-consumer-${algorithm}`;
        const consumer = await createConsumer(consumerName);
        consumerId = consumer.id;

        // add the public key to consumer with the algorithm
        let resp = await axios({
            method: 'post',
            url: `${consumerUrl}/${consumerId}/jwt`,
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            data: {
                algorithm: algorithm,
                rsa_public_key: publicKey
            },
        });

        logResponse(resp);

        expect(resp.status, 'Status should be 201').to.equal(201);

        iss = resp.data.key;
        const claims = {
            'iss': iss,
        };
        const jwt_token = jwt.sign(claims, privateKey, { algorithm: algorithm });

        await waitForConfigRebuild();

        resp = await axios({
            headers: {'Authorization': `Bearer ${jwt_token}`},
            url: `${proxyUrl}${path}`,
        });

        logResponse(resp);
        expect(resp.status, 'Status should be 200').to.equal(200);
        await deleteConsumer(consumerId);
    });
  });

  it('should delete the jwt plugin', async function () {
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
