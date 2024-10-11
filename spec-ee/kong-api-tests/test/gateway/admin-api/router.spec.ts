/* eslint-disable no-useless-escape */
import axios from 'axios';
import https from 'https';
import {
  expect,
  getNegative,
  postNegative,
  getBasePath,
  Environment,
  randomString,
  createGatewayService,
  logResponse,
  isGwHybrid,
  isLocalDatabase,
  wait,
  getGatewayHost,
  getGatewayContainerLogs,
  findRegex,
  retryRequest,
  getKongContainerName,
  waitForConfigRebuild,
  resetGatewayContainerEnvVariable,
  clearAllKongResources,
  isGateway,
  isKoko,
  deleteWorkspace,
  eventually,
} from '@support';

const agent = new https.Agent({
  rejectUnauthorized: false,
});

axios.defaults.httpsAgent = agent;

const testWrongHeaders = [
  { header: 'testHeader', value: 'wrong' },
  { header: 'testH', value: 'test' },
];

const testCorrectHeaders = [
  { header: 'testHeader', value: 'test' },
  { header: 'testHeader', value: 'test2' },
];

const regexWrongPatterns = ['/5555-helo', '/heo-world', '/wrong-test'];
const regexCorrectPatterns = ['/helo-test', '/hello-auto', '/world-te'];
const currentHost = getGatewayHost();

const isLocalDb = isLocalDatabase();

describe('@smoke @koko @gke: Router Functionality Tests', function () {
  const proxyUrl = `${getBasePath({
    app: 'gateway',
    environment: Environment.gateway.proxySec,
  })}`;

  const isHybrid = isGwHybrid();
  const serviceName = randomString();
  const serviceName2 = randomString();
  const kongContainerName = getKongContainerName();
  const regexPath = '~/(hell?o|world)-(?<user>[a-zA-Z]+)';
  const waitTime = 5000;
  const hybridWaitTime = 6000;

  let serviceDetails: any;
  let service2Details: any;
  let routeId: string;
  let adminUrl: any;
  let routesUrl: any
  let workspaceName: string;

  const routePayload = {
    name: randomString(),
    paths: [`/${randomString()}`, '/plain/a.b%25c', '~/prefix/[0-9]+'],
    methods: ['GET'],
  };

  before(async function () {
    adminUrl = `${getBasePath({
      environment: isGateway() ? Environment.gateway.admin : undefined,
    })}`;
  
    routesUrl = `${adminUrl}/routes`;

    const serviceReq = await createGatewayService(serviceName);

    serviceDetails = {
      id: serviceReq.id,
      name: serviceReq.name,
    };

    const workspaceReq = await axios({
      method: 'POST',
      url: `${adminUrl}/workspaces`,
      data: {
        name: randomString(),
      },
      validateStatus: null,
    });

    expect(workspaceReq.status, 'Status should be 201').equal(201);
    workspaceName = workspaceReq.data.name;

    //create service in new workspace
    const serviceReq2 = await axios({
      method: 'POST',
      url: `${adminUrl}/${workspaceName}/services`,
      data: {
        name: serviceName2,
        url: 'http://mockbin.org',
      },
    })
    logResponse(serviceReq2);

    service2Details = {
      id: serviceReq2.data.id,
      name: serviceReq2.data.name,
    };

    const resp = await axios({
      method: 'get',
      url: `${adminUrl}/services/${serviceDetails.id}/routes`,
    });
    logResponse(resp);
  });

  it('should create a route with header', async function () {
    const payload = {
      ...routePayload,
      headers: {
        testHeader: ['test', 'test2'],
      },
    };

    const resp = await axios({
      method: 'post',
      url: `${adminUrl}/services/${serviceDetails.id}/routes`,
      data: payload,
      validateStatus: null,
    });

    logResponse(resp);
    expect(resp.status, 'Status should be 201').equal(201);
    routeId = resp.data.id;

    expect(resp.data.name, 'Should have correct route name').equal(
      payload.name
    );

    expect(
      resp.data.headers,
      'Should have correct route header key'
    ).to.have.property('testHeader');

    await wait( // eslint-disable-line no-restricted-syntax
      isHybrid ? hybridWaitTime + (isLocalDb ? 0 : hybridWaitTime) : waitTime
    );
  });

  it('should not create a route with duplicate name', async function () {
    const resp = await postNegative(
      routesUrl,
      routePayload,
      'post',
      {},
      { rejectUnauthorized: true }
    );
    logResponse(resp);

    // *** RESPONSE DIFFERENCES IN GATEWAY AND KOKO ***
    if (isGateway()) {
      expect(resp.status, 'Status should be 409').equal(409);
      expect(resp.data.name, 'Should have correct error name').equal(
        'unique constraint violation'
      );
      expect(resp.data.message, 'Should have correct error name').equal(
        `UNIQUE violation detected on '{name="${routePayload.name}"}'`
      );
    } else if (isKoko()) {
      expect(resp.status, 'Status should be 400').to.equal(400);
      expect(resp.data.message, 'Should have correct error name').to.equal(
        'data constraint error'
      );

      // in Konnect we need to wait for the route creation to take effect
      await waitForConfigRebuild()
    }
  });

  testWrongHeaders.forEach(({ header, value }) => {
    it(`should not route a request with wrong header: ${header}:${value}`, async function () {
      const resp = await getNegative(
        `${proxyUrl}${routePayload.paths[0]}`,
        {
          [header]: value,
        },
        {},
        { rejectUnauthorized: true }
      );
      logResponse(resp);

      expect(resp.status, 'Status should be 404').equal(404);
      expect(resp.data.message, 'Should have correct error name').equal(
        `no Route matched with those values`
      );
    });
  });

  it('should not route a request without the required header', async function () {
    const resp = await getNegative(
      `${proxyUrl}${routePayload.paths[0]}`,
      {},
      {},
      { rejectUnauthorized: true }
    );
    logResponse(resp);

    expect(resp.status, 'Status should be 404').equal(404);
    expect(resp.data.message, 'Should have correct error name').equal(
      `no Route matched with those values`
    );
  });

  testCorrectHeaders.forEach(({ header, value }) => {
    it(`should route a request with correct header: ${header}:${value}`, async function () {
      const resp = await axios({
        url: `${proxyUrl}${routePayload.paths[0]}`,
        headers: { [header]: value },
      });
      logResponse(resp);
      expect(resp.status, 'Status should be 200').equal(200);
    });
  });

  it('should NOT route a request when http method is not allowed', async function () {
    const resp = await postNegative(
      `${proxyUrl}${routePayload.paths[0]}`,
      {},
      'post',
      {
        testHeader: 'test',
      },
      { rejectUnauthorized: true }
    );

    logResponse(resp);
    expect(resp.status, 'Status should be 404').equal(404);
    expect(resp.data.message, 'Should have correct error name').equal(
      `no Route matched with those values`
    );
  });

  it('should route a request with route path /plain/a.b%25c', async function () {
    const resp = await axios({
      url: `${proxyUrl}${routePayload.paths[1]}`,
      headers: { testHeader: 'test' },
    });
    logResponse(resp);
    expect(resp.status, 'Status should be 200').equal(200);
  });

  it('should match route path /prefix/123 when regex is ~/prefix/[0-9]+', async function () {
    const resp = await axios({
      url: `${proxyUrl}/prefix/123}`,
      headers: { testHeader: 'test' },
    });

    logResponse(resp);
    expect(resp.status, 'Status should be 200').equal(200);
  });

  it('should NOT match route path /extra/prefix/123 when regex is ~/prefix/[0-9]+', async function () {
    const resp = await getNegative(
      `${proxyUrl}/extra/prefix/123}`,
      {
        testHeader: 'test',
      },
      {},
      { rejectUnauthorized: true }
    );

    logResponse(resp);
    expect(resp.status, 'Status should be 404').equal(404);
  });

  it('should PATCH the route headers and paths', async function () {
    // *** KOKO DOES NOT PATCH REQUESTS AND HEADERS SHOULD BE NULL ***
    const resp = await axios({
      method: isGateway() ? 'patch' : 'put',
      url: `${routesUrl}/${routeId}`,
      data: {
        service: {
          id: serviceDetails.id
        },
        headers: isGateway() ? [] : null,
        paths: [regexPath]
      },
      headers: { 'Content-Type': 'application/json' },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').equal(200);
    expect(resp.data.paths[0], 'Should have correct path').to.equal(regexPath);

    // *** KOKO DOES NOT CONTAIN HEADERS in RESPONSE ***
    if(isGateway()) {
      expect(resp.data.headers, 'Should have empty headers').to.be.empty
    } else if (isKoko()) {
      expect(resp.data.headers, 'Should have no headers').to.not.exist
    }

    await waitForConfigRebuild()
  });
  
  regexCorrectPatterns.forEach((correctPattern) => {
    it(`should route a request with matching regex path: ${correctPattern}`, async function () {
      const req = () => axios(`${proxyUrl}${correctPattern}`);

      const assertions = (resp) => {
        expect(resp.status, 'Status should be 200').equal(200);
      };

      await retryRequest(req, assertions);
    });
  });

  regexWrongPatterns.forEach((wrongPattern) => {
    it(`should not route a request with non-matching regex path: ${wrongPattern}`, async function () {
      const resp = await getNegative(
        `${proxyUrl}${wrongPattern}`,
        {},
        {},
        { rejectUnauthorized: true }
      );
      logResponse(resp);
      expect(resp.status, 'Status should be 404').equal(404);
    });
  });

  it('should PATCH the route host', async function () {
    // *** KOKO DOES NOT PATCH REQUESTS ***
    const resp = await axios({
      method: isGateway() ? 'patch' : 'put',
      url: `${routesUrl}/${routeId}`,
      data: {
        service: {
          id: serviceDetails.id
        },
        hosts: ['test'],
        paths: [routePayload.paths[0]],
      },
      headers: { 'Content-Type': 'application/json' },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').equal(200);
    expect(resp.data.hosts[0], 'Should have correct host').to.equal('test');
    await wait(waitTime); // eslint-disable-line no-restricted-syntax
  });

  it('should not route a request with wrong host', async function () {
    const resp = await getNegative(
      `${proxyUrl}${routePayload.paths[0]}`,
      {},
      {},
      { rejectUnauthorized: true }
    );
    logResponse(resp);
    expect(resp.status, 'Status should be 404').equal(404);
    expect(resp.data.message, 'Should have correct error name').equal(
      `no Route matched with those values`
    );
  });

  it('should route the request with correct host', async function () {
    const resp = await axios({
      method: isGateway() ? 'patch' : 'put',
      url: `${routesUrl}/${routeId}`,
      data: {
        service: {
          id: serviceDetails.id
        },
        paths: [routePayload.paths[0]],
        hosts: [currentHost]
      },
      headers: { 'Content-Type': 'application/json' },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').equal(200);
    expect(resp.data.hosts[0], 'Should have correct host').to.equal(
      currentHost
    );

    await waitForConfigRebuild();

    const req = () => axios(`${proxyUrl}${routePayload.paths[0]}`);
    const assertions = (resp) => {
      expect(resp.status, 'Status should be 200').equal(200);
    };

    await retryRequest(req, assertions);
  });

  if(isGateway()) {
    it('should delete the route by name', async function () {
      const resp = await axios({
        method: 'delete',
        url: `${routesUrl}/${routePayload.name}`,
      });
  
      logResponse(resp);
      expect(resp.status, 'Status should be 204').to.equal(204);
    });

    it('should not panic and create a route with long regex path', async function () {
      // Skip this test for GKE deployment
      if (process.env.GKE) {
        this.skip();
      }
      // generate string longer than 2048 bytes
      // *** KOKO MAX BYTES IS 1024 AND IT DOESN'T RECOGNIZE "\\/" ESCAPE SEQUENCE ***
      const path = 'x'.repeat(3072);
  
      const resp = await postNegative(
        `${adminUrl}/services/${serviceDetails.id}/routes`,
        {
          name: randomString(),
          paths: [`~/${path}/[^\\/]{14}()$`],
        },
        'post',
        {},
        { rejectUnauthorized: true }
      );
      logResponse(resp);
  
      routeId = resp.data.id;
  
      expect(resp.status, 'Status should be 201').to.equal(201);
  
      await wait(4000); // eslint-disable-line no-restricted-syntax
      const currentLogs = getGatewayContainerLogs(kongContainerName, 15);
      const panickLog = findRegex('panicked', currentLogs);
      const outOfRangeLog = findRegex('out of range', currentLogs);
  
      expect(panickLog, 'Should not see router panic error log').to.be.false;
      expect(outOfRangeLog, 'Should not see out of range error log').to.be.false;
    });
  }

  it('should perform route validation when creating a duplicate route in a different workspace', async function () {
    // duplicate routes cannot be created when route validation is on
    const resp = await axios({ 
      method: 'post',
      url: `${adminUrl}/services/${serviceDetails.id}/routes`,
      data: {
        ...routePayload,
        name: routePayload.name,
      },
      validateStatus: null,
    });
    expect(resp.status, 'Status should be 201').to.equal(201);

    waitForConfigRebuild();

    // attempt to create route in second workspace
    const respRepeat = await axios({ 
      method: 'post',
      url: `${adminUrl}/${workspaceName}/services/${service2Details.id}/routes`,
      data: {
        ...routePayload,
        name: routePayload.name,
      },
      validateStatus: null,
    });
    logResponse(respRepeat);
    expect(respRepeat.status, 'Status should be 409').to.equal(409);
    expect(respRepeat.data.message, 'Should have correct error message').to.equal('API route collides with an existing API');
  })

  it('should update router to not perform route validation', async function () {
    await resetGatewayContainerEnvVariable({ KONG_ROUTE_VALIDATION_STRATEGY: 'off' }, kongContainerName);
    if (isHybrid) {
      await resetGatewayContainerEnvVariable({ KONG_ROUTE_VALIDATION_STRATEGY: 'off' }, 'kong-dp1');
    }

    await eventually(async () => {
    // ensure that route validation is set to off
    const resp = await axios({
      method: 'get',
      url: `${adminUrl}`,
    });
    logResponse(resp);
    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.configuration.route_validation_strategy, 'Route validation should be off').to.equal('off');
    });
  })

  it('should create a duplicate route when route validation is off', async function () {
    const resp = await axios({ 
      method: 'post',
      url: `${adminUrl}/${workspaceName}/services/${service2Details.id}/routes`,
      data: {
        ...routePayload,
        name: routePayload.name,
      },
    });
    expect(resp.status, 'Status should be 201').to.equal(201); 

    // validate route was created
    const respGet = await axios({
      method: 'get',
      url: `${adminUrl}/${workspaceName}/services/${service2Details.id}/routes`,
    });
    expect(respGet.status, 'Status should be 200').to.equal(200);
    expect(respGet.data.data.length, 'Should have correct number of routes').to.equal(1);
    expect(respGet.data.data[0].name, 'Should have correct route name').to.equal(routePayload.name);
  })

  it('should be able to send request to duplicate route', async function () {
    const resp = await axios({
      method: 'get',
      url: `${proxyUrl}${routePayload.paths[0]}`,
      headers: { testHeader: 'test' },
    });
    logResponse(resp);
    expect(resp.status, 'Status should be 200').to.equal(200);
  })

  after(async function () {
    await clearAllKongResources();
    await clearAllKongResources(workspaceName);
    await deleteWorkspace(workspaceName);
    await resetGatewayContainerEnvVariable({ KONG_ROUTE_VALIDATION_STRATEGY: 'smart' }, kongContainerName);
    // reset data plane
    if (isHybrid) {
      await resetGatewayContainerEnvVariable({ KONG_ROUTE_VALIDATION_STRATEGY: 'smart' }, 'kong-dp1');
    }
  });
});
