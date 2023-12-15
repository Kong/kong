import axios from 'axios';
import { 
  expect, 
  createGatewayService, 
  Environment, 
  getBasePath, 
  logResponse, 
  setGatewayContainerEnvVariable, 
  waitForConfigRebuild,
  getRouterFlavor, 
  isGwHybrid,
  wait,
  getKongContainerName,
} from '@support';

describe('Expressions Router Tests', function () {
  const serviceName = 'expressionsService';
  const simpleExpression = '(http.path == "/first_path") || (http.path == "/second_path")';
  const simpleExpressionUpdate = encodeURIComponent('(http.path == "/third_path" && http.method == "PUT")');
  const complexExpression = encodeURIComponent('(http.path == "/only_path" && http.method == "GET" && http.headers.x_required_header == "present")');
  const languageExpression = encodeURIComponent('(http.path ^= "/prefix") && (http.path =^ "/suffix")');

  const timeout = 10000;
  const interval = 1000;

  // router flavors
  const expressions = 'expressions'
  const traditional = 'traditional_compatible'
  const gwContainerName = getKongContainerName();

  const url = `${getBasePath({
    environment: Environment.gateway.admin,
  })}`;
  const proxyUrl = `${getBasePath({
    environment: Environment.gateway.proxy,
  })}`;

  let serviceId: string;
  let routeId: string;

  async function waitForTargetRouterFlavor(flavor, timeout, interval) {
    while(await getRouterFlavor() !== flavor && timeout > 0) {
      await new Promise((resolve) => setTimeout(resolve, interval));
      timeout -= interval;
    }
  }

  before(async function () {
    setGatewayContainerEnvVariable({ KONG_ROUTER_FLAVOR: expressions }, gwContainerName);
    if (isGwHybrid()) {
      setGatewayContainerEnvVariable({ KONG_ROUTER_FLAVOR: expressions }, 'kong-dp1');
      // need to wait for DP to restart and reconnect to CP
      // eslint-disable-next-line no-restricted-syntax
      await wait(timeout);
    }


   await waitForTargetRouterFlavor(expressions, timeout, interval);

    const service = await createGatewayService(serviceName);
    serviceId = service.id;

    await waitForConfigRebuild({timeout: 50000});
  });

  it('should not create route without expression', async function () {
    const resp = await axios({
      url: `${url}/services/${serviceId}/routes`,
      method: 'post',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      validateStatus: null,
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 400').to.equal(400);
    expect(resp.data.message, 'Should return correct error message').to.equal(
      'schema violation (expression: required field missing)',
    );
  });

  it('should not create route with malformed expression route', async function () {
    const resp = await axios({
      url: `${url}/services/${serviceId}/routes`,
      method: 'post',
      data: `expression=><dfdk44335430$#`,
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      validateStatus: null,
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 400').to.equal(400);
    expect(resp.data.message, 'Should return correct error message').to.contain('Router Expression failed validation');
  });

  it('should create a simple expression route', async function () {
    const resp = await axios({
      url: `${url}/services/${serviceId}/routes`,
      method: 'post',
      data: `expression=${simpleExpression}`,
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      validateStatus: null,
    });
    logResponse(resp);
    expect(resp.status, 'Status should be 201').to.equal(201);
    expect(resp.data.id, 'Should return route id').to.exist;
    routeId = resp.data.id;

  });

  it('should route correctly using the expressions router', async function () {
    await waitForConfigRebuild({timeout: 50000});

    let resp = await axios({
      method: 'get',
      url: `${proxyUrl}/first_path`,
      validateStatus: null,
    });
    expect(resp.status, 'Status should be 200').to.equal(200);

    resp = await axios({
      method: 'get',
      url: `${proxyUrl}/second_path`,
      validateStatus: null,
    });
    expect(resp.status, 'Status should be 200').to.equal(200);
  });

  it('should return 404 when route does not match expression', async function () {
    const resp = await axios({
      method: 'get',
      url: `${proxyUrl}/third_path`,
      validateStatus: null,
    });
    expect(resp.status, 'Status should be 404').to.equal(404);
  });

  it('should modify route with new expression', async function () {
    const resp = await axios({
      method: 'patch',
      url: `${url}/services/${serviceId}/routes/${routeId}`,
      data: `expression=${simpleExpressionUpdate}`,
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      validateStatus: null,
    });
    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.id, 'Should return route id').to.exist;
  });

  it('should not modify route with invalid expression', async function () {
    const resp = await axios({
      method: 'patch',
      url: `${url}/services/${serviceId}/routes/${routeId}`,
      data: `expression=dkasodaosaj`,
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      validateStatus: null,
    });
    expect(resp.status, 'Status should be 400').to.equal(400);
    expect(resp.data.message, 'Should return correct error message').to.contain('Router Expression failed validation');
  });

  it('should route with new expression', async function () {
    await waitForConfigRebuild({timeout: 50000});
    const resp = await axios({
      method: 'put',
      url: `${proxyUrl}/third_path`,
      validateStatus: null,
    });
    expect(resp.status, 'Status should be 200').to.equal(200);
  });

  it('should return 404 when route does not match expression', async function () {
    // wrong path
    let resp = await axios({
      method: 'put',
      url: `${proxyUrl}/wrong_path`,
      validateStatus: null,
    });
    expect(resp.status, 'Status should be 404').to.equal(404);

    // wrong method
    resp = await axios({
      method: 'get',
      url: `${proxyUrl}/third_path`,
      validateStatus: null,
    });
    expect(resp.status, 'Status should be 404').to.equal(404);
  });

  it('should modify route with complex expression', async function () {
    const resp = await axios({
      method: 'patch',
      url: `${url}/services/${serviceId}/routes/${routeId}`,
      data: `expression=${complexExpression}`,
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      validateStatus: null,
    });
    logResponse(resp);
    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.id, 'Should return route id').to.exist;
  });

  it('should route correctly with complex expression', async function () {
    await waitForConfigRebuild({timeout: 50000});

    const resp = await axios({
      url: `${proxyUrl}/only_path`,
      headers: {
        'x_required_header': 'present',
      },
      validateStatus: null,
    });

    expect(resp.status, 'Status should be 200').to.equal(200);
  });

  it('should return 404 when only supplying some of the required expression parameters', async function () {
    let resp = await axios({
      url: `${proxyUrl}/only_path`,
      validateStatus: null,
    });
    expect(resp.status, 'Status should be 404').to.equal(404);

    resp = await axios({
      method: 'put',
      url: `${proxyUrl}/only_path`,
      headers: {
        'x_required_header': 'present',
      },
      validateStatus: null,
    });
    expect(resp.status, 'Status should be 404').to.equal(404);
  });

  it('should update route with language expression', async function () {  
    const resp = await axios({
      method: 'patch',
      url: `${url}/services/${serviceId}/routes/${routeId}`,
      data: `expression=${languageExpression}`,
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      validateStatus: null,
    });
    logResponse(resp);
    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.id, 'Should return route id').to.exist;
  });

  it('should route correctly with language expression', async function () {
    await waitForConfigRebuild({timeout: 50000});

    const resp = await axios({
      url: `${proxyUrl}/prefix/middle_bit/suffix`,
      validateStatus: null,
    });

    expect(resp.status, 'Status should be 200').to.equal(200);
  });

  it('should return 404 when route does not match language expression', async function () {
    let resp = await axios({
      url: `${proxyUrl}/noprefix/suffix_path`,
      validateStatus: null,
    });

    expect(resp.status, 'Status should be 404').to.equal(404);

    resp = await axios({
      url: `${proxyUrl}/prefix/nosuffix`,
      validateStatus: null,
    });

    expect(resp.status, 'Status should be 404').to.equal(404);
  });

  it('should delete route', async function () {
    const resp = await axios({
      method: 'delete',
      url: `${url}/services/${serviceId}/routes/${routeId}`,
    });
    expect(resp.status, 'Status should be 204').to.equal(204);
  });

  after(async function () {
    await axios({
      method: 'delete',
      url: `${url}/services/${serviceId}`,
    });
    setGatewayContainerEnvVariable({ KONG_ROUTER_FLAVOR: traditional }, gwContainerName);
    if (isGwHybrid())  {
      setGatewayContainerEnvVariable({ KONG_ROUTER_FLAVOR: traditional }, 'kong-dp1');
      // eslint-disable-next-line no-restricted-syntax
      await wait(timeout) // wait for DP to restart and reconnect to CP
    }
    await waitForTargetRouterFlavor(traditional, timeout, interval);
  });
});
