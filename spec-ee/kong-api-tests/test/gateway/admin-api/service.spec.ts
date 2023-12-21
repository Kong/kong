import {
  deleteGatewayRoute,
  Environment,
  expect,
  getBasePath,
  getNegative,
  logResponse,
  postNegative,
  randomString,
  getKongVersionFromContainer,
  getKongContainerName,
  getKongVersion,
  isKoko,
  isGateway
} from '@support';
import axios, { AxiosResponse } from 'axios';

describe('@smoke @koko: Gateway Admin API: Services', function () {
  let url: string
  let serviceId: string
  let routeId: string;

  before(function () {
    const basePath = getBasePath({
      environment: isGateway() ? Environment.gateway.admin : undefined,
    });
    url = `${basePath}/services`;
  });

  const servicePayload = {
    name: 'APITestService',
    url: 'http://httpbin/anything',
  };
  
  const newPath = '/anythingUpdated';
  const kongContainerName = getKongContainerName();
  const kongVersion = getKongVersion();

  const assertRespDetails = (response: AxiosResponse) => {
    const resp = response.data;
    expect(resp.port, 'Should have port 80').equal(80);
    expect(resp.protocol, 'Should have protocol "http"').equal('http');
    expect(resp.host, 'Should have correct host').equal('httpbin');
    expect(resp.path, 'Should have correct path').equal('/anything');
    expect(resp.connect_timeout, 'Should have correct connect_timeout').equal(
      60000
    );
    expect(resp.read_timeout, 'Should have correct read_timeout').equal(60000);
    expect(resp.write_timeout, 'Should have correct write_timeout').equal(
      60000
    );
    expect(resp.retries, 'Should have 5 retries').equal(5);
    // expect(resp.tags, 'Should not have tags').to.be.null;
    // *** HANDLES NULL OR UNDEFINED **
    expect(resp.tags == null, 'Should not have tags').to.be.true;
    expect(resp.id, 'Should have id of type string').to.be.a('string');
    expect(resp.created_at, 'created_at should be a number').to.be.a('number');
    expect(resp.updated_at, 'updated_at should be a number').to.be.a('number');
  };

  it('should create a service and a route for service', async function () {
    let resp = await axios({
      method: 'post',
      url,
      data: servicePayload
    });

    logResponse(resp);
    expect(resp.status, 'Status should be 201').equal(201);
    expect(resp.data.name, 'Should have correct service name').equal(
      servicePayload.name
    );
    assertRespDetails(resp);
    serviceId = resp.data.id

    resp = await axios({
      method: 'post',
      url: `${url}/${serviceId}/routes`,
      data: {
        name: randomString(),
        paths: [`/${randomString()}`],
      },
    });
    logResponse(resp);
    expect(resp.status, 'Status should be 201').equal(201);
    routeId = resp.data.id;
  });

  it('should not create a service with same name', async function () {
    const resp = await postNegative(url, servicePayload, 'post');
    logResponse(resp);

    // *** RESPONSE DIFFERENCES IN GATEWAY AND KOKO ***
    if (isGateway()) {
      expect(resp.status, 'Status should be 409').equal(409);
      expect(resp.data.name, 'Should have correct error name').equal(
        'unique constraint violation'
      );
      expect(resp.data.message, 'Should have correct error name').equal(
        `UNIQUE violation detected on '{name="${servicePayload.name}"}'`
      );
    } else if (isKoko()) {
      expect(resp.status, 'Status should be 400').to.equal(400);
      expect(resp.data.message, 'Should have correct error name').to.equal(
        'data constraint error'
      );
    }
  });

    it('should not create a service with incorrect path', async function () {
    const wrongPayload = {
      name: 'my-service',
      protocol: 'http',
      port: 8000,
      host: 'httpbin',
      path: 'anything',
    };
    const resp = await postNegative(url, wrongPayload, 'post');
    logResponse(resp);

    expect(resp.status, 'Status should be 400').equal(400);
    // *** RESPONSE DIFFERENCES IN GATEWAY AND KOKO ***
    if (isGateway()) {
      expect(resp.data.name, 'Should have correct error name').equal(
        'schema violation'
      );
      expect(resp.data.message, 'Should have correct error name').contain(
        `schema violation (path: should start with: /`
      );
    } else if (isKoko()) {
      expect(resp.data.message, 'Should have correct error name').to.equal(
        'validation error'
      );
    }
  });

  it('should get the service by name', async function () {
    const resp = await axios(`${url}/${servicePayload.name}`);
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.name, 'Should have correct service name').equal(
      servicePayload.name
    );
    assertRespDetails(resp);
  });

  it('should get the service by id', async function () {
    const resp = await axios(`${url}/${serviceId}`);
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.name, 'Should have correct service name').equal(
      servicePayload.name
    );
    assertRespDetails(resp);
  });

  // *** KOKO DOES NOT PATCH SERVICES BY NAME ***
  if (isGateway()) {
    it('should patch the service', async function () {
      const resp = await axios({
        method: 'patch',
        url: `${url}/${servicePayload.name}`,
        data: {
          protocol: 'https',
          port: 8080,
          path: newPath,
        },
      });
      logResponse(resp);

      expect(resp.status, 'Status should be 200').to.equal(200);
      expect(resp.data.path, 'Should have correct path').equal(newPath);
      expect(resp.data.port, 'Should have port 8080').equal(8080);
      expect(resp.data.protocol, 'Should have protocol "http"').equal('https');
    });
  }

  it('should not get the service by wrong name', async function () {
    const resp = await getNegative(`${url}/wrong`);
    logResponse(resp);

    expect(resp.status, 'Should have correct error code').to.equal(404);
    const errMsg = (resp.data.message || resp.statusText).toLowerCase();
    expect(errMsg, 'Should have correct error message').to.equal('not found');
  });

  it('should not get the service by wrong id', async function () {
    const resp = await getNegative(
      `${url}/650d4122-3928-45a1-909d-73921163bb13`
    );
    logResponse(resp);

    expect(resp.status, 'Should respond with error').to.equal(404);
    const errMsg = (resp.data.message || resp.statusText).toLowerCase();
    expect(errMsg, 'Should have correct error message').to.equal('not found');
  });

  // *** KOKO ALLOWS DELETION -- RETURNS 204 ***
  if (isGateway()) {
    it('should not delete the service when it has associated route', async function () {
      const resp = await postNegative(
        `${url}/${serviceId}`,
        {},
        'delete'
      );
      logResponse(resp);

      expect(resp.status, 'Status should be 400').equal(400);
      expect(resp.data.message, 'Should have correct error message').include(
        `an existing 'routes' entity references this 'services' entity`
      );
    });
  }

  it('should delete the service by id when it has no associated route', async function () {
    await deleteGatewayRoute(routeId);

    const resp = await axios({
      method: 'delete',
      url: `${url}/${serviceId}`
    });
    logResponse(resp);
    expect(resp.status, 'Status should be 204').to.equal(204);
  });

  it('should create a service with url and path specified separately in request', async function () {
    const resp = await axios({
      method: 'post',
      url,
      data: {
        name: servicePayload.name,
        protocol: 'https',
        port: 443,
        host: 'mockbin.org',
        path: '/kongstrongservice',
      },
    });

    logResponse(resp);
    expect(resp.status, 'Status should be 201').equal(201);
    serviceId = resp.data.id
    expect(resp.data.name, 'Should have correct service name').equal(
      servicePayload.name
    );
    expect(resp.data.host, 'Should have correct host').equal('mockbin.org');
    expect(resp.data.path, 'Should have correct path').equal(
      '/kongstrongservice'
    );
  });

  // *** KOKO DOES NOT DELETE SERVICES BY NAME ***
  it('should delete the service by name', async function () {
    const resp = await axios({
      method: 'delete',
      url: `${url}/${isGateway() ? servicePayload.name : serviceId}`
    });
    logResponse(resp);
    expect(resp.status, 'Status should be 204').to.equal(204);
  });

  // run this test only when KONG_PACKAGE env variable is specified
  if (kongContainerName && kongContainerName !== 'kong-cp') {
    it('should have correct kong docker image version', async function () {
      const version = getKongVersionFromContainer(kongContainerName);
      expect(version).to.eq(`Kong Enterprise ${kongVersion}`);
    });
  }
});
