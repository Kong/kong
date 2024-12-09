import { authDetails } from '@fixtures';
import * as https from 'https';
import axios from 'axios';
import {
  createGatewayService,
  createRouteForService,
  Environment,
  expect,
  getBasePath,
  logResponse,
  clearAllKongResources,
  isGateway,
  patchRoute,
  eventually
} from '@support';

describe('@smoke: Gateway Plugins: TLS Handshake Modifier', function () {
  const path = '/tls';
  const serviceName = 'tls-service';
  const certDn = 'CN=foo@example.com,OU=Gateway,O=Kong,L=Toronto,ST=ON,C=CA'
  const resolvedIpAddress = '127.0.0.1'
  const proxyUrls = ['https://f.example.com:8443', 'https://test.example.com:8443']
  const wrongSniUrl = 'https://f.example.org:8443'
  const proxyUrlsRightmost = ['https://foo.example.test:8443', 'https://foo.example.org:8443']
  const wrongSniUrlRightmost = 'https://test.example.org:8443'
  const certChunk = "MIIDfTCCAmWgAwIBAgIUJCdVEgDy5Wmy6M7GG68L65WrF9UwDQYJKoZIhvcNAQEL"

  let url: string
  let serviceId: string;
  let routeId: string;
  let basePayload: any;

  before(async function () {
    url = `${getBasePath({
      environment: isGateway() ? Environment.gateway.admin : undefined,
    })}/plugins`;

    const service = await createGatewayService(serviceName);
    serviceId = service.id;
    const route = await createRouteForService(serviceId, [path], {snis: ["*.example.com"]});
    routeId = route.id;

    
    basePayload = {
      service: {
        id: serviceId,
      },
      route: {
        id: routeId,
      },
    };
  });


  it('should create tls-handshake-modifier and tls-metadata-headers plugins', async function () {
    // tls-handshake-modifier is only responsible for requesting the client cert and verifying the client has the corresponding private key
    // tls-handshake-modifier must be used in conjunction with the tls-metadata-headers plugin
    // The TLS Metadata Header plugin detects client certificates in requests, retrieves the TLS metadata, such as the URL-encoded client certificate, and proxies this metadata via HTTP headers

    let pluginPayload = {
      ...basePayload,
      name: 'tls-handshake-modifier'
    };

    let resp = await axios({ method: 'post', url, data: pluginPayload });
    logResponse(resp);
    expect(resp.status, 'Status should be 201').to.equal(201);
    

    pluginPayload = {
      ...basePayload,
      name: 'tls-metadata-headers',
      config: {
        inject_client_cert_details: true
      }
    };

    resp = await axios({ method: 'post', url, data: pluginPayload });
    logResponse(resp);
    expect(resp.status, 'Status should be 201').to.equal(201);
  });

  proxyUrls.forEach(async (proxyUrl) => {
    it(`should proxy request with ${proxyUrl} when SNI has leftmost wildcard`, async function () {
      await eventually(async () => {
        // equivalent request in curl: curl -k --cert c.crt --key c.key --resolve fo.example.com:8443:127.0.0.1 https://fo.example.com:8443/tls
        const resp = await axios({
          url: `${proxyUrl}${path}`,
          httpsAgent: new https.Agent({
            rejectUnauthorized: false,
            cert: authDetails.tls.cert,
            key: authDetails.tls.key,
          }),
          proxy: {
            host: resolvedIpAddress,
            port: 8443
          }
        });
        logResponse(resp);
    
        expect(resp.status, 'Status should be 200').to.equal(200);
        expect(resp.data.headers['X-Client-Cert'], 'Should see X-Client-Cert header').to.contain(certChunk)
        expect(resp.data.headers['X-Client-Cert-Subject-Dn'], 'Should see X-Client-Cert-Subject-Dn header').to.equal(certDn)
        expect(resp.data.headers['X-Client-Cert-Issuer-Dn'], 'Should see X-Client-Cert-Issuer-Dn header').to.equal(certDn)
        })
    });
  })

  it(`should not match route with wrong SNI`, async function () {
    const resp = await axios({
      url: `${wrongSniUrl}${path}`,
      httpsAgent: new https.Agent({
        rejectUnauthorized: false,
        cert: authDetails.tls.cert,
        key: authDetails.tls.key,
      }),
      validateStatus: null,
      proxy: {
        host: resolvedIpAddress,
        port: 8443
      }
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 404').to.equal(404);
    expect(resp.data.message, 'Should see correct error message').to.equal('no Route matched with those values')
  });

  it(`should match route but not put the cert in the header when certs do not exist in the request`, async function () {
    const resp = await axios({
      url: `${proxyUrls[0]}${path}`,
      httpsAgent: new https.Agent({
        rejectUnauthorized: false,
      }),
      proxy: {
        host: resolvedIpAddress,
        port: 8443
      }
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.headers['X-Client-Cert'], 'Should not see X-Client-Cert header').to.not.exist
    expect(resp.data.headers['X-Client-Cert-Subject-Dn'], 'Should not see X-Client-Cert-Subject-Dn header').to.not.exist
    expect(resp.data.headers['X-Client-Cert-Issuer-Dn'], 'Should not see X-Client-Cert-Issuer-Dn header').to.not.exist
  });

  it('should not patch the route SNI to middle wildcard', async function () {
    const resp = await patchRoute(routeId, { snis: ["foo.*.com"] });

    expect(resp.data.message, 'Should see correct SNI error message').to.contain('wildcard must be leftmost or rightmost character')
  });

  it('should patch the route SNI to leftmost wildcard', async function () {
    const resp = await patchRoute(routeId, { snis: ["foo.example.*"] });

    expect(resp.status, 'Status should be 200').equal(200);
    expect(resp.data.snis[0], 'Should see updated SNI').to.equal('foo.example.*')
  });

  proxyUrlsRightmost.forEach(async (proxyUrl) => {
    it(`should proxy request with ${proxyUrl} when SNI has rightmost wildcard`, async function () {
      await eventually(async () => {
        const resp = await axios({
          url: `${proxyUrl}${path}`,
          httpsAgent: new https.Agent({
            rejectUnauthorized: false,
            cert: authDetails.tls.cert,
            key: authDetails.tls.key,
          }),
          proxy: {
            host: resolvedIpAddress,
            port: 8443
          }
        });
        logResponse(resp);
    
        expect(resp.status, 'Status should be 200').to.equal(200);
        expect(resp.data.headers['X-Client-Cert'], 'Should see X-Client-Cert header').to.contain(certChunk)
        expect(resp.data.headers['X-Client-Cert-Subject-Dn'], 'Should see X-Client-Cert-Subject-Dn header').to.equal(certDn)
        expect(resp.data.headers['X-Client-Cert-Issuer-Dn'], 'Should see X-Client-Cert-Issuer-Dn header').to.equal(certDn)
      })
    });
  })

  it(`should not match route with rightmost wrong SNI`, async function () {
    const resp = await axios({
      url: `${wrongSniUrlRightmost}${path}`,
      httpsAgent: new https.Agent({
        rejectUnauthorized: false,
        cert: authDetails.tls.cert,
        key: authDetails.tls.key,
      }),
      validateStatus: null,
      proxy: {
        host: resolvedIpAddress,
        port: 8443
      }
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 404').to.equal(404);
    expect(resp.data.message, 'Should see correct error message').to.equal('no Route matched with those values')
  });

  after(async function () {
    await clearAllKongResources()
  });
});
