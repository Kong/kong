import {
  Environment,
  expect,
  getBasePath,
  getNegative,
  isGateway,
  logResponse,
  vars,
  getKongVersionFromContainer
} from '@support';
import axios from 'axios';

describe('Gateway release package tests', function () {
  this.retries(1)

  const url = getBasePath({
    environment: isGateway() ? Environment.gateway.admin : undefined,
  });
  const proxyUrl = `${getBasePath({
    environment: Environment.gateway.proxy,
  })}`;

  const kongVersion = vars.KONG_VERSION;
  const kongContainerName = vars.KONG_CONTAINER_NAME;

  const name = 'test'
  const path = '/testdefault'

  it('package: should see correct kong version', async function () {
    const resp = await axios(`${url}/`);
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.version, 'Should have correct version').equal(
      kongVersion
    );
  });

  it('package: should get the service by name', async function () {
    const resp = await axios(`${url}/services/${name}`);
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.name, 'Should have correct service name').equal(
      name
    );
  });

  it('debian: should get the route by name', async function () {
    const resp = await axios(`${url}/routes/${name}`);
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.name, 'Should have correct service name').equal(
      name
    );
  });

  it('package: should see RLA plugin', async function () {
    const resp = await axios(`${url}/plugins`);
    logResponse(resp);

    expect(resp.data.data[0].name, 'Plugin name should be correct').to.equal('rate-limiting-advanced');
  });

  it('package: should rate limit on 3rd request', async function () {
    // plugin limit is 2, window_size 10
    for (let i = 0; i <= 7; i++) {
      const resp = await getNegative(`${proxyUrl}${path}`);
      logResponse(resp);

      if (i > 1) {
        expect(resp.status, 'Status should be 429').to.equal(429);
      } else {
        expect(resp.status, 'Status should be 200').to.equal(200);
      }
    }
  });

  it('package: should have correct kong version', async function () {
    const version = getKongVersionFromContainer(kongContainerName);
    expect(version).to.eq(`Kong Enterprise ${kongVersion}`);
  });

});
