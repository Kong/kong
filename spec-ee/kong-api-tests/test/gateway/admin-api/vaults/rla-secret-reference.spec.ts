import axios from 'axios';
import {
  expect,
  getBasePath,
  Environment,
  createGatewayService,
  createRouteForService,
  deleteGatewayRoute,
  deleteGatewayService,
  getNegative,
  randomString,
  wait,
  createHcvVault,
  createHcvVaultSecrets,
  getHcvVaultSecret,
  deleteVaultEntity,
  createAwsVaultEntity,
  createEnvVaultEntity,
  deleteHcvSecret,
  deleteCache,
  checkGwVars,
  logResponse,
  createGcpVaultEntity,
  isGateway
} from '@support';

// ********* Note *********
// In order for this test to successfully run you need to have defined the following environment variables in all Kong nodes
// RLA_REDISU: redisuser
// RLA_REDISP: redispassword
// AWS_REGION: us-east-2
// AWS_ACCESS_KEY_ID: ${{ actualSecret}}
// AWS_SECRET_ACCESS_KEY: ${{ actualSecret }}
// GCP_SERVICE_ACCOUNT: ${{actualGcpAccountKey}}
// ********* End **********

describe('Vaults: Secret referencing in RLA Plugin', function () {
  let serviceId = '';
  let routeId = '';
  let rlaPluginId = '';

  const path = `/${randomString()}`;
  const pluginUrl = `${getBasePath({
    environment: isGateway() ? Environment.gateway.admin : undefined,
  })}/plugins`;

  const proxyUrl = getBasePath({ environment: isGateway() ? Environment.gateway.proxy : undefined });
  const gcpProjectId = 'gcp-sdet-test';
  // hcv secrets
  const redisHcvPassword = 'redispassword';
  const redisHcvUser = 'redisuser';
  // env secrets > RLA_REDISU (redisuser), RLA_REDISP (redispassword)
  // aws secrets > gateway-secret-test/ rla_redisu (redisuser), rla_redisp (redispassword)
  // gcp secrets > aws_access_key, aws_secret_key
  const waitTime = 8000;

  const window_size = 4;

  const doBasicRateLimitCheck = async () => {
    /**
     * This test will make 2 requests to the same path.
     * The first request should be successful.
     * The second request should be rate limited.
     *
     * But there is a unlucky chance could make the previous
     * assumption is wrong (2nd request will be successful).
     *
     * | 1st request | 2nd request |
     * +-------------+-------------+
     *     1st Wnd       2nd Wnd
     *
     * Wnd: Window
     *
     * If the 2nd request hit the 2nd Window,
     * it will be successful,
     * and our test will fail.
     *
     * If we are facing this situation,
     * that means the 2nd request was made
     * at the start of the 2nd Window.
     * So we can wait for the 3rd Window SAFELY.
     *
     * The resolution is that
     * if the 2nd request is successful,
     * we will wait for the 3rd Window,
     * and then make two request immediately.
     *
     * |    1st request   |    2nd request   | 3rd+4th requests |
     * +------------------+------------------+------------------+
     *        1st Wnd            2nd Wnd            3rd Wnd
     *
     * As the Windows are 4 seconds,
     * I believe the we can make 3rd+4th requests in 4 seconds.
     */

    for (let i = 0; i < 2; i++) {
      const resp: any = await getNegative(`${proxyUrl}/${path}`);

      if (i === 1) {
        if (resp.status === 429) {
          return;
        }

        if (resp.status != 200) {
          expect(
            resp.status,
            'Status should be 429 meaning secret reference worked'
          ).to.equal(429);
        }
      } else {
        expect(resp.status, 'Status should be 200').to.equal(200);
      }
    }

    await wait((window_size + 0.5) * 1000); // eslint-disable-line no-restricted-syntax

    for (let i = 0; i < 2; i++) {
      const resp: any = await getNegative(`${proxyUrl}/${path}`);

      if (i === 1) {
        expect(
          resp.status,
          'Status should be 429 meaning secret reference worked'
        ).to.equal(429);
      } else {
        expect(resp.status, 'Status should be 200').to.equal(200);
      }
    }
  };

  before(async function () {
    checkGwVars('aws');
    const service = await createGatewayService('VaultSecretService');
    serviceId = service.id;
    const route = await createRouteForService(serviceId, [path]);
    routeId = route.id;
  });

  it('should create hcv vault entity and secrets', async function () {
    await createHcvVault();

    await createHcvVaultSecrets({
      redisHcvPassword: redisHcvPassword,
      redisHcvUser: redisHcvUser,
    });

    const resp = await getHcvVaultSecret();

    expect(resp.data.redisHcvUser, 'Should see redis username').to.equal(
      redisHcvUser
    );
  });

  it('should create RLA plugin with hcv secret reference', async function () {
    const pluginPayload = {
      name: 'rate-limiting-advanced',
      service: {
        id: serviceId,
      },
      route: {
        id: routeId,
      },
      config: {
        limit: [1],
        window_size: [window_size],
        sync_rate: 0,
        strategy: 'redis',
        redis: {
          host: 'redis',
          port: 6379,
          username: '{vault://my-hcv/secret/redisHcvUser}',
          password: redisHcvPassword,
        },
      },
    };

    const resp: any = await axios({
      method: 'post',
      url: pluginUrl,
      data: pluginPayload,
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 201').to.equal(201);
    rlaPluginId = resp.data.id;

    expect(rlaPluginId, 'Plugin Id should be a string').to.be.string;

    expect(
      resp.data.config.redis.username,
      'Should have redis username referenced'
    ).to.equal('{vault://my-hcv/secret/redisHcvUser}');
  });

  it('should rate limit with redis password hcv vault entity referenced', async function () {
    await wait(waitTime); // eslint-disable-line no-restricted-syntax
    await doBasicRateLimitCheck();
  });

  it('should rate limit with redis password and username hcv vault entity referenced', async function () {
    // changing RLA Plugin plaintext redis password to hcv reference
    const patchResp = await axios({
      method: 'patch',
      url: `${pluginUrl}/${rlaPluginId}`,
      data: {
        name: 'rate-limiting-advanced',
        config: {
          redis: {
            password: '{vault://my-hcv/secret/redisHcvPassword}',
          },
        },
      },
    });
    logResponse(patchResp);

    expect(patchResp.status, 'Status should be 200').to.equal(200);
    expect(
      patchResp.data.config.redis.password,
      'Should replace redis password with reference'
    ).to.equal('{vault://my-hcv/secret/redisHcvPassword}');

    await wait(waitTime); // eslint-disable-line no-restricted-syntax
    await doBasicRateLimitCheck();
  });

  it('should rate limit with redis password and username hcv vault secret referenced', async function () {
    // changing RLA Plugin plaintext redis password to hcv reference
    const patchResp = await axios({
      method: 'patch',
      url: `${pluginUrl}/${rlaPluginId}`,
      data: {
        name: 'rate-limiting-advanced',
        config: {
          redis: {
            username: '{vault://hcv/secret/redisHcvUser}',
            password: '{vault://hcv/secret/redisHcvPassword}',
          },
        },
      },
    });
    logResponse(patchResp);

    expect(patchResp.status, 'Status should be 200').to.equal(200);
    expect(
      patchResp.data.config.redis.password,
      'Should replace redis password with hcv reference'
    ).to.equal('{vault://hcv/secret/redisHcvPassword}');

    await wait(waitTime); // eslint-disable-line no-restricted-syntax
    await doBasicRateLimitCheck();
  });

  it('should rate limit with redis password hcv and username hcv vault entity secret referenced', async function () {
    // changing RLA Plugin plaintext redis password to hcv reference
    const patchResp = await axios({
      method: 'patch',
      url: `${pluginUrl}/${rlaPluginId}`,
      data: {
        name: 'rate-limiting-advanced',
        config: {
          redis: {
            username: '{vault://my-hcv/secret/redisHcvUser}',
            password: '{vault://hcv/secret/redisHcvPassword}',
          },
        },
      },
    });
    logResponse(patchResp);

    expect(patchResp.status, 'Status should be 200').to.equal(200);

    await wait(waitTime); // eslint-disable-line no-restricted-syntax
    await doBasicRateLimitCheck();
  });

  it('should rate limit with redis password env and username hcv vault entity referenced', async function () {
    // changing RLA Plugin hcv redis password to env reference
    const patchResp = await axios({
      method: 'patch',
      url: `${pluginUrl}/${rlaPluginId}`,
      data: {
        name: 'rate-limiting-advanced',
        config: {
          redis: {
            password: '{vault://env/rla_redisp}',
          },
        },
      },
    });
    logResponse(patchResp);

    expect(patchResp.status, 'Status should be 200').to.equal(200);
    expect(
      patchResp.data.config.redis.password,
      'Should replace redis password with reference'
    ).to.equal('{vault://env/rla_redisp}');

    await wait(waitTime); // eslint-disable-line no-restricted-syntax
    await doBasicRateLimitCheck();
  });

  it('should rate limit with redis password aws and username hcv vault entity referenced', async function () {
    // changing RLA Plugin hcv redis password to env reference
    const patchResp = await axios({
      method: 'patch',
      url: `${pluginUrl}/${rlaPluginId}`,
      data: {
        name: 'rate-limiting-advanced',
        config: {
          redis: {
            password: '{vault://aws/gateway-secret-test/rla_redisp}',
          },
        },
      },
    });
    logResponse(patchResp);

    expect(patchResp.status, 'Status should be 200').to.equal(200);
    expect(
      patchResp.data.config.redis.password,
      'Should replace redis password with reference'
    ).to.equal('{vault://aws/gateway-secret-test/rla_redisp}');

    await wait(waitTime); // eslint-disable-line no-restricted-syntax
    await doBasicRateLimitCheck();
  });

  it('should rate limit with redis password aws and username env vault referenced', async function () {
    // changing RLA Plugin hcv redis password to env reference
    const patchResp = await axios({
      method: 'patch',
      url: `${pluginUrl}/${rlaPluginId}`,
      data: {
        name: 'rate-limiting-advanced',
        config: {
          redis: {
            username: '{vault://env/rla_redisu}',
          },
        },
      },
    });
    logResponse(patchResp);

    expect(patchResp.status, 'Status should be 200').to.equal(200);
    expect(
      patchResp.data.config.redis.username,
      'Should replace redis username with reference'
    ).to.equal('{vault://env/rla_redisu}');

    await wait(waitTime); // eslint-disable-line no-restricted-syntax
    await doBasicRateLimitCheck();
  });

  it('should create env,gcp and aws vault entities', async function () {
    //  creating my-env vault entity with varaible reference prefix 'rla_'
    await createEnvVaultEntity('my-env', { prefix: 'rla_' });
    // creating my-aws vault entity
    await createAwsVaultEntity();
    // creating my-gcp vault entity
    await createGcpVaultEntity();
  });

  it('should rate limit with redis password aws vault entity and username env vault entity referenced', async function () {
    // changing RLA Plugin aws and env references to the new created backend entities

    const patchResp = await axios({
      method: 'patch',
      url: `${pluginUrl}/${rlaPluginId}`,
      data: {
        name: 'rate-limiting-advanced',
        config: {
          redis: {
            // notice that we can strip the rla_ prefix as it is already defined in my-env backend vault config
            username: '{vault://my-env/redisu}',
            password: '{vault://my-aws/gateway-secret-test/rla_redisp}',
          },
        },
      },
    });
    logResponse(patchResp);

    expect(patchResp.status, 'Status should be 200').to.equal(200);
    expect(
      patchResp.data.config.redis.username,
      'Should replace redis username with reference'
    ).to.equal('{vault://my-env/redisu}');
    expect(
      patchResp.data.config.redis.password,
      'Should replace redis password with reference'
    ).to.equal('{vault://my-aws/gateway-secret-test/rla_redisp}');

    await wait(waitTime); // eslint-disable-line no-restricted-syntax
    await doBasicRateLimitCheck();
  });

  it('should rate limit with redis password env and username gcp vault entity referenced', async function () {
    // changing RLA Plugin redis username reference to gcp vault entity

    const patchResp = await axios({
      method: 'patch',
      url: `${pluginUrl}/${rlaPluginId}`,
      data: {
        name: 'rate-limiting-advanced',
        config: {
          redis: {
            username: '{vault://my-gcp/rla_redisu}',
          },
        },
      },
    });
    logResponse(patchResp);

    expect(patchResp.status, 'Status should be 200').to.equal(200);
    expect(
      patchResp.data.config.redis.username,
      'Should replace redis username with reference'
    ).to.equal('{vault://my-gcp/rla_redisu}');
    expect(
      patchResp.data.config.redis.password,
      'Should replace redis password with reference'
    ).to.equal('{vault://my-aws/gateway-secret-test/rla_redisp}');

    await wait(waitTime); // eslint-disable-line no-restricted-syntax
    await doBasicRateLimitCheck();
  });

  it('should rate limit with redis password gcp vault and username hcv vault entity referenced', async function () {
    // changing RLA Plugin redis username reference to hcv vault entity and password to gcp vault reference

    const patchResp = await axios({
      method: 'patch',
      url: `${pluginUrl}/${rlaPluginId}`,
      data: {
        name: 'rate-limiting-advanced',
        config: {
          redis: {
            username: '{vault://my-hcv/secret/redisHcvUser}',
            password: `{vault://gcp/rla_redisp?project_id=${gcpProjectId}}`,
          },
        },
      },
    });
    logResponse(patchResp);

    expect(patchResp.status, 'Status should be 200').to.equal(200);
    expect(
      patchResp.data.config.redis.username,
      'Should replace redis username with reference'
    ).to.equal('{vault://my-hcv/secret/redisHcvUser}');
    expect(
      patchResp.data.config.redis.password,
      'Should replace redis password with reference'
    ).to.equal(`{vault://gcp/rla_redisp?project_id=${gcpProjectId}}`);

    await wait(waitTime); // eslint-disable-line no-restricted-syntax
    await doBasicRateLimitCheck();
  });

  it('should rate limit with redis password aws and username gcp vault entity referenced', async function () {
    // changing RLA Plugin redis username reference to gcp vault entity and password to aws vault entity reference

    const patchResp = await axios({
      method: 'patch',
      url: `${pluginUrl}/${rlaPluginId}`,
      data: {
        name: 'rate-limiting-advanced',
        config: {
          redis: {
            username: `{vault://my-gcp/rla_redisu}`,
            password: '{vault://my-aws/gateway-secret-test/rla_redisp}',
          },
        },
      },
    });
    logResponse(patchResp);

    expect(patchResp.status, 'Status should be 200').to.equal(200);
    expect(
      patchResp.data.config.redis.username,
      'Should replace redis username with reference'
    ).to.equal(`{vault://my-gcp/rla_redisu}`);
    expect(
      patchResp.data.config.redis.password,
      'Should replace redis password with reference'
    ).to.equal('{vault://my-aws/gateway-secret-test/rla_redisp}');

    await wait(waitTime); // eslint-disable-line no-restricted-syntax
    await doBasicRateLimitCheck();
  });

  after(async function () {
    // need to delete cache for secret referencing to work with updated secrets
    await deleteCache();
    ['my-hcv', 'my-env', 'my-aws', 'my-gcp'].forEach(async (backendVault) => {
      await deleteVaultEntity(backendVault);
    });
    await deleteHcvSecret('secret', 'secret');
    await deleteGatewayRoute(routeId);
    await deleteGatewayService(serviceId);
  });
});
