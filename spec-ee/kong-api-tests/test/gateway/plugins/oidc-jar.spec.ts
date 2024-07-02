import {
    expect,
    Environment,
    getBasePath,
    createGatewayService,
    createRouteForService,
    waitForConfigRebuild,
    logResponse,
    isGateway,
    clearAllKongResources,
    generateJWT,
    getKeycloakLogs,
    submitLoginInfo
} from '@support'
import {
    authDetails,
} from '@fixtures'
import axios from 'axios'

const jwk = authDetails.keycloak.client_jwk

const urls = {
    // eslint-disable-next-line no-restricted-syntax
    admin: `${getBasePath({
        environment: isGateway() ? Environment.gateway.admin : undefined,
    })}`,
    proxy: `${getBasePath({
        app: 'gateway',
        environment: Environment.gateway.proxy,
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

const serviceName = 'oidc-service'

let serviceId: string
let oidcPluginId: string

// Skip this test suite for packages to investigate the error when creating OIDC plugin
describe('Gateway Plugins: OIDC with Keycloak and JAR/JARM', function () {
    const keycloakPath = '/oidc'
    const keycloakAuthUrl = `${urls.keycloak}/realms/demo/protocol/openid-connect/auth`
    const keycloakIssuerUrl = `${urls.keycloak}/realms/demo`

    const jwtClientId = 'kong-private-key-jwt'

    let redirectLocation: string
    
    // gets the action url from HTML
    const getActionUrl = (resp) => {
        return resp.data.match(/action="([^"]*)/)[1].replace(/&amp;/g, '&').replace('keycloak', 'localhost')
    }
    // gets set cookie and formats it for submission in auth request
    const getCookie = (resp) => {
        return resp.headers['set-cookie']?.filter((cookie: string) => !cookie.includes('AUTH_SESSION_ID='))
    }


    before(async function () {
        const service = await createGatewayService(serviceName)
        serviceId = service.id
        await createRouteForService(serviceId, [keycloakPath])
    })

    //======= JAR tests =======
    it('should create OIDC plugin with JAR configurations', async function () {
        const resp = await axios({
            method: 'POST',
            url: `${urls.admin}/services/${serviceId}/plugins`,
            data: {
                name: 'openid-connect',
                config: {
                    client_id: [ jwtClientId ],
                    auth_methods: [ 'bearer' ],
                    require_signed_request_object: true,
                    issuer: keycloakIssuerUrl,
                    client_auth: [ 'private_key_jwt' ], 
                    client_jwk: [ jwk ],    
                    preserve_query_args: true,
                    authorization_endpoint: `${urls.keycloak}/realms/demo/protocol/openid-connect/auth`,
                },
            },
            validateStatus: null,
        })
        logResponse(resp)
        expect(resp.status, 'Status should be 201').to.equal(201)
        oidcPluginId = resp.data.id
        await waitForConfigRebuild()
    })

    it('should not validate authorization request without signed request object', async function() {
        const resp = await axios({
            method: 'GET',
            url: keycloakAuthUrl,
            params: {
                client_id: jwtClientId,
            },
            validateStatus: null,
        })
        expect(resp.status, 'Status should be 400').to.equal(400)
        expect(resp.data, 'Error message should reference invalid redirect uri').to.contain('Invalid parameter: redirect_uri')

        const keycloakLogs = await getKeycloakLogs('keycloak')
        expect(keycloakLogs, 'Error message in keycloak should reference invalid redirect uri').to.contain('error=invalid_redirect_uri')
    })

    it('should not validate auth request without client id', async function() {
        const signedJwt = await generateJWT(jwtClientId, keycloakPath, `${urls.proxy}${keycloakPath}`)
        const resp = await axios({
            method: 'GET',
            url: keycloakAuthUrl,
            params: {
                request: signedJwt,
            },
            validateStatus: null,
        })
        expect(resp.status, 'Status should be 400').to.equal(400)
        expect(resp.data, 'Error message should reference invalid request').to.contain('Invalid Request')

        const currentLogs = await getKeycloakLogs('keycloak')
        expect(currentLogs, 'Keycloak error logs should reference client id').to.contain("Parameter 'client_id' not present or present multiple times in the HTTP request parameters")
    });

    it('should not validate authorization request with invalid signed request object', async function() {
        const resp = await axios({
            method: 'GET',
            url: keycloakAuthUrl,
            params: {
                client_id: jwtClientId,
                request: 'invalid-signed-request-object',
            },
            validateStatus: null,
        })
        expect(resp.status, 'Status should be 400').to.equal(400)
        expect(resp.data, 'Error message should reference invalid request').to.contain('Invalid Request')

        const currentLogs = await getKeycloakLogs('keycloak')
        expect(currentLogs, 'Keycloak error message should reference invalid request').to.contain('error=invalid_request')
    })

    it('should not validate auth request with JWT with no client in signed request object', async function() {
        const signedJwt = await generateJWT('', keycloakPath, `${urls.proxy}${keycloakPath}`)
        const resp = await axios({
            method: 'GET',
            url: keycloakAuthUrl,
            params: {
                client_id: jwtClientId,
                request: signedJwt,
            },
            validateStatus: null,
        })
        expect(resp.status, 'Status should be 400').to.equal(400)
        expect(resp.data, 'Error message should reference invalid request').to.contain('Invalid Request')

        const currentLogs = await getKeycloakLogs('keycloak')
        expect(currentLogs, 'Keycloak error message should reference invalid request').to.contain('error=invalid_request')
    });

    it('should not validate auth request with JWT with no redirect uri', async function() {
        const signedJwt = await generateJWT(jwtClientId, keycloakPath, null)
        const resp = await axios({
            method: 'GET',
            url: keycloakAuthUrl,
            params: {
                client_id: jwtClientId,
                request: signedJwt,
            },
            validateStatus: null,
        })
        expect(resp.status, 'Status should be 400').to.equal(400)
        expect(resp.data, 'Error message should reference invalid redirect uri').to.contain('Invalid parameter: redirect_uri')
        
        const currentLogs = await getKeycloakLogs('keycloak')
        expect(currentLogs, 'Keycloak error logs should reference invalid redirect uri').to.contain('error=invalid_redirect_uri')
    });
        
    it('should send authorization request using JAR', async function() {
        // create JWT
        const signedJwt = await generateJWT(jwtClientId, keycloakPath, `${urls.proxy}${keycloakPath}`)

        // send authorization request
        const resp = await axios({
            method: 'GET',
            url: keycloakAuthUrl,
            // use JAR as request param
            params: {
                client_id: jwtClientId,
                request: signedJwt,
            },
            validateStatus: null,
        })
        expect(resp.status, 'Status should be 200').to.equal(200)
    })
        
    //======= JARM tests =======
    it('should update OIDC plugin with JARM configurations', async function () {
        const resp = await axios({
            method: 'PATCH',
            url: `${urls.admin}/plugins/${oidcPluginId}`,
            data: {
                name: 'openid-connect',
                config: {
                    client_id: [ 'kong-client-secret' ],
                    client_secret: [ '38beb963-2786-42b8-8e14-a5f391b4ba93' ],
                    issuer: keycloakIssuerUrl,
                    response_mode: 'jwt',
                    require_signed_request_object: false, 
                    login_action: 'upstream',
                    login_tokens: {},
                    auth_methods: [ 'authorization_code', 'session' ],
                    preserve_query_args: true,
                    authorization_endpoint: `${urls.keycloak}/realms/demo/protocol/openid-connect/auth`,
                    client_auth: [ ], 
                    client_jwk: [ ],    
                },
            },
            validateStatus: null,
        })
        logResponse(resp)
        expect(resp.status, 'Status should be 200').to.equal(200)

        oidcPluginId = resp.data.id

        await waitForConfigRebuild()
    })

    it('should not validate auth request without cookie', async function() {
        const resp = await axios({
            method: 'GET',
            headers: {
                "Host": "localhost:8000",
            },
            url: `${urls.proxy}${keycloakPath}`,
            validateStatus: null,
            maxRedirects: 1,
        })
        logResponse(resp)
        expect(resp.status, 'Status should be 200').to.equal(200)
        expect(resp.headers, 'Should send Set-Cookie header').to.have.property('set-cookie')

        const actionUrl = getActionUrl(resp)
        const loginResp = await submitLoginInfo(actionUrl, 'john', 'doe', '')

        expect(loginResp.status, 'Status should be 400').to.equal(400)
        expect(loginResp.data, 'Error message should reference lack of cookie').to.contain('Cookie not found. Please make sure cookies are enabled in your browser')

        const currentLogs = await getKeycloakLogs('keycloak')
        expect(currentLogs, 'Keycloak error logs should reference lack of cookie').to.contain('error=cookie_not_found')
    });

    it('should not validate auth request with missing username', async function() {
        const resp = await axios({
            method: 'GET',
            headers: {
                "Host": "localhost:8000",
            },
            url: `${urls.proxy}${keycloakPath}`,
            validateStatus: null,
            maxRedirects: 1,
        })
        expect(resp.status, 'Status should be 200').to.equal(200)
        expect(resp.headers, 'Should send set-cookie header').to.have.property('set-cookie')
        const actionUrl = getActionUrl(resp)
        const cookie = getCookie(resp)

        const loginResp = await submitLoginInfo(actionUrl, '', 'doe', cookie)
        const currentLogs = await getKeycloakLogs('keycloak')

        expect(loginResp.status, 'Status should be 200').to.equal(200)
        expect(loginResp.data, 'Error message should reference invalid username/password').to.contain('Invalid username or password')
        expect(currentLogs, 'Keycloak error message should reference invalid user').to.contain('error=user_not_found')
    });

    it('should not validate auth request with missing password', async function() {
        const resp = await axios({
            method: 'GET',
            headers: {
                "Host": "localhost:8000",
            },
            url: `${urls.proxy}${keycloakPath}`,
            validateStatus: null,
            maxRedirects: 1,
        })
        expect(resp.status, 'Status should be 200').to.equal(200)
        expect(resp.headers, 'Should send set-cookie header').to.have.property('set-cookie')

        const actionUrl = getActionUrl(resp)
        const cookie = getCookie(resp)
        const loginResp = await submitLoginInfo(actionUrl, 'john', '', cookie)
        const currentLogs = await getKeycloakLogs('keycloak')

        expect(loginResp.status, 'Status should be 200').to.equal(200)
        expect(loginResp.data, 'Error message should reference invalid user/password').to.contain('Invalid username or password')
        expect(currentLogs).to.contain('error=invalid_user_credentials')
    });
        
    it('should send authorization request and get JARM response', async function() {
        // validate that JARM is working by sending request and checking if response is in JARM format
        let resp = await axios({
            method: 'GET',
            headers: {
                "Host": "localhost:8000",
            },
            url: `${urls.proxy}${keycloakPath}`,
            validateStatus: null,
            maxRedirects: 1,
        })
        logResponse(resp)
        expect(resp.status, 'Status should be 200').to.equal(200)
        expect(resp.headers, 'Should send set-cookie header').to.have.property('set-cookie')
        // get actionurl from html, replace keycloak with localhost for proper routing
        const actionUrl = getActionUrl(resp)
        // create an object, cookie, that is set-cookies except it does NOT contain AUTH_SESSION_ID
        const cookies = getCookie(resp)

        // submit login info via urlencoded form
        resp = await submitLoginInfo(actionUrl, 'john', 'doe', cookies)
        redirectLocation = resp.headers.location
        // check JARM - should be in location
        expect(redirectLocation, 'Redirect location should contain JARM').to.contain('response')

        const jwt = redirectLocation.split('response=')[1]
        //check that jwt is valid by coverting to object and checking each claim and header part
        const decoded = jwt.split('.')
        const claims = JSON.parse(Buffer.from(decoded[1], 'base64').toString('utf-8'))
        const header = JSON.parse(Buffer.from(decoded[0], 'base64').toString('utf-8'))
        
        expect(header['typ'], 'Header should have type JWT').to.equal('JWT')
        expect(header['alg'], 'Algorithm should be RS256').to.equal('RS256')
        // host returns as keycloak due to docker config
        expect(claims['iss'], 'Iss should match issuer').to.equal(keycloakIssuerUrl.replace('localhost', 'keycloak'))
        expect(claims['aud'], 'Aud should be client').to.equal('kong-client-secret')
        expect(claims['exp'], 'Exp should be in the future').to.be.greaterThan(Math.floor(Date.now() / 1000))
        expect(claims['code'], 'Code should be a string').to.be.a('string')
    })
        
    it('should delete OIDC plugin', async function () {
        const resp = await axios({
            method: 'DELETE',
            url: `${urls.admin}/plugins/${oidcPluginId}`,
        })
        expect(resp.status, 'status should be 204').to.equal(204)
    })

    after(async function () {
        await clearAllKongResources()
    })
})