import {
    expect,
    Environment,
    getBasePath,
    createGatewayService,
    createRouteForService,
    deleteGatewayService,
    deleteGatewayRoute,
    deletePlugin,
    waitForConfigRebuild,
    logResponse,
} from '@support';
import {
    authDetails,
} from '@fixtures'
import axios from 'axios';
import https from 'https';
import querystring from 'querystring';

describe('Gateway Plugins: OIDC with Keycloak', function () {
    const path = '/oidc';
    const serviceName = 'oidc-service';
    
    const cert = authDetails.keycloak.certificate;
    const key = authDetails.keycloak.key;

    const certHttpsAgent = new https.Agent({
        cert: cert,
        key: key,
        rejectUnauthorized: false,
    });

    const invalidCert = authDetails.keycloak.invalid_cert;
    const invalidKey = authDetails.keycloak.invalid_key;

    // use to authenticate token request
    const clientId = 'kong-certificate-bound';
    const clientSecret = '670f2328-85a0-11ee-b9d1-0242ac120002'

    let serviceId: string;
    let routeId: string;
    let tlsPluginId: string;
    let oidcPluginId: string;
    let token: string;

    const url = `${getBasePath({
        environment: Environment.gateway.admin,
    })}`;
    const proxyUrl = `${getBasePath({
        environment: Environment.gateway.proxySec,
    })}`;

    const keycloakUrl = `${getBasePath({
        environment: Environment.gateway.keycloakSec,
    })}/realms/demo`;

    const tokenRequestUrl = `${keycloakUrl}/protocol/openid-connect/token`;
    const issuerUrl = 'https://keycloak:8543/realms/demo/.well-known/openid-configuration';

    before(async function () {
        const service = await createGatewayService(serviceName);
        serviceId = service.id;
        const route = await createRouteForService(serviceId, [path]);
        routeId = route.id;

        // Create TLS plugin for certificate-based tokens
        const resp = await axios({
            method: 'POST',
            url: `${url}/services/${serviceId}/plugins`,
            data: { name: 'tls-handshake-modifier' },
        });
        tlsPluginId = resp.data.id;
    });

    it('should create OIDC plugin with certificate-based tokens enabled', async function () {
        const resp = await axios({
            method: 'POST',
            url: `${url}/services/${serviceId}/plugins`,
            data: {
                name: 'openid-connect',
                config: {
                    client_id: [ clientId ],
                    client_secret: [ clientSecret ],
                    auth_methods: [ 'bearer' ],
                    issuer: issuerUrl,
                    proof_of_possession_mtls: 'strict',
                    ignore_signature: [ 'client_credentials' ],
                },
            },
            validateStatus: null,
        });
        logResponse(resp);
        expect(resp.status).to.equal(201);
        oidcPluginId = resp.data.id;
        await waitForConfigRebuild();
    });

    it('should not be able to request a token without a valid certificate', async function() {
        const resp = await axios({
            method: 'POST',
            url: tokenRequestUrl,
            data: querystring.stringify({
                grant_type: 'client_credentials',
                client_id: clientId,
                client_secret: clientSecret,
            }),
            validateStatus: null,
        });
        logResponse(resp);
        expect(resp.status).to.equal(400);
        expect(resp.data.error_description).to.equal('Client Certification missing for MTLS HoK Token Binding');
    });

    it('should return 401 when accessing route without certificate in request', async function() {
        const resp = await axios({
            method: 'GET',
            url: `${proxyUrl}${path}`,
            headers: {
                Authorization: `Bearer ${token}`,
            },
            validateStatus: null,
        });
        expect(resp.status).to.equal(401);
    });

    it('should be able to request token with valid certificate provided', async function() {
        const resp = await axios({
            method: 'POST',
            url: tokenRequestUrl,
            data: querystring.stringify({
                grant_type: 'client_credentials',
                client_id: clientId,
                client_secret: clientSecret,
            }),
            httpsAgent: certHttpsAgent,
        });
        logResponse(resp);
        expect(resp.status).to.equal(200);
        token = resp.data.access_token;
    });

    it('should return 401 when accessing route with certificate but no token', async function() {
        const resp = await axios({
            method: 'GET',
            url: `${proxyUrl}${path}`,
            validateStatus: null,
            httpsAgent: certHttpsAgent,
        });
        expect(resp.status).to.equal(401);
    });

    it('should return 401 when accessing route with incorrect certificate', async function() {
        const resp = await axios({
            method: 'GET',
            url: `${proxyUrl}${path}`,
            headers: {
                Authorization: `Bearer ${token}`,
            },
            httpsAgent: new https.Agent({
                cert: invalidCert,
                key: invalidKey,
                rejectUnauthorized: false,
            }),
            validateStatus: null,
        });
        expect(resp.status).to.equal(401);
    });

    it('should successfully authenticate when accessing route with certificate and token', async function() {
        const resp = await axios({
            method: 'GET',
            url: `${proxyUrl}${path}`,
            headers: {
                Authorization: `Bearer ${token}`,
            },
            httpsAgent: certHttpsAgent,
            validateStatus: null,
        });
        logResponse(resp);
        expect(resp.status).to.equal(200);
    });

    it('should delete OIDC plugin', async function () {
        const resp = await axios({
            method: 'DELETE',
            url: `${url}/plugins/${oidcPluginId}`,
        });
        expect(resp.status).to.equal(204);
    });

    after(async function () {
        await deletePlugin(tlsPluginId);
        await deleteGatewayRoute(routeId);
        await deleteGatewayService(serviceId);
    });
});