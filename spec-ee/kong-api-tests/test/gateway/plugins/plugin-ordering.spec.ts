import axios from 'axios';
import {
  expect,
  Environment,
  getBasePath,
  createGatewayService,
  deleteGatewayService,
  createRouteForService,
  deleteGatewayRoute,
  getNegative,
  randomString,
  isGwHybrid,
  wait,
  deleteConsumer,
  createConsumer,
  createBasicAuthCredentialForConsumer,
  postNegative,
  logResponse,
  retryRequest,
  waitForConfigRebuild,
  getMetric,
  waitForConfigHashUpdate,
} from '@support';

describe('Plugin Ordering: featuring RTA,basic-auth,RV plugins', function () {
  this.timeout(45000);
  const path = `/${randomString()}`;
  const basicAuthPassword = randomString();
  const isHybrid = isGwHybrid();
  const waitTime = 5000;
  const hybridWaitTime = 8000;

  let serviceId: string;
  let routeId: string;
  let consumerDetails: any;
  let plugins: any;
  let base64credentials: string;
  let basePayload: any;

  const url = `${getBasePath({
    environment: Environment.gateway.admin,
  })}/plugins`;
  const proxyUrl = `${getBasePath({
    environment: Environment.gateway.proxy,
  })}`;

  before(async function () {
    const service = await createGatewayService('pluginOrderingService');
    serviceId = service.id;
    const route = await createRouteForService(serviceId, [path]);
    routeId = route.id;
    const consumer = await createConsumer();

    consumerDetails = {
      id: consumer.id,
      username: consumer.username,
    };

    basePayload = {
      name: 'rate-limiting-advanced',
      service: {
        id: serviceId,
      },
      route: {
        id: routeId,
      },
    };
  });

  it('should create RT, basic-auth and RV plugins with given ordering', async function () {
    // create basic-auth plugin with ordering before request-validator
    const basicAuthPayload = {
      ...basePayload,
      name: 'basic-auth',
      ordering: {
        before: {
          access: ['request-validator'],
        },
      },
    };

    let resp = await axios({
      method: 'post',
      url,
      data: basicAuthPayload,
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 201').to.equal(201);
    plugins = {
      'basic-auth': resp.data.id,
    };

    // create basic-auth credentials for a consumer
    resp = await createBasicAuthCredentialForConsumer(
      consumerDetails.id,
      consumerDetails.username,
      basicAuthPassword
    );
    logResponse(resp);

    // base64 encode credentials
    base64credentials = Buffer.from(
      `${consumerDetails.username}:${basicAuthPassword}`
    ).toString('base64');

    // create request transformer advanced plugin with ordering before basic-auth
    const rtaPayload = {
      ...basePayload,
      name: 'request-transformer-advanced',
      config: {
        add: {
          headers: [
            `Authorization: Basic ${base64credentials}`,
            'headerToBeAdded: 5',
          ],
        },
      },
      ordering: {
        before: {
          access: ['basic-auth'],
        },
      },
    };

    resp = await axios({
      method: 'post',
      url,
      data: rtaPayload,
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 201').to.equal(201);
    expect(
      resp.data.config.add.headers[0],
      'Should have correct add header'
    ).to.equal(`Authorization: Basic ${base64credentials}`);
    plugins['rta'] = resp.data.id;

    // create request validator plugin which expects 'headerToBeAdded: <number>' header with no ordering
    const rvPayload = {
      ...basePayload,
      name: 'request-validator',
      config: {
        body_schema: null,
        verbose_response: true,
        parameter_schema: [
          {
            name: 'headerToBeAdded',
            in: 'header',
            required: true,
            schema: '{"type": "number"}',
            style: 'simple',
            explode: true,
          },
        ],
      },
    };

    resp = await axios({
      method: 'post',
      url,
      data: rvPayload,
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 201').to.equal(201);
    plugins['rv'] = resp.data.id;

    if (isHybrid) {
      await waitForConfigHashUpdate(
        await getMetric('kong_data_plane_config_hash')
      );
    }
  });

  it('should apply plugin ordering RTA > basic-auth > RV', async function () {
    await waitForConfigRebuild();
    // Current plugin ordering is: RTA > basic-auth > RV
    const req = () => getNegative(`${proxyUrl}${path}`);
    const assertions = (resp) => {
      expect(resp.status, 'Status should be 200').to.equal(200);
    };

    await retryRequest(req, assertions);
  });

  it('should patch RTA plugin ordering to become after basic-auth', async function () {
    const resp = await axios({
      method: 'patch',
      url: `${url}/${plugins.rta}`,
      data: {
        ordering: {
          after: {
            access: ['basic-auth'],
          },
        },
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
  });

  it('should get 401 error as RTA now runs after basic-auth', async function () {
    // Current plugin ordering is: basic-auth > RTA > RV

    await waitForConfigRebuild();

    const req = () => getNegative(`${proxyUrl}${path}`);
    const assertions = (resp) => {
      expect(resp.status, 'Status should be 401').to.equal(401);
    };

    await retryRequest(req, assertions);
  });

  it('should put basic-auth plugin ordering to become after RV', async function () {
    let resp = await axios({
      method: 'put',
      url: `${url}/${plugins['basic-auth']}`,
      data: {
        ...basePayload,
        name: 'basic-auth',
        ordering: {
          after: {
            access: ['request-validator'],
          },
        },
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);

    //  updating RTA plugin to add only 'Authorization' header
    resp = await axios({
      method: 'patch',
      url: `${url}/${plugins.rta}`,
      data: {
        config: {
          add: {
            headers: [`Authorization: Basic ${base64credentials}`],
          },
        },
        ordering: {
          before: {
            access: ['request-validator'],
          },
        },
      },
    });

    expect(resp.status, 'Status should be 200').to.equal(200);
  });

  it('should get 400 error as RTA now runs after basic-auth', async function () {
    // Current plugin ordering is: RTA > RV > basic-auth
    await waitForConfigRebuild();
    const resp = await getNegative(`${proxyUrl}${path}`);
    logResponse(resp);

    expect(resp.status, 'Status should be 400').to.equal(400);
    expect(
      resp.data.message,
      'Should fail due to non-existing header'
    ).to.include("header 'headerToBeAdded' validation failed");
  });

  it('should pass after adding correct header for RV', async function () {
    // Current plugin ordering is: RTA > RV > basic-auth
    await wait(waitTime);
    const resp = await getNegative(`${proxyUrl}${path}`, {
      headerToBeAdded: '5',
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
  });

  it('should patch plugins so that RV is the first in order', async function () {
    let resp = await axios({
      method: 'put',
      url: `${url}/${plugins['basic-auth']}`,
      data: {
        ...basePayload,
        name: 'basic-auth',
        ordering: {
          after: {
            access: ['request-transformer-advanced'],
          },
        },
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);

    resp = await axios({
      method: 'patch',
      url: `${url}/${plugins.rta}`,
      data: {
        ordering: {
          after: {
            access: ['request-validator'],
          },
        },
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
  });

  it('should fail as RV now runs the first and header is not in the request', async function () {
    // Current plugin ordering is: RV > RTA > basic-auth
    await wait(waitTime);
    const resp = await getNegative(`${proxyUrl}${path}`);
    logResponse(resp);

    expect(resp.status, 'Status should be 400').to.equal(400);
    expect(
      resp.data.message,
      'Should fail due to non-existing header'
    ).to.include("header 'headerToBeAdded' validation failed");
  });

  it('should fully pass the ordering chain after adding correct header', async function () {
    // Current plugin ordering is: RV > RTA > basic-auth
    await wait(waitTime);
    const resp = await getNegative(`${proxyUrl}${path}`, {
      headerToBeAdded: '5',
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
  });

  it('should patch basic-auth plugin ordering to become before all in ordering', async function () {
    let resp = await axios({
      method: 'patch',
      url: `${url}/${plugins['basic-auth']}`,
      data: {
        ordering: {
          before: {
            access: ['request-transformer-advanced'],
          },
        },
      },
    });
    logResponse(resp);

    resp = await axios({
      method: 'patch',
      url: `${url}/${plugins.rv}`,
      data: {
        ordering: {
          after: {
            access: ['basic-auth'],
          },
        },
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);

    // Current plugin ordering is: basic-auth > RV > RTA
    await wait(isHybrid ? hybridWaitTime : waitTime);
    resp = await getNegative(`${proxyUrl}${path}`);

    expect(resp.status, 'Status should be 401').to.equal(401);
  });

  it('should not be able to create consumer-scoped RLA plugin with ordering', async function () {
    const rlaPayload = {
      consumer: {
        id: consumerDetails.id,
      },
      name: 'rate-limiting-advanced',
      ordering: {
        before: {
          access: ['request-validator'],
        },
      },
    };

    const resp = await postNegative(url, rlaPayload);
    logResponse(resp);

    expect(resp.status, 'Status should be 400').to.equal(400);
    expect(resp.data.message, 'Should have correct error message').to.include(
      "schema violation (ordering: can't apply dynamic reordering to consumer scoped plugins)"
    );
  });

  after(async function () {
    await deleteGatewayRoute(routeId);
    await deleteGatewayService(serviceId);
    await deleteConsumer(consumerDetails.id);
  });
});
