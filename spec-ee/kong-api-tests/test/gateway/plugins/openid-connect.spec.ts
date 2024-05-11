import {
    expect,
    Environment,
    getBasePath,
    createGatewayService,
    createRouteForService,
    deletePlugin,
    waitForConfigRebuild,
    logResponse,
    isGateway,
    resetGatewayContainerEnvVariable,
    getKongContainerName,
    getGatewayMode,
    clearAllKongResources,
} from '@support'
import {
    authDetails,
} from '@fixtures'
import axios from 'axios'
import https from 'https'
import querystring from 'querystring'

describe('Gateway Plugins: OIDC with Keycloak', function () {
    const path = '/oidc'
    const serviceName = 'oidc-service'

    const invalidCertificate = authDetails.keycloak.invalid_cert
    const invalidKey = authDetails.keycloak.invalid_key

    const clientCertificate = authDetails.keycloak.client_cert
    const clientKey = authDetails.keycloak.client_key

    const certHttpsAgent = new https.Agent({
        cert: clientCertificate,
        key: clientKey,
        rejectUnauthorized: false,
    })

    // use to authenticate token request
    const certClientId = 'kong-certificate-bound'
    const certClientSecret = '670f2328-85a0-11ee-b9d1-0242ac120002'
    const mtlsClientId = 'kong-client-tls-auth'

    let serviceId: string
    let tlsPluginId: string
    let oidcPluginId: string
    let certId: string
    let invalidCertId: string
    let expiredCertId: string
    let token: string

    const isHybrid = getGatewayMode() === 'hybrid'
    const url = `${getBasePath({
        environment: isGateway() ? Environment.gateway.admin : undefined,
    })}`
    const proxyUrl = `${getBasePath({
        app: 'gateway',
        environment: Environment.gateway.proxySec,
    })}`

    const keycloakUrl = `${getBasePath({
        app: 'gateway',
        environment: Environment.gateway.keycloakSec,
    })}/realms/demo`

    const tokenRequestUrl = `${keycloakUrl}/protocol/openid-connect/token`
    const issuerUrl = 'https://keycloak:8543/realms/demo/'

    const kongContainerName = getKongContainerName();
    const kongDpContainerName = 'kong-dp1';

    before(async function () {
        //set KONG_LUA_SSL_TRUSTED_CERTIFICATE value to root/intermediate CA certificates
        await resetGatewayContainerEnvVariable(
            {
                KONG_LUA_SSL_TRUSTED_CERTIFICATE: '/tmp/root_ca.crt,/tmp/intermediate_ca.crt',
            },
            kongContainerName
        );

        if (isHybrid) {
            await resetGatewayContainerEnvVariable(
                {
                    KONG_LUA_SSL_TRUSTED_CERTIFICATE: '/tmp/root_ca.crt,/tmp/intermediate_ca.crt',
                },
                kongDpContainerName
            );
        }
        const service = await createGatewayService(serviceName)
        serviceId = service.id
        await createRouteForService(serviceId, [path])

        const validCert = await axios({
            method: 'POST',
            url: `${url}/certificates`,
            data: {
                cert: clientCertificate,
                key: clientKey,
            },
            validateStatus: null,
        })
        certId = validCert.data.id

        const invalidCert = await axios({
            method: 'POST',
            url: `${url}/certificates`,
            data: {
                cert: invalidCertificate,
                key: invalidKey,
            },
            validateStatus: null,
        })
        invalidCertId = invalidCert.data.id

        // Create TLS plugin for certificate-based tokens
        const resp = await axios({
            method: 'POST',
            url: `${url}/services/${serviceId}/plugins`,
            data: { name: 'tls-handshake-modifier' },
        })
        tlsPluginId = resp.data.id
    })

    it('should create OIDC plugin with certificate-based tokens enabled', async function () {
        const resp = await axios({
            method: 'POST',
            url: `${url}/services/${serviceId}/plugins`,
            data: {
                name: 'openid-connect',
                config: {
                    client_id: [ certClientId ],
                    client_secret: [ certClientSecret ],
                    auth_methods: [ 'bearer' ],
                    issuer: issuerUrl,
                    proof_of_possession_mtls: 'strict',
                    ignore_signature: [ 'client_credentials' ],
                    cache_tokens: false,
                    cache_introspection: false,
                    cache_user_info: false,
                },
            },
            validateStatus: null,
        })
        logResponse(resp)
        expect(resp.status).to.equal(201)
        oidcPluginId = resp.data.id
        await waitForConfigRebuild()
    })

    it('should not be able to request a token without a valid certificate', async function() {
        const resp = await axios({
            method: 'POST',
            url: tokenRequestUrl,
            data: querystring.stringify({
                grant_type: 'client_credentials',
                client_id: certClientId,
                client_secret: certClientSecret,
            }),
            validateStatus: null,
        })
        logResponse(resp)
        expect(resp.status).to.equal(400)
        expect(resp.data.error_description).to.equal('Client Certification missing for MTLS HoK Token Binding')
    })

    it('should return 401 when accessing route without certificate in request', async function() {
        const resp = await axios({
            method: 'GET',
            url: `${proxyUrl}${path}`,
            headers: {
                Authorization: `Bearer ${token}`,
            },
            validateStatus: null,
        })
        expect(resp.status).to.equal(401)
        expect(resp.data.message).to.equal('Unauthorized')
    })

    it('should be able to request token with valid certificate provided', async function() {
        const resp = await axios({
            method: 'POST',
            url: tokenRequestUrl,
            data: querystring.stringify({
                grant_type: 'client_credentials',
                client_id: certClientId,
                client_secret: certClientSecret,
            }),
            httpsAgent: certHttpsAgent,
        })
        logResponse(resp)
        expect(resp.status).to.equal(200)
        token = resp.data.access_token
    })

    it('should return 401 when accessing route with certificate but no token', async function() {
        const resp = await axios({
            method: 'GET',
            url: `${proxyUrl}${path}`,
            validateStatus: null,
            httpsAgent: certHttpsAgent,
        })
        expect(resp.status).to.equal(401)
    })

    it('should return 401 when accessing route with incorrect certificate', async function() {
        const resp = await axios({
            method: 'GET',
            url: `${proxyUrl}${path}`,
            headers: {
                Authorization: `Bearer ${token}`,
            },
            httpsAgent: new https.Agent({
                cert: invalidCertificate,
                key: invalidKey,
                rejectUnauthorized: false,
            }),
            validateStatus: null,
        })
        expect(resp.status).to.equal(401)
    })

    it('should successfully authenticate when accessing route with certificate and token', async function() {
        const resp = await axios({
            method: 'GET',
            url: `${proxyUrl}${path}`,
            headers: {
                Authorization: `Bearer ${token}`,
            },
            httpsAgent: certHttpsAgent,
            validateStatus: null,
        })
        logResponse(resp)
        expect(resp.status).to.equal(200)
        // delete tls plugin to test mTLS auth
        await deletePlugin(tlsPluginId)
        await waitForConfigRebuild()
    })

    it('should not update plugin to use mTLS authentication without certificate', async function () {
        const resp = await axios({
            method: 'PATCH',
            url: `${url}/plugins/${oidcPluginId}`,
            data: {
                config: {
                    client_auth: [ 'tls_client_auth' ],
                },
            },
            validateStatus: null,
        })
        logResponse(resp)
        expect(resp.status).to.equal(400)
        expect(resp.data.message).to.contain('tls_client_auth_cert_id is required when tls client auth is enabled')
    })

    it('should update plugin to use mTLS authentication', async function () {
        const resp = await axios({
            method: 'PATCH',
            url: `${url}/plugins/${oidcPluginId}`,
            data: {
                config: {
                    client_id: [ mtlsClientId ],
                    client_auth: [ 'tls_client_auth' ],
                    tls_client_auth_cert_id: certId,
                    auth_methods: [ 'password' ],
                    ignore_signature: [],
                    issuer: issuerUrl,
                    proof_of_possession_mtls: 'off',
                    login_methods: ['authorization_code'],
                    tls_client_auth_ssl_verify: true,
                },
            },
            validateStatus: null,
        })
        expect(resp.status).to.equal(200)
        await waitForConfigRebuild()
    })

    it('should return 401 when accessing route without credentials', async function() {
        const resp = await axios({
            method: 'GET',
            url: `${proxyUrl}${path}`,
            validateStatus: null,
        })
        expect(resp.status).to.equal(401)
    })

    it('should return 401 when accessing route with incorrect credentials', async function() {
        const resp = await axios({
            method: 'GET',
            url: `${proxyUrl}${path}`,
            auth: {
                username:'john',
                password:'no',
            },
            validateStatus: null,
        })
        expect(resp.status).to.equal(401)
    })

    it('should successfully authenticate when accessing route with mTLS authentication', async function() {
        const resp = await axios({
            method: 'GET',
            url: `${proxyUrl}${path}`,
            auth: {
                username:'john',
                password:'doe',
            },
            validateStatus: null,
        })
        logResponse(resp)
        expect(resp.status).to.equal(200)
        expect(resp.data.headers).to.have.property('Authorization')
    })

    it('should update plugin to use an invalid certificate', async function () {
        const resp = await axios({
            method: 'PATCH',
            url: `${url}/plugins/${oidcPluginId}`,
            data: {
                config: {
                    tls_client_auth_cert_id: invalidCertId,
                },
            },
            validateStatus: null,
        })
        logResponse(resp)
        expect(resp.status).to.equal(200)
        await waitForConfigRebuild()
    })

    it('should return 401 when accessing route with mismatched certificate', async function() {
        const resp = await axios({
            method: 'GET',
            url: `${proxyUrl}${path}`,
            auth: {
                username:'john',
                password:'doe',
            },
            validateStatus: null,
        })
        logResponse(resp)
        expect(resp.status).to.equal(401)
    })

    it('should update plugin to use expired certificate', async function() {
        const resp = await axios({
            method: 'PATCH',
            url: `${url}/plugins/${oidcPluginId}`,
            data: {
                config: {
                    tls_client_auth_cert_id: expiredCertId,
                },
            },
            validateStatus: null,
        })
        logResponse(resp)
        expect(resp.status).to.equal(200)
    })

    it('should return 401 when accessing route with expired certificate', async function() {
        const resp = await axios({
            method: 'GET',
            url: `${proxyUrl}${path}`,
            auth: {
                username:'john',
                password:'doe',
            },
            validateStatus: null,
        })
        logResponse(resp)
        expect(resp.status).to.equal(401)
    })

    it('should update plugin to use different message for unauthorized requests', async function () {
        const resp = await axios({
            method: 'PATCH',
            url: `${url}/plugins/${oidcPluginId}`,
            data: {
                config: {
                    unauthorized_error_message: 'You shall not pass!',
                },
            },
            validateStatus: null,
        })
        expect(resp.status).to.equal(200)
        await waitForConfigRebuild()
    })

    it('should return custom message when accessing route without authorization', async function() {
        const resp = await axios({
            method: 'GET',
            url: `${proxyUrl}${path}`,
            validateStatus: null,
        })
        logResponse(resp)
        expect(resp.status).to.equal(401)
        expect(resp.data.message).to.equal('You shall not pass!')
    })

    it('should delete OIDC plugin', async function () {
        const resp = await axios({
            method: 'DELETE',
            url: `${url}/plugins/${oidcPluginId}`,
        })
        expect(resp.status).to.equal(204)
    })

    after(async function () {
        await clearAllKongResources()

        // reset vars back to original setting 'system'
        await resetGatewayContainerEnvVariable(
            {
                KONG_LUA_SSL_TRUSTED_CERTIFICATE: 'system',
            },
            kongContainerName
        );
        if (isHybrid) {
            await resetGatewayContainerEnvVariable(
                {
                    KONG_LUA_SSL_TRUSTED_CERTIFICATE: 'system',
                },
                kongDpContainerName
            );
        }
    })
})