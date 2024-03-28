import { authDetails } from '@fixtures';
import * as https from 'https';
import axios from 'axios';
import {
  createConsumer,
  createGatewayService,
  createRouteForService,
  Environment,
  expect,
  getBasePath,
  getNegative,
  logResponse,
  clearAllKongResources,
  isGateway,
  waitForConfigRebuild,
  uploadCaCertificate,
  Consumer,
  postNegative,
  patchConsumer,
} from '@support';

describe('@smoke: Gateway Plugins: mtls-auth', function () {
  const path = '/mtls-auth';
  const serviceName = 'mtls-auth-service';
  const root1CertDn = 'emailAddress=kong@konghq.com,CN=KongSDET,OU=Gateway,O=Kong,L=Toronto,ST=ON,C=CA'
  const root2CertDn = 'CN=apitest,OU=Gateway,O=Kong,L=Toronto,ST=ON,C=CA'

  const consumer1Details: Consumer = {
    username: 'KongSDET',
    custom_id: '1234'
  };

  const consumer2Details: Consumer = {
    username: 'consumer2',
    custom_id: 'apitest'
  };

  const consumer3Details: Consumer = {
    username: 'consumer3'
  };

  const rootCertIds = {
    cert1: '',
    cert2: ''
  }

  let url: string
  let proxyUrl: string
  let serviceId: string;
  let routeId: string;
  let basePayload: any;
  let pluginId: string;

  before(async function () {
    url = `${getBasePath({
      environment: isGateway() ? Environment.gateway.admin : undefined,
    })}/plugins`;
    proxyUrl = `${getBasePath({
      app: 'gateway',
      environment: Environment.gateway.proxySec,
    })}`;

    const service = await createGatewayService(serviceName);
    serviceId = service.id;
    const route = await createRouteForService(serviceId, [path]);
    routeId = route.id;

    // Create 3 consumers
    let consumer = await createConsumer(consumer1Details.username, consumer1Details);
    consumer1Details.id = consumer.id
    consumer = await createConsumer(consumer2Details.username, consumer2Details);
    consumer2Details.id = consumer.id
    consumer = await createConsumer(consumer3Details.username, consumer3Details);
    consumer3Details.id = consumer.id

    // upload the root certificate for mtls request verifications with consumers
    let resp = await uploadCaCertificate(authDetails.mtls_certs.root1)
    // cert1 has CN of KongSDET
    rootCertIds.cert1 = resp.id
    resp = await uploadCaCertificate(authDetails.mtls_certs.root2)
    // cert2 has CN of apitest
    rootCertIds.cert2 = resp.id
    
    basePayload = {
      name: 'mtls-auth',
      service: {
        id: serviceId,
      },
      route: {
        id: routeId,
      },
    };
  });

  it('should not create mtls-auth plugin without ca_certificates', async function () {
    const resp = await postNegative(url, basePayload);
    logResponse(resp);

    expect(resp.status, 'Status should be 400').to.equal(400);
    expect(resp.data.message, 'Should have correct error message').to.contain(
      "schema violation (config.ca_certificates: required field missing)"
    );
  });

  it('should create mtls-auth plugin with ca_certificate', async function () {
    const pluginPayload = {
      ...basePayload,
      config: {
        ca_certificates: [rootCertIds.cert1]
      },
    };

    const resp = await axios({ method: 'post', url, data: pluginPayload });
    logResponse(resp);

    expect(resp.status, 'Status should be 201').to.equal(201);
    expect(resp.data.config.ca_certificates[0], 'Should see correct ca_cert id in plugin').to.equal(rootCertIds.cert1);
    expect(resp.data.config.consumer_by, 'Should see correct consumer_by configuration').to.eql(['username', 'custom_id']);
    pluginId = resp.data.id;

    await waitForConfigRebuild();
  });

  it('should not proxy request without supplying certificates', async function () {
    const resp = await getNegative(`${proxyUrl}${path}`, {}, {}, { rejectUnauthorized: true });
    logResponse(resp);

    expect(resp.status, 'Status should be 401').to.equal(401);
    expect(resp.data.message, 'Should indicate no api key found').to.equal(
      'No required TLS certificate was sent'
    );
  });

  it('should not proxy request with supplying non-matching certificates', async function () {
    const resp = await axios({
      url: `${proxyUrl}${path}`,
      httpsAgent: new https.Agent({
        rejectUnauthorized: false,
        cert: authDetails.mtls_certs.entity2_cert,
        key: authDetails.mtls_certs.entity2_key,
      }),
      validateStatus: null
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 401').to.equal(401);
    expect(resp.data.message, 'Should indicate no api key found').to.equal(
      'TLS certificate failed verification'
    );
  });

  // as long as at least one consumer exists with matching CN this test will fail (meaning request will go through which is illogical)
  // see this conversation https://kongstrong.slack.com/archives/C03CTMSHP6C/p1710440701434039
  // see this related closed ticket https://konghq.atlassian.net/browse/FTI-3284
  // to be checked if this is expected or not
  it.skip('should proxy request with supplying certificates but with non-matching consumer CN', async function () {
    const resp = await axios({
      url: `${proxyUrl}${path}`,
      httpsAgent: new https.Agent({
        rejectUnauthorized: false,
        cert: authDetails.mtls_certs.entity1_cert,
        key: authDetails.mtls_certs.entity1_key,
      }),
      validateStatus: null
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 401').to.equal(401);
    // expect(resp.data.message, 'Should indicate no api key found').to.equal(
    //   'TLS certificate failed verification'
    // );
  });

  it('should proxy request with supplying certificates', async function () {
    const resp = await axios({
      url: `${proxyUrl}${path}`,
      httpsAgent: new https.Agent({
        rejectUnauthorized: false,
        cert: authDetails.mtls_certs.entity1_cert,
        key: authDetails.mtls_certs.entity1_key,
      })
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.headers['X-Consumer-Custom-Id'], 'Should see X-Consumer-Custom-Id header').to.equal(consumer1Details.custom_id);
    expect(resp.data.headers['X-Consumer-Id'], 'Should see X-Consumer-Id header').to.equal(consumer1Details.id);
    expect(resp.data.headers['X-Consumer-Username'], 'Should see X-Consumer-Username header').to.equal(consumer1Details.username);
    expect(resp.data.headers['X-Client-Cert-Dn'], 'Should not see X-Client-Cert-Dn header').to.not.exist;
    expect(resp.data.headers['X-Client-Cert-San'], 'Should not see X-Client-Cert-San header').to.not.exist;
  });

  it('should patch mtls-auth plugin consumer_by', async function () {
    const resp = await axios({
      method: 'patch',
      url: `${url}/${pluginId}`,
      data: {
        config: {
          consumer_by: ['custom_id'],
          ca_certificates: [rootCertIds.cert1, rootCertIds.cert2]
        },
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.config.consumer_by, 'Should see correct consumer_by configuration').to.eql(['custom_id']);
    expect(resp.data.config.ca_certificates, 'Should see correct ca_certificates configuration').to.have.lengthOf(2)
    await waitForConfigRebuild();
  });

  it('should not proxy request with CN username match when consumer_by is custom_id only', async function () {
    const resp = await axios({
      url: `${proxyUrl}${path}`,
      httpsAgent: new https.Agent({
        rejectUnauthorized: false,
        cert: authDetails.mtls_certs.entity1_cert,
        key: authDetails.mtls_certs.entity1_key,
      }),
      validateStatus: null
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 401').to.equal(401);
    expect(resp.data.message, 'Should indicate no api key found').to.equal(
      'TLS certificate failed verification'
    );
  });

  it('should proxy request with supplying matching certificates for the new root certificate', async function () {
    const resp = await axios({
      url: `${proxyUrl}${path}`,
      httpsAgent: new https.Agent({
        rejectUnauthorized: false,
        cert: authDetails.mtls_certs.entity2_cert,
        key: authDetails.mtls_certs.entity2_key,
      }),
      validateStatus: null
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.headers['X-Consumer-Custom-Id'], 'Should see X-Consumer-Custom-Id header').to.equal(consumer2Details.custom_id);
    expect(resp.data.headers['X-Consumer-Id'], 'Should see X-Consumer-Id header').to.equal(consumer2Details.id);
    expect(resp.data.headers['X-Consumer-Username'], 'Should see X-Consumer-Username header').to.equal(consumer2Details.username);
  });

  it('should patch mtls-auth plugin skip_consumer_lookup', async function () {
    const resp = await axios({
      method: 'patch',
      url: `${url}/${pluginId}`,
      data: {
        config: {
          skip_consumer_lookup: true
        },
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.config.consumer_by, 'Should see correct consumer_by configuration').to.eql(['custom_id']);
    expect(resp.data.config.skip_consumer_lookup, 'Should see skip_consumer_lookup enabled').to.be.true
    expect(resp.data.config.ca_certificates, 'Should see correct ca_certificates configuration').to.have.lengthOf(2)

    await waitForConfigRebuild();
  });

  it('should proxy request with CN matching username when consumer_by is only custom_id and skip_consumer_lookup is enabled', async function () {
    const resp = await axios({
      url: `${proxyUrl}${path}`,
      httpsAgent: new https.Agent({
        rejectUnauthorized: false,
        cert: authDetails.mtls_certs.entity1_cert,
        key: authDetails.mtls_certs.entity1_key,
      }),
      validateStatus: null
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.headers['X-Client-Cert-Dn'], 'Should see X-Client-Cert-Dn header').to.equal(root1CertDn);
    expect(resp.data.headers['X-Client-Cert-San'], 'Should see X-Client-Cert-San header').to.equal(consumer1Details.username);
    expect(resp.data.headers['X-Consumer-Custom-Id'], 'Should see X-Consumer-Custom-Id header').to.not.exist
    expect(resp.data.headers['X-Consumer-Id'], 'Should see X-Consumer-Id header').to.not.exist
    expect(resp.data.headers['X-Consumer-Username'], 'Should see X-Consumer-Username header').to.not.exist
  });

  it('should patch mtls-auth plugin anonymous consumer', async function () {
    const resp = await axios({
      method: 'patch',
      url: `${url}/${pluginId}`,
      data: {
        config: {
          anonymous: consumer3Details.id
        },
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.config.consumer_by, 'Should see correct consumer_by configuration').to.eql(['custom_id']);
    expect(resp.data.config.skip_consumer_lookup, 'Should see skip_consumer_lookup enabled').to.be.true
    expect(resp.data.config.anonymous, 'Should see correct anonymous configuration').to.equal(consumer3Details.id)

    await waitForConfigRebuild();
  });

  it('should fallback to the given anonymous consumer when authentication fails', async function () {
    const resp = await axios({
      url: `${proxyUrl}${path}`,
      httpsAgent: new https.Agent({
        rejectUnauthorized: false,
        cert: authDetails.keycloak.invalid_cert,
        key: authDetails.keycloak.invalid_key,
      }),
      validateStatus: null
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.headers['X-Consumer-Id'], 'Should see X-Consumer-Id header').to.equal(consumer3Details.id);
    expect(resp.data.headers['X-Consumer-Username'], 'Should see X-Consumer-Username header').to.equal(consumer3Details.username);
    expect(resp.data.headers['X-Anonymous-Consumer'], 'Should see X-Anonymous-Consumer header').to.equal('true')
  });

  it('should patch mtls-auth plugin default consumer', async function () {
    // update consumer custom_id to non-matching to the cert CN
    await patchConsumer(consumer2Details.username, { custom_id: 'notapitest' })
    consumer2Details.custom_id = 'notapitest'
    
    const resp = await axios({
      method: 'patch',
      url: `${url}/${pluginId}`,
      data: {
        config: {
          default_consumer: consumer3Details.id,
          skip_consumer_lookup: false,
          consumer_by: ['custom_id', 'username'],
        },
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.config.consumer_by, 'Should see correct consumer_by configuration').to.eql(['custom_id','username']);
    expect(resp.data.config.skip_consumer_lookup, 'Should see skip_consumer_lookup enabled').to.be.false
    expect(resp.data.config.anonymous, 'Should see correct anonymous configuration').to.equal(consumer3Details.id)
    expect(resp.data.config.default_consumer, 'Should see correct default_consumer configuration').to.equal(consumer3Details.id)

    await waitForConfigRebuild();
  });

  it('should fallback to default_consumer with valid cert when no matching consumer is found', async function () {
    const resp = await axios({
      url: `${proxyUrl}${path}`,
      httpsAgent: new https.Agent({
        rejectUnauthorized: false,
        cert: authDetails.mtls_certs.entity2_cert,
        key: authDetails.mtls_certs.entity2_key,
      }),
      validateStatus: null
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);''
    expect(resp.data.headers['X-Client-Cert-Dn'], 'Should see X-Client-Cert-Dn header').to.equal(root2CertDn);
    expect(resp.data.headers['X-Client-Cert-San'], 'Should see X-Client-Cert-San header').to.equal('apitest');
    expect(resp.data.headers['X-Consumer-Custom-Id'], 'Should see X-Consumer-Custom-Id header').to.equal(consumer3Details.custom_id)
    expect(resp.data.headers['X-Consumer-Id'], 'Should see X-Consumer-Id header').to.equal(consumer3Details.id)
    expect(resp.data.headers['X-Consumer-Username'], 'Should see X-Consumer-Username header').to.equal(consumer3Details.username)
  });

  it('should fallback to anonymous when using invalid cert with default consumer enabled', async function () {
    const resp = await axios({
      url: `${proxyUrl}${path}`,
      httpsAgent: new https.Agent({
        rejectUnauthorized: false,
        cert: authDetails.keycloak.invalid_cert,
        key: authDetails.keycloak.invalid_key,
      }),
      validateStatus: null
    });
    logResponse(resp);

    expect(resp.data.headers['X-Consumer-Id'], 'Should see X-Consumer-Id header').to.equal(consumer3Details.id);
    expect(resp.data.headers['X-Consumer-Username'], 'Should see X-Consumer-Username header').to.equal(consumer3Details.username);
  });

  it('should successfully send request with matching consumer and cert', async function () {
    const resp = await axios({
      url: `${proxyUrl}${path}`,
      httpsAgent: new https.Agent({
        rejectUnauthorized: false,
        cert: authDetails.mtls_certs.entity1_cert,
        key: authDetails.mtls_certs.entity1_key,
      }),
      validateStatus: null
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.headers['X-Consumer-Custom-Id'], 'Should see X-Consumer-Custom-Id header').to.equal(consumer1Details.custom_id);
    expect(resp.data.headers['X-Consumer-Id'], 'Should see X-Consumer-Id header').to.equal(consumer1Details.id);
    expect(resp.data.headers['X-Consumer-Username'], 'Should see X-Consumer-Username header').to.equal(consumer1Details.username);
    expect(resp.data.headers['X-Client-Cert-Dn'], 'Should not see X-Client-Cert-Dn header').to.not.exist;
    expect(resp.data.headers['X-Client-Cert-San'], 'Should not see X-Client-Cert-San header').to.not.exist;
  });

  it('should fallback to default_consumer with valid cert using default consumer username', async function () {
    let resp = await axios({
      method: 'patch',
      url: `${url}/${pluginId}`,
      data: {
        config: {
          default_consumer: consumer3Details.username
        },
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.config.default_consumer, 'Should see correct default_consumer configuration').to.equal(consumer3Details.username)

    await waitForConfigRebuild();

    resp = await axios({
      url: `${proxyUrl}${path}`,
      httpsAgent: new https.Agent({
        rejectUnauthorized: false,
        cert: authDetails.mtls_certs.entity2_cert,
        key: authDetails.mtls_certs.entity2_key,
      }),
      validateStatus: null
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.headers['X-Client-Cert-Dn'], 'Should see X-Client-Cert-Dn header').to.equal(root2CertDn);
    expect(resp.data.headers['X-Client-Cert-San'], 'Should see X-Client-Cert-San header').to.equal('apitest');
    expect(resp.data.headers['X-Consumer-Custom-Id'], 'Should see X-Consumer-Custom-Id header').to.equal(consumer3Details.custom_id)
    expect(resp.data.headers['X-Consumer-Id'], 'Should see X-Consumer-Id header').to.equal(consumer3Details.id)
    expect(resp.data.headers['X-Consumer-Username'], 'Should see X-Consumer-Username header').to.equal(consumer3Details.username)
  });

  it('should see 401 when using invalid default consumer uuid', async function () {
    let resp = await axios({
      method: 'patch',
      url: `${url}/${pluginId}`,
      data: {
        config: {
          default_consumer: '454554687912casdasd456'
        },
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    await waitForConfigRebuild();

    resp = await axios({
      url: `${proxyUrl}${path}`,
      httpsAgent: new https.Agent({
        rejectUnauthorized: false,
        cert: authDetails.mtls_certs.entity2_cert,
        key: authDetails.mtls_certs.entity2_key,
      }),
      validateStatus: null
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 401').to.equal(401);
    expect(resp.data.message, 'Should see Unauthorized error message').to.equal('Unauthorized')
  });

  it('should delete the mtls-auth plugin', async function () {
    const resp = await axios({
      method: 'delete',
      url: `${url}/${pluginId}`,
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 204').to.equal(204);
  });

  after(async function () {
    await clearAllKongResources()
  });
});
