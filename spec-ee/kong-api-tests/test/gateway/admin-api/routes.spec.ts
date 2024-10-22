import {
    Environment,
    expect,
    getBasePath,
    getNegative,
    logResponse,
    postNegative,
    isKoko,
    isGateway,
    randomString,
    deleteGatewayService,
    wait,
    eventually,
    isKongOSS
} from '@support';
import axios, { AxiosResponse } from 'axios';
  
describe('@smoke @gke @oss: Gateway Admin API: Routes', function () {
    let serviceId: string
    let routeId: string;

    const path = `/${randomString()}`;
    const newPath = `/${randomString()}`;
    const routeName = "APITestRoute"
    const basePath = getBasePath({
        environment: isGateway() ? Environment.gateway.admin : undefined,
    });
    const url = `${basePath}/routes`;
    const proxyUrl = getBasePath({
        environment: isGateway() ? Environment.gateway.proxy : undefined,
    });
    const proxyUrlSec = getBasePath({
        environment: isGateway() ? Environment.gateway.proxySec : undefined,
    });

    const servicePayload = {
        name: 'APITestService',
        url: 'http://httpbin/anything',
    };

    const routePayload = {
        methods: ['GET'],
        paths: [path],
        protocols: ['http'],
        strip_path: true,
        preserve_host: false,
    };

    const isGwOSS = isKongOSS();
  
    const assertRespDetails = (response: AxiosResponse) => {
        const resp = response.data;
        expect(resp.paths, 'Should have correct paths').to.deep.equal(routePayload.paths);
        expect(resp.methods, 'Should have correct methods').to.deep.equal(routePayload.methods);
        expect(resp.protocols, 'Should have correct protocols').to.deep.equal(routePayload.protocols);
        expect(resp.strip_path, 'Should have correct strip_path value').equal(routePayload.strip_path);
        expect(resp.preserve_host, 'Should have correct preserve_host value').equal(routePayload.preserve_host);
        expect(resp.https_redirect_status_code, 'Should include default redirect status code').equal(426);
        // *** HANDLES NULL OR UNDEFINED **
        expect(resp.tags == null, 'Should not have tags').to.be.true;
        expect(resp.id, 'Should have id of type string').to.be.a('string');
        expect(resp.created_at, 'created_at should be a number').to.be.a('number');
        expect(resp.updated_at, 'updated_at should be a number').to.be.a('number');
    };

    before(async function () {
        const resp = await axios({
            method: 'post',
            url: `${basePath}/services`,
            data: servicePayload,
        });
        logResponse(resp);
        expect(resp.status, 'Status should be 201').equal(201);
        expect(resp.data.name, 'Should have correct service name').equal(
            servicePayload.name
        );
        
        if (!isGwOSS) {
            expect(resp.headers, 'Should include request id in header').to.have.property('x-kong-admin-request-id');
            expect(resp.headers['x-kong-admin-request-id'], 'request id should be a string').to.be.a('string')
        }
        
        serviceId = resp.data.id
    });
  
    it('should create a global route', async function () {
        const resp = await axios({
            method: 'post',
            url,
            data: {
                ...routePayload,
                name: routeName,
            },
        });
        logResponse(resp);
        routeId = resp.data.id;

        expect(resp.status, 'Status should be 201').equal(201);
        assertRespDetails(resp);
    });

    it('should patch route to be scoped to service', async function () {
        const resp = await axios({
            method: 'PATCH',
            url: `${url}/${routeId}`,
            data: {
                ...routePayload,
                service: { id: serviceId },
            },
        });
        logResponse(resp);
        expect(resp.status, 'Status should be 200').equal(200);
        expect(resp.data.service.id, 'Should be scoped to service').equal(serviceId);
    });
  
    it('should not create a route with empty path', async function () {
        const wrongPayload = {
            name: randomString(),
            paths: [],
        };
        const resp = await postNegative(url, wrongPayload);
        logResponse(resp);
        expect(resp.status, 'Status should be 400').equal(400);
        // *** RESPONSE DIFFERENCES IN GATEWAY AND KOKO ***
        if (isGateway()) {
          expect(resp.data.name, 'Should have correct error name').equal(
            'schema violation'
          );
          expect(resp.data.message, 'Should have correct error name').contain(
            `schema violation (must set one of 'methods', 'hosts'`
          );
        } else if (isKoko()) {
          expect(resp.data.message, 'Should have correct error name').to.equal(
            'validation error'
          );
        }
    });
  
    it('should get the route by name', async function () {
        const resp = await axios({
            method: 'get',
            url: `${url}/${routeName}`,
        });
        logResponse(resp);
        expect(resp.status, 'Status should be 200').to.equal(200);
        assertRespDetails(resp);
    });
  
    it('should get the route by id', async function () {
        const resp = await axios({
            method: 'get',
            url: `${url}/${routeId}`,
        });
        logResponse(resp);
        expect(resp.status, 'Status should be 200').to.equal(200);
        assertRespDetails(resp);
    });
  
    // *** KOKO DOES NOT PATCH ROUTES BY NAME ***
    if (isGateway()) {
      it('should patch the route with new tags', async function () {
        const resp = await axios({
            method: 'patch',
            url: `${url}/${routeName}`,
            data: {
                tags: ['patchedRoutebyName']
            },
        });
        logResponse(resp);
  
        expect(resp.status, 'Status should be 200').to.equal(200);
        expect(resp.data.tags, 'Should have new tag').contain('patchedRoutebyName');
      });
    }

    it('should be able to update route by id with new path', async function () {
        const resp = await axios({
            method: 'patch',
            url: `${url}/${routeId}`,
            data: {
                paths: [newPath],
            },
        });
        logResponse(resp);
        expect(resp.status, 'Status should be 200').to.equal(200);
        expect(resp.data.paths, 'Should have updated path').contain(newPath);
        await wait(5000); // eslint-disable-line no-restricted-syntax
    });
  
    it('should not get the route by wrong name', async function () {
      const resp = await getNegative(`${url}/wrong`);
      logResponse(resp);
  
      expect(resp.status, 'Should have correct error code').to.equal(404);
      const errMsg = (resp.data.message || resp.statusText).toLowerCase();
      expect(errMsg, 'Should have correct error message').to.equal('not found');
    });
  
    it('should not get the route by wrong id', async function () {
      const resp = await getNegative(
        `${url}/650d4122-3928-45a1-909d-73921163bb13`
      );
      logResponse(resp);
  
      expect(resp.status, 'Should respond with error').to.equal(404);
      const errMsg = (resp.data.message || resp.statusText).toLowerCase();
      expect(errMsg, 'Should have correct error message').to.equal('not found');
    });

    it('should be able to send a request to the route', async function () {
        await eventually(async () => {
            const resp = await axios({
                method: 'get',
                url: `${proxyUrl}${newPath}`,
                validateStatus: null,
            });
            logResponse(resp);
            expect(resp.status, 'Status should be 200').to.equal(200);
            expect(resp.headers, 'Should include request id in header').to.have.property('x-kong-request-id');
            expect(resp.headers['x-kong-request-id'], 'request id should be a string').to.be.a('string')
        });
    });

    it('should be able to send a secure request to the route', async function () {
        const resp = await axios({
            method: 'get',
            url: `${proxyUrlSec}${newPath}`,
            validateStatus: null,
        });
        logResponse(resp);
        expect(resp.status, 'Status should be 200').to.equal(200);
        expect(resp.headers, 'Should have request_id').to.have.property('x-kong-request-id');
        expect(resp.headers['x-kong-request-id'], 'request id should be a string').to.be.a('string')
    });
  
    // *** KOKO DOES NOT DELETE ROUTES BY NAME ***
    it('should delete the route', async function () {
        const resp = await axios({
            method: 'delete',
            url: `${url}/${isGateway() ? routeName : routeId}`
        });
        logResponse(resp);
        expect(resp.status, 'Status should be 204').to.equal(204);
    });

    after(async function () {
        // delete service
        await deleteGatewayService(serviceId);
    });
});
  