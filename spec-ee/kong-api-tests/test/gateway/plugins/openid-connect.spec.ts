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
    getKongContainerName,
    getGatewayMode,
    clearAllKongResources,
    randomString,
    generateDpopProof,
    isGwNative,
    resetGatewayContainerEnvVariable,
    eventually,
} from '@support'
import {
    authDetails,
} from '@fixtures'
import axios from 'axios'
import https from 'https'
import querystring from 'querystring'

const urls = {
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

const isHybrid = getGatewayMode() === 'hybrid'
const kongContainerName = getKongContainerName()
const kongDpContainerName = 'kong-dp1';
const serviceName = 'oidc-service'

let serviceId: string
let oidcPluginId: string

describe('Gateway Plugins: OIDC with Okta', function () {
    const oktaPath = '/oidcOktaAuthentication'
    const oktaIssuerUrl = `${urls.okta}/default`
    const oktaTokenUrl = `${urls.okta}/default/v1/token`

    // DPoP vars
    const dpopClientId = '0oae8abki4NEfVkLQ1d7'
    const dpopClientSecret = 'eOXgBBLJHRcd9GYvkP3fbvfrf2tU6RmX3j_WYPYlRHGmQ1paRcNkfFM0DHolo1P6'
    const jti = randomString()

    let dpopProof: string
    let dpopProofNonce: string
    let updatedDpopProof: string
    let dpopToken: string
    let currentTime: number

    before(async function () {
        const service = await createGatewayService(serviceName)
        serviceId = service.id
        await createRouteForService(serviceId, [oktaPath])
    })

    //======= DPoP tests =======
    it('should create OIDC plugin with dPoP enabled', async function () {
        const resp = await axios({
            method: 'POST',
            url: `${urls.admin}/services/${serviceId}/plugins/`,
            data: {
                name: 'openid-connect',
                config: {
                    client_id: [ dpopClientId ],
                    client_secret: [ dpopClientSecret ],
                    auth_methods: [ 'bearer' ],
                    issuer: oktaIssuerUrl,
                    proof_of_possession_dpop: 'strict',
                    scopes: ['scope1'],
                    expose_error_code: true,
                },
            },
            validateStatus: null,
        })
        logResponse(resp)
        expect(resp.status, 'Status should be 201').to.equal(201)
        oidcPluginId = resp.data.id
        await waitForConfigRebuild()
    })

    it('should be able to request token with dPoP', async function() {
        // initial request to get nonce - should return 400
        currentTime = Math.floor(Date.now() / 1000)
        dpopProof = await generateDpopProof({time: currentTime, jti: jti, nonce: '', token: '', url: oktaTokenUrl})
        const resp = await axios({
            method: 'POST',
            url: oktaTokenUrl,
            headers: {
                'Content-Type': 'application/x-www-form-urlencoded',
                'Accept': 'application/json',
                'DPoP': dpopProof
            },
            data: querystring.stringify({
                grant_type: 'client_credentials',
                client_id: dpopClientId,
                client_secret: dpopClientSecret,
                scope: 'scope1'
            }),
            validateStatus: null,
        })

        expect(resp.status, 'Status should be 400').to.equal(400)
        expect(resp.data.error_description, 'Error description should reference nonce').to.contain('Authorization server requires nonce in DPoP proof')
        dpopProofNonce = resp.headers['dpop-nonce']

        // request token with dPoP proof
        updatedDpopProof = await generateDpopProof({time: currentTime, jti: jti, nonce: dpopProofNonce, token: '', url: oktaTokenUrl})
        const tokenResp = await axios({
            method: 'POST',
            url: oktaTokenUrl,
            headers: {
                'Content-Type': 'application/x-www-form-urlencoded',
                'Accept': 'application/json',
                'DPoP': updatedDpopProof
            },
            data: querystring.stringify({
                grant_type: 'client_credentials',
                client_id: dpopClientId,
                client_secret: dpopClientSecret,
                scope: 'scope1'
            }),
        })
        expect(tokenResp.status, 'Status should be 200').to.equal(200)
        expect(tokenResp.data, 'Access token should be present').to.have.property('access_token')
        expect(tokenResp.data.token_type, 'Token type should be DPOP').to.equal('DPoP')
        dpopToken = tokenResp.data.access_token
    })

    it('should return 401 when accessing route without token but with dpop proof', async function() {
      await eventually(async () => {
        const resp = await axios({
            method: 'GET',
            url: `${urls.proxy}${oktaPath}`,
            validateStatus: null,
            headers: {
                'DPoP': dpopProof,
            }
        })

        expect(resp.status, 'Status should be 401').to.equal(401)
        expect(resp.headers['www-authenticate'], 'Headers should contain DPoP').to.contain('DPoP')
        expect(resp.headers['www-authenticate'], 'error message should reference invalid token').to.contain('error="invalid_token"')
      });
    })

    it('should return 401 when accessing route with token but without token proof', async function() {
      await eventually(async () => {
        const resp = await axios({
            method: 'GET',
            url: `${urls.proxy}${oktaPath}`,
            validateStatus: null,
            headers: {
                'Authorization': `DPoP ${dpopToken}`,
            }
        })

        expect(resp.status, 'Status should be 401').to.equal(401)
        expect(resp.headers['www-authenticate'], 'Headers should contain DPoP').to.contain('DPoP')
        expect(resp.headers['www-authenticate'], 'error message should reference invalid dpop proof').to.contain('error="invalid_dpop_proof"')
      });
    })

    it('should return 401 when accessing route with downgraded dpop proof', async function() {
        const proofWithRoute  = await generateDpopProof({time: currentTime, jti: jti, nonce: '', token: dpopToken, url: `${urls.proxy}${oktaPath}`})
        await eventually(async () => {
          const resp = await axios({
              method: 'GET',
              url: `${urls.proxy}${oktaPath}`,
              validateStatus: null,
              headers: {
                  'Authorization': `Bearer ${dpopToken}`,
                  'DPoP': proofWithRoute,
              }
          })

          logResponse(resp)
          expect(resp.status, 'Status should be 401').to.equal(401)
          expect(resp.headers['www-authenticate'], 'Headers should contain DPoP').to.contain('DPoP')
          expect(resp.headers['www-authenticate'], 'error message should reference invalid dpop proof').to.contain('error="invalid_dpop_proof"')
        });
    })

    it('should return 401 when accessing route with dpop proof with incorrect htu claim', async function() {
        const proofWithIncorrectHtu = await generateDpopProof({time: currentTime, jti: jti, nonce: '', token: dpopToken, url: `http://localhost:8000/wrongpath`})
        await eventually(async () => {
          const resp = await axios({
              method: 'GET',
              url: `${urls.proxy}${oktaPath}`,
              headers: {
                  'Authorization': `DPoP ${dpopToken}`,
                  'DPoP': proofWithIncorrectHtu,
              },
              validateStatus: null,
          })

          logResponse(resp)
          expect(resp.status, 'Status should be 401').to.equal(401)
          expect(resp.headers['www-authenticate'], 'Headers should contain DPoP').to.contain('DPoP')
          expect(resp.headers['www-authenticate'], 'error message should reference invalid dpop proof').to.contain('error="invalid_dpop_proof"')
        });
    })

    it('should return 200 when accessing route with token and dpop proof', async function() {
        const proofWithRoute  = await generateDpopProof({time: currentTime, jti: jti, nonce: '', token: dpopToken, url: `${urls.proxy}${oktaPath}`})

        await eventually(async () => {
          const resp = await axios({
              method: 'POST',
              url: `${urls.proxy}${oktaPath}`,
              headers: {
                  'Authorization': `DPoP ${dpopToken}`,
                  'DPoP': proofWithRoute,
              },
              validateStatus: null,
          })

          expect(resp.status, 'Status should be 200').to.equal(200)
        });
    })

    it('should delete OIDC plugin', async function () {
        const resp = await axios({
            method: 'DELETE',
            url: `${urls.admin}/plugins/${oidcPluginId}`,
        })
        expect(resp.status, 'Status should be 204').to.equal(204)
    })

    after(async function () {
        await clearAllKongResources()
    })

})

// Skip this test suite for packages to investigate the error when creating OIDC plugin
describe('Gateway Plugins: OIDC with Keycloak', function () {
    const keycloakPath = '/oidc'
    const keycloakTokenRequestUrl = `${urls.keycloak}/realms/demo/protocol/openid-connect/token`
    const keycloakIssuerUrl = `https://keycloak:8543/realms/demo`
    const certClientId = 'kong-certificate-bound'
    const certClientSecret = '670f2328-85a0-11ee-b9d1-0242ac120002'
    const mtlsClientId = 'kong-client-tls-auth'
    const isKongNative = isGwNative();

    const invalidCertificate = authDetails.keycloak.invalid_cert
    const invalidKey = authDetails.keycloak.invalid_key
    const clientCertificate = authDetails.keycloak.client_cert
    const clientKey = authDetails.keycloak.client_key

    const certHttpsAgent = new https.Agent({
        cert: clientCertificate,
        key: clientKey,
        rejectUnauthorized: false,
    })

    let tlsPluginId: string
    let certId: string
    let invalidCertId: string
    let expiredCertId: string
    let token: string

    before(async function () {
        // set KONG_LUA_SSL_TRUSTED_CERTIFICATE value to root/intermediate CA certificates
        // whenever the original LUA_SSL_TRUSTED_CERTIFICATE is being modified, the keyring needs to either be turned off or get its certificates updated as well
        await resetGatewayContainerEnvVariable(
            {
                KONG_LUA_SSL_TRUSTED_CERTIFICATE: 'system,/tmp/root_ca.crt,/tmp/intermediate_ca.crt', KONG_KEYRING_ENABLED: `${isKongNative ? 'off' : 'on'}`
            },
            kongContainerName
        );

        if (isHybrid) {
            await resetGatewayContainerEnvVariable(
                {
                    KONG_LUA_SSL_TRUSTED_CERTIFICATE: 'system,/tmp/root_ca.crt,/tmp/intermediate_ca.crt', KONG_KEYRING_ENABLED: `${isKongNative ? 'off' : 'on'}`
                },
                kongDpContainerName
            );
        }

        const service = await createGatewayService(serviceName)
        serviceId = service.id
        await createRouteForService(serviceId, [keycloakPath])

        const validCert = await axios({
            method: 'POST',
            url: `${urls.admin}/certificates`,
            data: {
                cert: clientCertificate,
                key: clientKey,
            },
            validateStatus: null,
        })
        certId = validCert.data.id

        const invalidCert = await axios({
            method: 'POST',
            url: `${urls.admin}/certificates`,
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
            url: `${urls.admin}/services/${serviceId}/plugins`,
            data: { name: 'tls-handshake-modifier' },
        })
        tlsPluginId = resp.data.id
    })

    //======= cert-based auth tests =======
    it('should create OIDC plugin that uses certificate-based tokens', async function () {
        const resp = await axios({
            method: 'POST',
            url: `${urls.admin}/services/${serviceId}/plugins`,
            data: {
                name: 'openid-connect',
                config: {
                    client_id: [ certClientId ],
                    client_secret: [ certClientSecret ],
                    issuer: keycloakIssuerUrl,
                    token_endpoint: keycloakTokenRequestUrl,
                    proof_of_possession_mtls: 'strict',
                    ignore_signature: [ 'client_credentials' ],
                    auth_methods: ['bearer'],
                    cache_user_info: false,
                    cache_tokens: false,
                    cache_introspection: false,
                },
            },
            validateStatus: null,
        })
        logResponse(resp)
        expect(resp.status, 'Status should be 201').to.equal(201)
        oidcPluginId = resp.data.id
        await waitForConfigRebuild()
    })

    it('should not be able to request a token without a valid certificate', async function() {
        const resp = await axios({
            method: 'POST',
            url: keycloakTokenRequestUrl,
            data: querystring.stringify({
                grant_type: 'client_credentials',
                client_id: certClientId,
                client_secret: certClientSecret,
            }),
            validateStatus: null,
        })
        logResponse(resp)

        expect(resp.status, 'Status should be 400').to.equal(400)
        expect(resp.data.error_description, 'Description should reference missing cert').to.equal('Client Certification missing for MTLS HoK Token Binding')
    })

    it('should return 401 when accessing route without certificate in request', async function() {
        const resp = await axios({
            method: 'GET',
            url: `${urls.proxySec}${keycloakPath}`,
            headers: {
                Authorization: `Bearer ${token}`,
            },
            validateStatus: null,
        })
        logResponse(resp)
        expect(resp.status, 'Status should be 401').to.equal(401)
        expect(resp.data.message, 'Message should be "Unauthorized"').to.equal('Unauthorized')
    })

    it('should be able to request token with valid certificate provided', async function() {
        const resp = await axios({
            method: 'POST',
            url: keycloakTokenRequestUrl,
            data: querystring.stringify({
                grant_type: 'client_credentials',
                client_id: certClientId,
                client_secret: certClientSecret,
            }),
            httpsAgent: certHttpsAgent,
        })
        logResponse(resp)
        expect(resp.status, 'Status should be 200').to.equal(200)
        token = resp.data.access_token
    })

    it('should return 401 when accessing route with certificate but no token', async function() {
        const resp = await axios({
            method: 'GET',
            url: `${urls.proxySec}${keycloakPath}`,
            validateStatus: null,
            httpsAgent: certHttpsAgent,
        })
        expect(resp.status, 'Status should be 401').to.equal(401)
    })

    it('should return 401 when accessing route with incorrect certificate', async function() {
        const resp = await axios({
            method: 'GET',
            url: `${urls.proxySec}${keycloakPath}`,
            headers: {
                'Authorization': `Bearer ${token}`,
            },
            httpsAgent: new https.Agent({
                cert: invalidCertificate,
                key: invalidKey,
                rejectUnauthorized: false,
            }),
            validateStatus: null,
        })
        expect(resp.status, 'Status should be 401').to.equal(401)
    })

    it('should successfully authenticate when accessing route with certificate and token', async function() {
        const resp = await axios({
            method: 'GET',
            url: `${urls.proxySec}${keycloakPath}`,
            headers: {
                Authorization: `Bearer ${token}`,
            },
            httpsAgent: certHttpsAgent,
            validateStatus: null,
        })
        logResponse(resp)
        expect(resp.status, 'Status should be 200').to.equal(200)
        // delete tls plugin to test mTLS auth
        await deletePlugin(tlsPluginId)
        await waitForConfigRebuild()
    })

    //======= mTLS auth tests =======
    it('should not update plugin to use mTLS authentication without certificate', async function () {
        const resp = await axios({
            method: 'POST',
            url: `${urls.admin}/plugins`,
            data: {
                name: 'openid-connect',
                config: {
                    client_id: [ mtlsClientId ],
                    auth_methods: [ 'password' ],
                    issuer: keycloakIssuerUrl,
                    client_auth: [ 'tls_client_auth' ],
                    login_methods: ['authorization_code'],
                    tls_client_auth_ssl_verify: true,
                },
            },
            validateStatus: null,
        })
        logResponse(resp)
        expect(resp.status, 'Status should be 400').to.equal(400)
        expect(resp.data.message, 'Message should reference missing cert id').to.contain('tls_client_auth_cert_id is required when tls client auth is enabled')
    })

    it('should update plugin to use mTLS authentication', async function () {
        const resp = await axios({
            method: 'PATCH',
            url: `${urls.admin}/plugins/${oidcPluginId}`,
            data: {
                config: {
                    client_id: [ mtlsClientId ],
                    auth_methods: [ 'password' ],
                    client_auth: [ 'tls_client_auth' ],
                    tls_client_auth_cert_id: certId,
                    issuer: keycloakIssuerUrl,
                    login_methods: ['authorization_code'],
                    tls_client_auth_ssl_verify: true,
                    ignore_signature: [],
                    proof_of_possession_mtls: 'off',
                },
            },
            validateStatus: null,
        })
        logResponse(resp)
        expect(resp.status, 'Status should be 200').to.equal(200)
        await waitForConfigRebuild()
    })

    it('should return 401 when accessing route without credentials', async function() {
        const resp = await axios({
            method: 'GET',
            url: `${urls.proxySec}${keycloakPath}`,
            validateStatus: null,
        })
        expect(resp.status, 'Status should be 401').to.equal(401)
    })

    it('should return 401 when accessing route with incorrect credentials', async function() {
        const resp = await axios({
            method: 'GET',
            url: `${urls.proxySec}${keycloakPath}`,
            auth: {
                username:'john',
                password:'no',
            },
            validateStatus: null,
        })
        expect(resp.status, 'Status should be 401').to.equal(401)
    })

    it('should successfully authenticate when accessing route with mTLS authentication', async function() {
        const resp = await axios({
            method: 'GET',
            url: `${urls.proxySec}${keycloakPath}`,
            auth: {
                username:'john',
                password:'doe',
            },
            validateStatus: null,
        })

        logResponse(resp)
        expect(resp.status, 'Status should be 200').to.equal(200)
        expect(resp.data.headers, 'Auth header should be present').to.have.property('Authorization')
    })

    it('should update plugin to use an invalid certificate', async function () {
        const resp = await axios({
            method: 'PATCH',
            url: `${urls.admin}/plugins/${oidcPluginId}`,
            data: {
                config: {
                    tls_client_auth_cert_id: invalidCertId,
                },
            },
            validateStatus: null,
        })
        logResponse(resp)
        expect(resp.status, 'Status should be 200').to.equal(200)
        await waitForConfigRebuild()
    })

    it('should return 401 when accessing route with mismatched certificate', async function() {
        const resp = await axios({
            method: 'GET',
            url: `${urls.proxySec}${keycloakPath}`,
            auth: {
                username:'john',
                password:'doe',
            },
            validateStatus: null,
        })
        logResponse(resp)
        expect(resp.status, 'Status should be 401').to.equal(401)
    })

    it('should update plugin to use expired certificate', async function() {
        const resp = await axios({
            method: 'PATCH',
            url: `${urls.admin}/plugins/${oidcPluginId}`,
            data: {
                config: {
                    tls_client_auth_cert_id: expiredCertId,
                },
            },
            validateStatus: null,
        })
        logResponse(resp)
        expect(resp.status, 'Status should be 200').to.equal(200)
    })

    it('should return 401 when accessing route with expired certificate', async function() {
        const resp = await axios({
            method: 'GET',
            url: `${urls.proxySec}${keycloakPath}`,
            auth: {
                username:'john',
                password:'doe',
            },
            validateStatus: null,
        })
        logResponse(resp)
        expect(resp.status, 'Status should be 401').to.equal(401)
    })

    //====== Unauthorized message tests =======
    it('should update plugin to use different message for unauthorized requests', async function () {
        const resp = await axios({
            method: 'PATCH',
            url: `${urls.admin}/plugins/${oidcPluginId}`,
            data: {
                config: {
                    unauthorized_error_message: 'You shall not pass!',
                },
            },
            validateStatus: null,
        })
        expect(resp.status, 'Status should be 200').to.equal(200)
        await waitForConfigRebuild()
    })

    it('should return custom message when accessing route without authorization', async function() {
        const resp = await axios({
            method: 'GET',
            url: `${urls.proxy}${keycloakPath}`,
            validateStatus: null,
        })
        logResponse(resp)
        expect(resp.status, 'Status should be 200').to.equal(401)
        expect(resp.data.message).to.equal('You shall not pass!')
    })

    it('should delete OIDC plugin', async function () {
        const resp = await axios({
            method: 'DELETE',
            url: `${urls.admin}/plugins/${oidcPluginId}`,
        })
        expect(resp.status, 'Status should be 204').to.equal(204)
    })

    after(async function () {
        await clearAllKongResources()

        // reset vars back to original setting 'system'
        await resetGatewayContainerEnvVariable(
            {
                KONG_LUA_SSL_TRUSTED_CERTIFICATE: 'system', KONG_KEYRING_ENABLED: `${isKongNative ? 'on' : 'off'}`
            },
            kongContainerName
        );
        if (isHybrid) {
            await resetGatewayContainerEnvVariable(
                {
                    KONG_LUA_SSL_TRUSTED_CERTIFICATE: 'system', KONG_KEYRING_ENABLED: `${isKongNative ? 'on' : 'off'}`
                },
                kongDpContainerName
            );
        }
    })
})
