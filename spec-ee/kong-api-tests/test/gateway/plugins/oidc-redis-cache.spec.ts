import {
    expect,
    Environment,
    getBasePath,
    createGatewayService,
    createRouteForService,
    waitForConfigRebuild,
    logResponse,
    isGateway,
    getGatewayMode,
    clearAllKongResources,
    getGatewayContainerLogs,
    eventually,
} from '@support'
import axios from 'axios'
import { wait } from 'support/utilities/random'

const urls = {
    admin: `${getBasePath({
        environment: isGateway() ? Environment.gateway.admin : undefined,
    })}`,
    proxySec: `${getBasePath({
        app: 'gateway',
        environment: Environment.gateway.proxySec,
    })}`,
    keycloak: `${getBasePath({
        app: 'gateway',
        environment: Environment.gateway.keycloakSec,
    })}`,
    okta: 'https://kong-sandbox.oktapreview.com/oauth2',
}

const isHybrid = getGatewayMode() === 'hybrid'
const kongContainerName = isHybrid ? 'kong-dp1' : 'kong-cp'
const serviceName = 'oidc-service'

let serviceId: string
let introspectPluginId: string
let passwordPluginId: string

describe('Gateway Plugins: OIDC with Redis Caching for Introspection', function () {
    const keycloakPath = '/oidc'
    const introspectPath = '/introspection'
    const keycloakTokenRequestUrl = `https://keycloak:8543/realms/demo/protocol/openid-connect/token`
    const keycloakIssuerUrl = `https://keycloak:8543/realms/demo`

    let token: string
    let routeId: string
    let introspectRouteId: string
    let introspectionReqId
    let cacheReqId
    let currentLogs

    async function getLogLinesWithGivenRequestId(requestId, logs) {
        //split logs into lines
        const lines = logs.split('\n')
        // filter lines that contain the request id
        return lines.filter((line) => line.includes(requestId)).filter((line) => !line.includes('keycloak'))
    }
    
    async function createOidcPlugin(route, auth_method) {
        // create a plugin to use with password grant
        const resp = await axios({
            method: 'POST',
            url: `${urls.admin}/plugins`,
            data: {
                name: 'openid-connect',
                route: {
                    id: route
                },
                config: {
                    cluster_cache_strategy: 'redis',
                    cluster_cache_redis: {                   
                        host: 'redis',
                        port: 6379,
                        username: 'redisuser',
                        password: 'redispassword',
                    },
                    cache_ttl: 5,
                    cache_ttl_max: 5,
                    client_id: [ 'kong-client-secret' ],
                    client_secret: [ '38beb963-2786-42b8-8e14-a5f391b4ba93' ],
                    auth_methods: [ auth_method ],
                    issuer: keycloakIssuerUrl,
                    token_endpoint: keycloakTokenRequestUrl,
                },
            },
            validateStatus: null,
        })
        return resp
    }

    async function checkLogsForRequest(logs, requestId, idpRequest = false) {
        const lines = await getLogLinesWithGivenRequestId(requestId, logs)

        if (idpRequest) {
            expect(lines.length, 'should reach to IDP for first request').to.equal(2);
            expect(lines[0], 'log should report introspection to IDP').to.contain('introspecting access token with identity provider')
            expect(lines[1], 'log should report success for first request').to.contain('GET /introspection HTTP/1.1" 200')
        } else {
            expect(lines.length, 'should not reach to IDP again for second request').to.equal(1);
            expect(lines[0], 'log should report success for second request').to.include('GET /introspection HTTP/1.1" 200');
        }
    }

    before(async function () {
        const service = await createGatewayService(serviceName)
        serviceId = service.id
        // Create two routes: one for password grant, one for introspection
        const route = await createRouteForService(serviceId, [keycloakPath])
        routeId = route.id
        const introspectRoute = await createRouteForService(serviceId, [introspectPath])
        introspectRouteId = introspectRoute.id
    })

    //======= Redis cluster cache tests ======
    it('should create OIDC plugin using redis as cluster cache backend' , async function() {
        // create a plugin to use with password grant
        const passwordResp = await createOidcPlugin(routeId, 'password')
        expect(passwordResp.status, 'Status should be 201 for password grant plugin').to.equal(201)
        passwordPluginId = passwordResp.data.id

        // Create a second plugin to use introspection after password grant gets token
        const introspectResp = await createOidcPlugin(introspectRouteId, 'introspection')
        expect(introspectResp.status, 'Status should be 201 for introspect plugin').to.equal(201)
        introspectPluginId = introspectResp.data.id

        await waitForConfigRebuild()
    })
    
    it('should not authenticate when accessing route without credentials', async function() {
        const resp = await axios({
            method: 'GET',
            url: `${urls.proxySec}${keycloakPath}`,
            validateStatus: null,
        })
        expect(resp.status, 'Status should be 401').to.equal(401)
    })

    it('should return 200 when accessing route with credentials', async function() {
        // Send request with password credentials
        const resp = await axios({
            method: 'GET',
            url: `${urls.proxySec}${keycloakPath}`,
            headers: {
                Authorization: `Basic john:doe`,
            },
            validateStatus: null,
        })
        expect(resp.status, 'Status should be 200').to.equal(200)
        // save token for introspection
        token = resp.data.headers['Authorization']
        await waitForConfigRebuild()
    })

    it('should not authenticate without token for introspection', async function() {
        const resp = await axios({
            method: 'GET',
            url: `${urls.proxySec}${introspectPath}`,
            validateStatus: null,
        })
        expect(resp.status, 'Status should be 401').to.equal(401)
    })

    it('should not authenticate with invalid token for introspection', async function() {
        const resp = await axios({
            method: 'GET',
            url: `${urls.proxySec}${introspectPath}`,
            headers: {
                Authorization: 'Bearer invalid-token',
            },
            validateStatus: null,
        })
        expect(resp.status, 'Status should be 401').to.equal(401)
    })

    it('should not authenticate accessing introspection endpoint using password grant', async function() {
        const resp = await axios({
            method: 'GET',
            url: `${urls.proxySec}${introspectPath}`,
            headers: {
                Authorization: 'Basic john:doe',
            },
            validateStatus: null,
        })
        expect(resp.status, 'Status should be 401').to.equal(401)
    })

    it('should introspect token successfully', async function() {
        // send introspection token to endpoint set up for introspection
        const resp = await axios({
            method: 'GET',
            url: `${urls.proxySec}${introspectPath}`,
            headers: {
                Authorization: token,
            },
            validateStatus: null,
        })
        expect(resp.status, 'Status should be 200').to.equal(200)
        // get request id from this request to check log lines later
        introspectionReqId = resp.data.headers['X-Kong-Request-Id']
    });

    it('should cache introspection token in redis cluster', async function() {
        // send another request to check caching
        const resp = await axios({
            method: 'GET',
            url: `${urls.proxySec}${introspectPath}`,
            headers: {
                Authorization: token,
            },
            validateStatus: null,
        })
        expect(resp.status, 'Status should be 200').to.equal(200)
        // get request id from this request to check log lines later
        cacheReqId = resp.data.headers['X-Kong-Request-Id']
        // wait for log messages to register
        waitForConfigRebuild()

        // Check Kong logs to ensure introspection wasn't done again
        await eventually(async () => {
            currentLogs = getGatewayContainerLogs(
                kongContainerName, isHybrid ? 250 : 30
            );
        });
        // first request should return introspection line as well as request success line
        await checkLogsForRequest(currentLogs, introspectionReqId, true)
        // second request should only return request success line
        await checkLogsForRequest(currentLogs, cacheReqId)
    });

    it('should not introspect with token after cache expiration', async function() {
        // ensure that cache_ttl applies to redis cache
        // wait for cache to expire
        await wait(6000) // eslint-disable-line no-restricted-syntax
        // send introspection token to endpoint set up for introspection
        const resp = await axios({
            method: 'GET',
            url: `${urls.proxySec}${introspectPath}`,
            headers: {
                Authorization: token,
            },
            validateStatus: null,
        })
        expect(resp.status, 'Status should be 200').to.equal(200)
        // get request id from this request to check log lines later
        introspectionReqId = resp.data.headers['X-Kong-Request-Id']

        // check logs for line indicating that IDP was used, not cache
        await eventually(async () => {
            currentLogs = getGatewayContainerLogs(
                kongContainerName, isHybrid ? 250 : 30
            );
        });
    
        // request should return introspection line as well as request success line
        await checkLogsForRequest(currentLogs, introspectionReqId, true)
    });

    it('should disable redis caching successfully', async function() {
        // update plugin to disable redis caching
        let resp = await axios({
            method: 'PATCH',
            url: `${urls.admin}/plugins/${introspectPluginId}`,
            data: {
                config: {
                    cluster_cache_strategy: 'off',
                },
            },
            validateStatus: null,
        })
        logResponse(resp)
        expect(resp.status, 'Status should be 200').to.equal(200)

        resp =  await axios({
            method: 'PATCH',
            url: `${urls.admin}/plugins/${passwordPluginId}`,
            data: {
                config: {
                    cluster_cache_strategy: 'off',
                },
            },
            validateStatus: null,
        })
        logResponse(resp)
        expect(resp.status, 'Status should be 200').to.equal(200)

        await waitForConfigRebuild()
    })

    it('should introspect token without caching token in redis', async function() {
        // ensure token expires
        await wait(6000) // eslint-disable-line no-restricted-syntax
        // send introspection token to endpoint set up for introspection
        const resp = await axios({
            method: 'GET',
            url: `${urls.proxySec}${introspectPath}`,
            headers: {
                Authorization: token,
            },
            validateStatus: null,
        })
        expect(resp.status, 'Status should be 200').to.equal(200)
        // get request id from this request to check log lines later
        introspectionReqId = resp.data.headers['X-Kong-Request-Id']

        // send second request to show caching is disabled
        const resp2 = await axios({
            method: 'GET',
            url: `${urls.proxySec}${introspectPath}`,
            headers: {
                Authorization: token,
            },
            validateStatus: null,
        })
        expect(resp2.status, 'Status should be 200').to.equal(200)
        // get request id from this request to check log lines later
        cacheReqId = resp2.data.headers['X-Kong-Request-Id']

        await waitForConfigRebuild()

        // Check Kong logs to ensure introspection wasn't done again
        await eventually(async () => {
            currentLogs = getGatewayContainerLogs(
                kongContainerName, isHybrid ? 250 : 30
            );
        });

        // first request should return introspection line as well as request success line
        await checkLogsForRequest(currentLogs, introspectionReqId, true)
        // TODO: automate monitoring redis cache
        // 2 tokens should come in over the test
        // - one from initial introspect test
        // - one from expiry test
        // - this third token should not be cached in redis
    })

    after(async function () {
        await clearAllKongResources()
    })
})
