import { spaceApi } from '@fixtures';
import {
  createGatewayService,
  createRouteForService,
  deleteGatewayRoute,
  deleteGatewayService,
  Environment,
  expect,
  getBasePath,
  getNegative,
  isLocalDatabase,
  isGwHybrid,
  logResponse,
  postNegative,
  wait,
} from '@support';
import axios from 'axios';

describe('Mocking Plugin Tests', function () {
  this.timeout(25000);
  const isHybrid = isGwHybrid();
  const isLocalDb = isLocalDatabase();

  const url = `${getBasePath({
    environment: Environment.gateway.admin,
  })}/plugins`;
  const proxyUrl = getBasePath({
    environment: Environment.gateway.proxy,
  });
  const longWait = 8000;
  const shortWait = isHybrid ? 3000 : 1000;

  const validSpec = JSON.stringify(spaceApi);
  const statusCodeList = [200, 500, 404];
  const minDelay = 0.1;
  const maxDelay = 3;
  const exactDelay = 2000;
  let pluginId: string;
  let serviceId: string;
  let planetRouteId: string;
  let randomRouteId: string;
  let moonRouteId: string;

  let basePayload;

  before(async function () {
    const service = await createGatewayService('MockingService');
    serviceId = service.id;
    const planetRoute = await createRouteForService(serviceId, ['/planets']);
    planetRouteId = planetRoute.id;
    const randomRoute = await createRouteForService(serviceId, [
      '/planets/random',
    ]);
    randomRouteId = randomRoute.id;
    const moonRoute = await createRouteForService(serviceId, ['/moons']);
    moonRouteId = moonRoute.id;

    basePayload = {
      name: 'mocking',
      service: {
        id: serviceId,
      },
    };
  });

  it('should not create mocking plugin without config', async function () {
    const resp = await postNegative(url, basePayload);
    logResponse(resp);

    expect(resp.status, 'Status should be 400').to.equal(400);
    expect(resp.data.message, 'Should have correct error message').to.contain(
      "at least one of these fields must be non-empty: 'config.api_specification_filename', 'config.api_specification'"
    );
  });

  it('should not create mocking plugin with invalid config', async function () {
    const payload = {
      ...basePayload,
      config: {
        api_specification: 'not valid',
      },
    };

    const resp = await postNegative(url, payload);
    logResponse(resp);

    expect(resp.status, 'Status should be 400').to.equal(400);
    expect(resp.data.message, 'Should have correct error message').to.contain(
      'api_specification is neither valid json nor valid yaml'
    );
  });

  // Skipping until resolved: https://konghq.atlassian.net/browse/FT-3568
  it.skip('should not create mocking plugin with max_delay_time less than min_delay_time', async function () {
    const payload = {
      ...basePayload,
      config: {
        api_specification: validSpec,
        random_delay: true,
        min_delay_time: 5,
        max_delay_time: 1,
      },
    };

    const resp = await postNegative(url, payload);
    logResponse(resp);

    expect(resp.status, 'Status should be 400').to.equal(400);
    expect(resp.data.message, 'Should have correct error message').to.contain(
      'max_delay_time must be greater than min_delay_time'
    );
  });

  it('should create mocking plugin with valid config', async function () {
    const payload = {
      ...basePayload,
      config: {
        api_specification: validSpec,
      },
    };

    const resp = await axios({
      url: url,
      method: 'post',
      data: payload,
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 201').to.equal(201);
    expect(
      resp.data.config.api_specification,
      'Response should contain API Specification'
    ).to.contain('"title":"Space API"');

    pluginId = resp.data.id;

    // give plugin time to take effect
    await wait(longWait);
  });

  it('should return expected mock response', async function () {
    await wait(isLocalDb ? shortWait : longWait);
    const resp = await axios(`${proxyUrl}/planets`);
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.planets, 'Should include expected data').to.have.length(8);
    expect(resp.headers, 'Should include mocking header').to.include({
      'x-kong-mocking-plugin': 'true',
    });
  });

  it('should return expected examples from random_examples set', async function () {
    const payload = {
      ...basePayload,
      config: {
        random_examples: true,
      },
    };

    const update = await axios({
      url: `${url}/${pluginId}`,
      method: 'patch',
      data: payload,
    });

    expect(update.status, 'Status should be 200 when updating plugin').to.equal(
      200
    );

    await wait(shortWait);

    // send 5 requests and ensure each time we get an expected example
    for (let i = 0; i < 5; i++) {
      const resp = await axios(`${proxyUrl}/planets/random`);
      logResponse(resp);

      expect(resp.status, 'Status should be 200').to.equal(200);
      expect(resp.data.name, 'Should be one of expected examples').to.be.oneOf([
        'Earth',
        'Neptune',
        'Venus',
      ]);
    }
  });

  it('should mock request with expected delay between min and max_delay_time', async function () {
    const payload = {
      ...basePayload,
      config: {
        api_specification: validSpec,
        random_delay: true,
        min_delay_time: minDelay,
        max_delay_time: maxDelay,
      },
    };

    const update = await axios({
      url: `${url}/${pluginId}`,
      method: 'patch',
      data: payload,
    });

    expect(update.status, 'Status should be 200 when updating plugin').to.equal(
      200
    );

    await wait(longWait);

    // send 5 requests and ensure each has expected delay
    for (let i = 0; i < 5; i++) {
      const resp = await axios(`${proxyUrl}/planets/random`);
      logResponse(resp);

      expect(resp.status, 'Status should be 200').to.equal(200);
      // convert latency from ms to s and check if within 10% of expected delays
      expect(parseInt(resp.headers['x-kong-response-latency']) / 1000)
        .to.be.lessThan(maxDelay + maxDelay * 0.1)
        .and.greaterThan(minDelay - minDelay * 0.1);
    }
  });

  // below tests address FT-3178 - https://konghq.atlassian.net/browse/FT-3178
  it('should mock response with given delay when using delay behavioral header', async function () {
    // send 5 requests and ensure each has expected delay
    // min and max delay should be ignored
    for (let i = 0; i < 5; i++) {
      const resp = await axios({
        url: `${proxyUrl}/planets/random`,
        headers: { 'X-Kong-Mocking-Delay': exactDelay },
      });
      expect(resp.status, 'Status should be 200').to.equal(200);
      // check if latency is within 10% of expected delay
      expect(parseInt(resp.headers['x-kong-response-latency']))
        .to.be.lessThan(exactDelay + exactDelay * 0.1)
        .and.greaterThan(exactDelay - exactDelay * 0.1);
    }
  });

  it('should mock response with specific example when using example id behavioral header', async function () {
    const resp = await axios({
      url: `${proxyUrl}/planets/random`,
      headers: { 'X-Kong-Mocking-Example-Id': 'earth' },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.name, 'Data should match expected example').to.equal(
      'Earth'
    );
  });

  it('should return error when using example id behavioral header with wrong id', async function () {
    const resp = await getNegative(`${proxyUrl}/planets/random`, {
      'X-Kong-Mocking-Example-Id': 'jupiter',
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 400').to.equal(400);
    expect(resp.data.message, 'Should have expected error message').to.contain(
      "could not find the example id 'jupiter'"
    );
  });

  it('should mock response with specific status code when using status code behavioral header', async function () {
    const resp = await getNegative(`${proxyUrl}/planets/random`, {
      'X-Kong-Mocking-Status-Code': '404',
    });
    expect(resp.status, 'Status should be 404').to.equal(404);
    expect(resp.data.error, 'Data should match expected example').to.contain(
      'Your planets are in another universe!'
    );
  });

  it('should mock response with different status codes', async function () {
    const payload = {
      ...basePayload,
      config: {
        included_status_codes: statusCodeList,
        random_status_code: true,
      },
    };

    const update = await axios({
      url: `${url}/${pluginId}`,
      method: 'patch',
      data: payload,
    });

    expect(update.status, 'Should update plugin successfully').to.equal(200);

    await wait(shortWait);

    for (let i = 0; i < 5; i++) {
      const resp = await getNegative(`${proxyUrl}/planets/random`);
      logResponse(resp);

      expect(resp.status, 'Should return expected status').to.be.oneOf(
        statusCodeList
      );
      if (resp.status === 200) {
        expect(
          resp.data,
          'Should return planet info with status 200'
        ).to.have.property('day_length_earth_days');
      } else if (resp.status === 404) {
        expect(
          resp.data.error,
          'Should return error message with status 404'
        ).to.equal('Your planets are in another universe!');
      } else if (resp.status === 500) {
        expect(
          resp.data.error,
          'Should return error message with status 500'
        ).to.equal('Bzzzzzt. We need to reboot the universe.');
      }
    }
  });

  it('should mock random example response using schemas', async function () {
    const resp = await axios(`${proxyUrl}/moons`);
    logResponse(resp);

    expect(resp.status, 'Should return 200 response').to.equal(200);
    expect(
      resp.data.orbiting,
      'Should have expected type for "orbiting"'
    ).to.be.a('string');
    expect(
      resp.data.diameter_mi,
      'Should have expected type for "diameter_mi"'
    ).to.be.an('number');
    expect(resp.data.name, 'Should have expected type for "name"').to.be.a(
      'string'
    );
  });

  after(async function () {
    await deleteGatewayRoute(moonRouteId);
    await deleteGatewayRoute(planetRouteId);
    await deleteGatewayRoute(randomRouteId);
    await deleteGatewayService(serviceId);
  });
});
