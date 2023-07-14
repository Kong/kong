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
  deleteGatewayService,
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
  deleteGatewayRoute,
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

describe('@smoke: Router Functionality Tests', function () {
  const routesUrl = `${getBasePath({
    environment: Environment.gateway.adminSec,
  })}/routes`;

  const adminUrl = `${getBasePath({
    environment: Environment.gateway.adminSec,
  })}`;

  const proxyUrl = `${getBasePath({
    environment: Environment.gateway.proxySec,
  })}`;

  const isHybrid = isGwHybrid();
  const serviceName = randomString();
  const kongContainerName = getKongContainerName();
  const regexPath = '~/(hell?o|world)-(?<user>\\S+)';
  const waitTime = 5000;
  const longWaitTime = 10000;
  const hybridWaitTime = 6000;

  let serviceDetails: any;
  let routeId: string;

  const routePayload = {
    name: randomString(),
    paths: [`/${randomString()}`, '/plain/a.b%25c', '~/prefix/[0-9]+'],
    methods: ['GET'],
  };

  before(async function () {
    const serviceReq = await createGatewayService(serviceName, {
      url: 'http://httpbin/anything',
    });
    serviceDetails = {
      id: serviceReq.id,
      name: serviceReq.name,
    };
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

    await wait(
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

    expect(resp.status, 'Status should be 409').equal(409);
    expect(resp.data.name, 'Should have correct error name').equal(
      'unique constraint violation'
    );
    expect(resp.data.message, 'Should have correct error name').equal(
      `UNIQUE violation detected on '{name="${routePayload.name}"}'`
    );
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
    const resp = await axios({
      method: 'patch',
      url: `${routesUrl}/${routeId}`,
      data: {
        headers: [],
        paths: [regexPath],
      },
      headers: { 'Content-Type': 'application/json' },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').equal(200);
    expect(resp.data.headers, 'Should have empty headers').to.be.empty;
    expect(resp.data.paths[0], 'Should have correct path').to.equal(regexPath);
    await wait(isLocalDb ? waitTime : longWaitTime);
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

  regexCorrectPatterns.forEach((correctPattern) => {
    it(`should route a request with matching regex path: ${correctPattern}`, async function () {
      const req = () =>
        axios({
          url: `${proxyUrl}${correctPattern}`,
        });

      const assertions = (resp) => {
        expect(resp.status, 'Status should be 200').equal(200);
      };

      await retryRequest(req, assertions);
    });
  });

  it('should PATCH the route host', async function () {
    const resp = await axios({
      method: 'patch',
      url: `${routesUrl}/${routeId}`,
      data: {
        hosts: ['test'],
        paths: [routePayload.paths[0]],
      },
      headers: { 'Content-Type': 'application/json' },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').equal(200);
    expect(resp.data.hosts[0], 'Should have correct host').to.equal('test');
    await wait(waitTime);
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
    let resp = await axios({
      method: 'patch',
      url: `${routesUrl}/${routeId}`,
      data: {
        hosts: [currentHost],
      },
      headers: { 'Content-Type': 'application/json' },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').equal(200);
    expect(resp.data.hosts[0], 'Should have correct host').to.equal(
      currentHost
    );

    await waitForConfigRebuild();

    resp = await axios(`${proxyUrl}${routePayload.paths[0]}`);
    expect(resp.status, 'Status should be 200').equal(200);
    logResponse(resp);
  });

  it('should delete the route by name', async function () {
    const resp = await axios({
      method: 'delete',
      url: `${routesUrl}/${routePayload.name}`,
    });

    logResponse(resp);
    expect(resp.status, 'Status should be 204').to.equal(204);
  });

  it('should not panic and create a route with long regex path', async function () {
    // generate string longer than 2048 bytes
    const path = 'x'.repeat(3 * 1024);

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

    await wait(4000);
    const currentLogs = getGatewayContainerLogs(kongContainerName, 15);
    const panickLog = findRegex('panicked', currentLogs);
    const outOfRangeLog = findRegex('out of range', currentLogs);

    expect(panickLog, 'Should not see router panic error log').to.be.false;
    expect(outOfRangeLog, 'Should not see out of range error log').to.be.false;
  });

  after(async function () {
    await deleteGatewayRoute(routeId);
    await deleteGatewayService(serviceName);
  });
});
