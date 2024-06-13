import axios from 'axios';
import { authDetails } from '@fixtures';
import { jwtDecode } from 'jwt-decode';
import {
  expect,
  Environment,
  getBasePath,
  isLocalDatabase,
  createGatewayService,
  deleteGatewayService,
  createRouteForService,
  deleteGatewayRoute,
  wait,
  logResponse,
  createConsumer,
  deleteConsumer,
  getNegative,
  retryRequest,
  isGateway,
  waitForConfigRebuild,
  postNegative,
  deletePlugin,
} from '@support';

describe('Gateway Plugins: jwt-signer', function () {
  this.timeout(30000);
  const path = '/jwtsigner';
  const serviceName = 'jwt-signer-service';
  const consumerName = 'demo';
  const upstreamConsumerHeaderName = 'X-Consumer-Username';
  const upstreamConsumerHeaderId = 'X-Consumer-Id';
  const islocalDb = isLocalDatabase();
  const waitTime = 5000;
  const expiredTokenHeaders = {
    Authorization: `bearer ${authDetails.expired_token}`,
  };
  const validTokenHeaders = {
    Authorization: `bearer ${authDetails.valid_token}`,
  };

  const channelValidTokenHeaders = {
    Authorization: `bearer ${authDetails.valid_token}`,
    'Channel-Authorization': `bearer ${authDetails.valid_token}`
  };

  const testClaims = [
    {
      description: 'should be able to add extra claims in the resigned token',
      config: {
        add_claims: {
          a: 'test_a',
          b: '[true, false]',
          c: '{ ccc: 123 }',
          d: '12345.99',
        }
      },
      expectedToken: {
        a: 'test_a',
        b: [ true, false ],
        iss: 'kong',
        c: '{ ccc: 123 }',
        d: 12345.99,
        iat: 1665610129,
        original_iss: 'demo',
        username: 'demo'
      },
      headerKey: 'Abc',
      tokenHeaders: validTokenHeaders
    },
    {
      description: 'should be able to add access token claims in the resigned token',
      config: {
        add_access_token_claims: {
          e: 'test_e',
          f: '[true, false]',
          g: '{ ggg: 123 }',
          d: '12345.99999999999999999999999999999',
        }
      },
      expectedToken: {
        f: [ true, false ],
        c: '{ ccc: 123 }',
        e: 'test_e',
        username: 'demo',
        g: '{ ggg: 123 }',
        iss: 'kong',
        a: 'test_a',
        b: [ true, false ],
        iat: 1665610129,
        d: 12346,
        original_iss: 'demo'
      },
      headerKey: 'Abc',
      tokenHeaders: validTokenHeaders
    },
    {
      description: 'should be able to set access token claims in the resigned token',
      config: {
        set_access_token_claims: {
          i: 'test_i',
          j: '[true, false]',
          k: '{ kkk: 123 }',
          l: '12345.999998888',
        }
      },
      expectedToken: {
        a: 'test_a',
        k: '{ kkk: 123 }',
        c: '{ ccc: 123 }',
        b: [ true, false ],
        e: 'test_e',
        f: [ true, false ],
        username: 'demo',
        i: 'test_i',
        g: '{ ggg: 123 }',
        iss: 'kong',
        d: 12346,
        j: [ true, false ],
        iat: 1665610129,
        original_iss: 'demo',
        l: 12345.999998888
      },
      headerKey: 'Abc',
      tokenHeaders: validTokenHeaders
    },
    {
      description: 'should be able to update claims with add_claims in the resigned token',
      config: {
          add_claims: {
            a: 'test_a_new'
          }
      },
      expectedToken: {
        k: '{ kkk: 123 }',
        a: 'test_a_new',
        e: 'test_e',
        f: [ true, false ],
        username: 'demo',
        i: 'test_i',
        g: '{ ggg: 123 }',
        iss: 'kong',
        d: 12346,
        j: [ true, false ],
        iat: 1665610129,
        original_iss: 'demo',
        l: 12345.999998888
      },
      headerKey: 'Abc',
      tokenHeaders: validTokenHeaders
    },
    {
      description: 'should be able to update claims with set_claims in the resigned token',
      config: {
          set_claims: {
            a: 'test_a_new_v2'
          }
      },
      expectedToken: {
        k: '{ kkk: 123 }',
        a: 'test_a_new_v2',
        e: 'test_e',
        f: [ true, false ],
        username: 'demo',
        i: 'test_i',
        g: '{ ggg: 123 }',
        iss: 'kong',
        d: 12346,
        j: [ true, false ],
        iat: 1665610129,
        l: 12345.999998888,
        original_iss: 'demo'
      },
      headerKey: 'Abc',
      tokenHeaders: validTokenHeaders
    },
    {
      description: 'should not be able to remove claims if added with add_claims or add_access_token_claims in the resigned token',
      config: {
          remove_access_token_claims: ['a', 'e']
      },
      expectedToken: {
        k: '{ kkk: 123 }',
        a: 'test_a_new_v2',
        e: 'test_e',
        f: [ true, false ],
        username: 'demo',
        i: 'test_i',
        g: '{ ggg: 123 }',
        iss: 'kong',
        d: 12346,
        j: [ true, false ],
        iat: 1665610129,
        l: 12345.999998888,
        original_iss: 'demo'
      },
      headerKey: 'Abc',
      tokenHeaders: validTokenHeaders
    },
    {
      description: 'should be able to remove claims if it was pre-existed from the resigned token',
      config: {
          remove_access_token_claims: ['username']
      },
      expectedToken: {
        k: '{ kkk: 123 }',
        a: 'test_a_new_v2',
        e: 'test_e',
        f: [ true, false ],
        i: 'test_i',
        g: '{ ggg: 123 }',
        iss: 'kong',
        d: 12346,
        j: [ true, false ],
        iat: 1665610129,
        original_iss: 'demo',
        l: 12345.999998888
      },
      headerKey: 'Abc',
      tokenHeaders: validTokenHeaders
    },
    {
      description: 'should set_claims takes higher priority than add_claims',
      config: {
          add_claims: {
            b: "{\"key\": 123}"
          },
          set_claims: {
            b: "[\"str1\",\"str2\", true, 1234.009999]"
          }
      },
      expectedToken: {
        b: [ 'str1', 'str2', true, 1234.009999 ],
        e: 'test_e',
        f: [ true, false ],
        d: 12346,
        i: 'test_i',
        g: '{ ggg: 123 }',
        iss: 'kong',
        original_iss: 'demo',
        j: [ true, false ],
        iat: 1665610129,
        k: '{ kkk: 123 }',
        l: 12345.999998888
      },
      headerKey: 'Abc',
      tokenHeaders: validTokenHeaders
    },
    {
      description: 'should set_access_token_claims takes higher priority than set_claims',
      config: {
          add_claims: {
            b: "{\"key\": 123}"
          },
          set_claims: {
            b: "[\"str1\",\"str2\", true, 1234.009999]"
          }
      },
      expectedToken: {
        b: [ 'str1', 'str2', true, 1234.009999 ],
        e: 'test_e',
        f: [ true, false ],
        d: 12346,
        i: 'test_i',
        g: '{ ggg: 123 }',
        iss: 'kong',
        original_iss: 'demo',
        j: [ true, false ],
        iat: 1665610129,
        k: '{ kkk: 123 }',
        l: 12345.999998888
      },
      headerKey: 'Abc',
      tokenHeaders: validTokenHeaders
    },
    {
      description: 'should see original access token when set original_access_token_upstream_header',
      config: {
          original_access_token_upstream_header: "og_token"
      },
      expectedToken: { iat: 1665610129, iss: 'demo', username: 'demo' },
      headerKey: 'Og-Token',
      tokenHeaders: validTokenHeaders
    },
    {
      description: 'should be able to add channel token',
      config: {
          channel_token_upstream_header: "DEF",
          verify_channel_token_signature: false,
          channel_token_request_header: "Channel-Authorization"
      },
      expectedToken: {
        iss: 'kong',
        b: [ 'str1', 'str2', true, 1234.009999 ],
        iat: 1665610129,
        original_iss: 'demo',
        username: 'demo'
      },
      headerKey: 'Def',
      tokenHeaders: channelValidTokenHeaders
    },
    {
      description: 'should be able to add_claims and set_claims for channel token',
      config: {
          add_claims: {
            c: "{ \"ccc\": 12309.9999 }"
          },
          set_claims: {
            c: "{ \"ccc\": true }"
          }
      },
      expectedToken: {
        iss: 'kong',
        c: { ccc: true },
        iat: 1665610129,
        original_iss: 'demo',
        username: 'demo'
      },
      headerKey: 'Def',
      tokenHeaders: channelValidTokenHeaders
    },
    {
      description: 'should set_channel_token_claims take the higher priority for channel token',
      config: {
          add_claims: {
            d: "{ \"ddd\": 12309.9999 }"
          },
          set_claims: {
            d: "{ \"ddd\": true }"
          },
          add_access_token_claims: {
            d: "1234"
          },
          set_channel_token_claims: {
            d: "{\"dd\": 1234, \"ddd\": true}"
          }
      },
      expectedToken: {
        iss: 'kong',
        d: { dd: 1234, ddd: true },
        iat: 1665610129,
        original_iss: 'demo',
        username: 'demo'
      },
      headerKey: 'Def',
      tokenHeaders: channelValidTokenHeaders
    },
    {
      description: 'should set original channel token',
      config: {
          original_channel_token_upstream_header: "og-channel-token"
      },
      expectedToken: { iat: 1665610129, iss: 'demo', username: 'demo' },
      headerKey: 'Og-Channel-Token',
      tokenHeaders: channelValidTokenHeaders
    }
  ]


  let serviceId: string;
  let routeId: string;
  let consumerId: string;

  const url = `${getBasePath({
    environment: isGateway() ? Environment.gateway.admin : undefined,
  })}/plugins`;
  const proxyUrl = `${getBasePath({
    app: 'gateway',
    environment: Environment.gateway.proxy,
  })}`;

  // json server running in the same docker network as kong
  const jwksUri = `http://json-server:3000/db`;

  let basePayload: any;
  let pluginId: string;

  before(async function () {
    const service = await createGatewayService(serviceName);
    serviceId = service.id;
    const route = await createRouteForService(serviceId, [path]);
    routeId = route.id;
    const consumer = await createConsumer(consumerName);
    consumerId = consumer.id;

    basePayload = {
      name: 'jwt-signer',
      service: {
        id: serviceId,
      },
      route: {
        id: routeId,
      },
    };
  });

  it('should create jwt-signer plugin with default parameters when config payload is not supplied by the user', async function () {
    basePayload = {
      name: 'jwt-signer',
      service: {
        id: serviceId,
      },
      route: {
        id: routeId,
      },
    };
    const pluginPayload = {
      ...basePayload,
      config: {},
    };
    const resp = await axios({ method: 'post', url, data: pluginPayload });
    logResponse(resp);

    expect(resp.status, 'Status should be 201').to.equal(201);
    expect(resp.data.config.verify_access_token_expiry, 'Expiry should be true')
      .to.true;
    expect(
      resp.data.config.access_token_issuer,
      'Issuer should be kong'
    ).to.equal('kong');
    expect(
      resp.data.config.access_token_signing_algorithm,
      'Algorithm should be RS256'
    ).to.equal('RS256');
    expect(resp.data.config.access_token_jwks_uri, 'Jwks uri should be null').to
      .be.null;
    expect(resp.data.config.access_token_optional, 'Should be false').to.false;
    expect(resp.data.config.channel_token_optional, 'Should be false').to.false;

    pluginId = resp.data.id;
  });

  it('should not proxy request when JWKS_URI parameter is null preventing token validation', async function () {
    const req = () => getNegative(`${proxyUrl}${path}`);

    const assertions = (resp) => {
      expect(resp.status, 'Status should be 401').to.equal(401);
      expect(resp.data.message, 'Message should be unauthorized').to.equal(
        'Unauthorized'
      );
    };

    await retryRequest(req, assertions);
  });

  it('should patch jwt-signer plugin to set JWKS_URI allowing token validation', async function () {
    const resp = await axios({
      method: 'patch',
      url: `${url}/${pluginId}`,
      data: {
        config: {
          channel_token_optional: true,
          access_token_jwks_uri: jwksUri,
          access_token_consumer_claim: ['username'],
        },
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(
      resp.data.config.access_token_jwks_uri,
      'Jwks uri should not be null'
    ).to.equal(jwksUri);

    await waitForConfigRebuild()
  });

  it('should proxy request with a valid token', async function () {
    const resp = await axios({
      headers: validTokenHeaders,
      url: `${proxyUrl}${path}`,
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(
      resp.data.headers[upstreamConsumerHeaderName],
      'Should see consumer username in upstream request'
    ).to.equal(consumerName);
    expect(
      resp.data.headers[upstreamConsumerHeaderId],
      'Should see consumer id in upstream request'
    ).to.equal(consumerId);
  });

  it('should not proxy request with a expired token ', async function () {
    const resp = await getNegative(`${proxyUrl}${path}`, expiredTokenHeaders);
    logResponse(resp);

    expect(resp.status, 'Status should be 401').to.equal(401);
    expect(resp.data.message, 'Should be Unauthorized').to.equal(
      'Unauthorized'
    );
  });

  it('should patch jwt-signer plugin to disable auth and allow requests', async function () {
    const resp = await axios({
      method: 'patch',
      url: `${url}/${pluginId}`,
      data: {
        config: {
          channel_token_optional: true,
          access_token_optional: true,
        },
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.config.access_token_optional, 'Should be true').to.be.true;
    expect(resp.data.config.channel_token_optional, 'Should be true').to.be
      .true;
    await wait(waitTime + (islocalDb ? 0 : waitTime)); // eslint-disable-line no-restricted-syntax
  });

  it('should proxy request without token', async function () {
    const req = () =>
      axios({
        url: `${proxyUrl}${path}`,
      });

    const assertions = (resp) => {
      expect(resp.status, 'Status should be 200').to.equal(200);
    };

    await retryRequest(req, assertions, 20000, 4000);
  });

  it('should delete the jwt-signer plugin', async function () {
    const resp = await axios({
      method: 'delete',
      url: `${url}/${pluginId}`,
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 204').to.equal(204);
  });

  it('should not create a jwt-signer plugin when original channel token and original access token headers are same', async function () {
    basePayload = {
      name: 'jwt-signer',
      service: {
        id: serviceId,
      },
      route: {
        id: routeId,
      },
    };
    const pluginPayload = {
      ...basePayload,
      config: {
        original_channel_token_upstream_header: 'AAA',
        verify_access_token_signature: false,
        verify_channel_token_signature: false,
        channel_token_optional: true,
        original_access_token_upstream_header: 'AAA'
      },
    };

    const resp = await postNegative(url, pluginPayload, 'post');

    expect(resp.status, 'Status should be 400').to.equal(400);
    expect(resp.data.name, 'Should indicate schema violation').to.equal(
      'schema violation'
    );
    logResponse(resp);

  });

  it('should recreate jwt-signer plugin with the access token upstream header', async function () {
    basePayload = {
      name: 'jwt-signer',
      service: {
        id: serviceId,
      },
      route: {
        id: routeId,
      },
    };
    const pluginPayload = {
      ...basePayload,
      config: {
        access_token_upstream_header: 'ABC',
        verify_access_token_signature: false,
        verify_channel_token_signature: false,
        channel_token_optional: true,
      },
    };
    const resp = await axios({ method: 'post', url, data: pluginPayload });
    logResponse(resp);

    expect(resp.status, 'Status should be 201').to.equal(201);
    pluginId = resp.data.id;
    await waitForConfigRebuild();
  });

  it('should proxy request with a valid token and verify the resigned token', async function () {
    const expectedToken = {
      username: 'demo',
      iat: 1665610129,
      iss: 'kong',
      original_iss: 'demo'
    }
    const resp = await axios({
      headers: validTokenHeaders,
      url: `${proxyUrl}${path}`,
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    const decodedToken = jwtDecode(resp.data.headers['Abc']);
    expect(
      decodedToken, 'should see the decoded token in the response',
    ).to.deep.equal(expectedToken);
  });  

  testClaims.forEach(({ description, config, expectedToken, headerKey, tokenHeaders }) => {
    it(description, async function() {
      let resp = await axios({
        method: 'patch',
        url: `${url}/${pluginId}`,
        data: {
          config: config
        },
      });

      logResponse(resp);

      expect(resp.status, 'Status should be 200').to.equal(200);

      await waitForConfigRebuild()
      
      resp = await axios({
        headers: tokenHeaders,
        url: `${proxyUrl}${path}`,
      });
      logResponse(resp);

      expect(resp.status, 'Status should be 200').to.equal(200);
      const decodedToken = jwtDecode(resp.data.headers[headerKey]);
      expect(
        decodedToken, 'should see the decoded token in the response',
      ).to.deep.equal(expectedToken);
    });
  });

  after(async function () {
    await deleteGatewayRoute(routeId);
    await deleteGatewayService(serviceId);
    await deleteConsumer(consumerId);
    await deletePlugin(pluginId);
  });
});
