import axios from 'axios';
import {
  expect,
  getBasePath,
  Environment,
  vars,
  createGatewayService,
  createRouteForService,
  randomString,
  wait,
  createHcvVault,
  createHcvVaultSecrets,
  getHcvVaultSecret,
  createAwsVaultEntity,
  createEnvVaultEntity,
  deleteHcvSecret,
  deleteCache,
  checkGwVars,
  logResponse,
  createGcpVaultEntity,
  isGateway,
  clearAllKongResources
} from '@support';

// ********* Note *********
// In order for this test to successfully run you need to have defined the following environment variables in all Kong nodes
// AWS_REGION: us-east-2
// AWS_ACCESS_KEY_ID: ${{ actualSecret}}
// AWS_SECRET_ACCESS_KEY: ${{ actualSecret }}
// GCP_SERVICE_ACCOUNT: ${{actualGcpAccountKey}}
// ********* End **********

describe('Vaults: Secret referencing in AWS-Lambda plugin', function () {
  checkGwVars('aws');

  let serviceId = '';
  let routeId = '';
  let awsPluginId = '';

  const path = `/${randomString()}`;
  const pluginUrl = `${getBasePath({
    environment: Environment.gateway.admin,
  })}/plugins`;

  const proxyUrl = getBasePath({ environment: isGateway() ? Environment.gateway.proxy : undefined });
  const gcpProjectId = 'gcp-sdet-test';
  const hcvPrefix = 'my-hcv'
  const hcvMount = 'secret'
  const hcvSecretPath = 'aws-secret'

  const awsFunctionName = 'gateway-awsplugin-test';
  const waitTime = 3000;
  // aws credentials to be created in hcv vault
  const awsAccessKey = vars.aws.AWS_ACCESS_KEY_ID;
  const awsSecretKey = vars.aws.AWS_SECRET_ACCESS_KEY;
  // env secrets (at this point should already exist in gateway/kong, see above Note) > AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
  // aws secrets > gateway-secret-test/ aws_access_key, aws_secret_key
  // gcp secrets > aws_access_key, aws_secret_key

  const doBasicRequestCheck = async () => {
    const resp = await axios(`${proxyUrl}${path}`);
    logResponse(resp);
    expect(resp.status, 'Status should be 200').to.equal(200);
  };

  const createPlugin = async (serviceId, routeId) => {
    const pluginPayload = {
      name: 'aws-lambda',
      service: {
        id: serviceId,
      },
      route: {
        id: routeId,
      },
      config: {
        aws_key: awsAccessKey,
        aws_secret: awsSecretKey,
        aws_region: 'us-east-2',
        function_name: awsFunctionName,
      },
    };

    const resp: any = await axios({
      method: 'post',
      url: pluginUrl,
      data: pluginPayload,
    });
    logResponse(resp);
    expect(resp.status, 'Status should be 201').to.equal(201);

    return resp.data
  };

  before(async function () {
    await clearAllKongResources();
    const service = await createGatewayService('VaultSecretAwsService');
    serviceId = service.id;
    const route = await createRouteForService(serviceId, [path]);
    routeId = route.id;
    const plugin = await createPlugin(serviceId, routeId)
    awsPluginId = plugin.id
    // creatting hcv vault entity
    await createHcvVaultSecrets({
      aws_access_key: awsAccessKey,
      aws_secret_key: awsSecretKey,
    }, hcvMount, hcvSecretPath);

    await createHcvVault();
    //  creating my-env vault entity with varaible reference prefix 'aws_'
    await createEnvVaultEntity('my-env', { prefix: 'aws_' });
    // creating my-aws vault entity
    await createAwsVaultEntity();
    // creating my-gcp vault entity
    await createGcpVaultEntity();
  });

  it('should create hcv vault entity and secrets', async function () {
    const resp = await getHcvVaultSecret(hcvMount, hcvSecretPath);

    expect(resp.data.aws_secret_key, 'Should see aws secret ket').to.equal(
      awsSecretKey
    );
    expect(resp.data.aws_access_key, 'Should see aws access key').to.equal(
      awsAccessKey
    );
  });

  it('should reference with aws access key hcv vault entity', async function () {
    const patchResp = await axios({
      method: 'patch',
      url: `${pluginUrl}/${awsPluginId}`,
      data: {
        name: 'aws-lambda',
        config: {
          aws_key: `{vault://${hcvPrefix}/${hcvSecretPath}/aws_access_key}`,
        },
      },
    });
    logResponse(patchResp);
   
    expect(patchResp.status, 'Status should be 200').to.equal(200);
    expect(patchResp.data.config.aws_key, 'Should have aws_key referenced').to.equal(
      `{vault://${hcvPrefix}/${hcvSecretPath}/aws_access_key}`
    );

    await wait(waitTime + 3000); // eslint-disable-line no-restricted-syntax
    await doBasicRequestCheck();
  });

  it('should reference with aws access and secret keys hcv vault entity', async function () {
    // changing aws-lambda plaintext aws_secret to hcv vault enittiy secret reference
    const patchResp = await axios({
      method: 'patch',
      url: `${pluginUrl}/${awsPluginId}`,
      data: {
        name: 'aws-lambda',
        config: {
          aws_secret: `{vault://${hcvPrefix}/${hcvSecretPath}/aws_secret_key}`,
        },
      },
    });
    logResponse(patchResp);

    expect(patchResp.status, 'Status should be 200').to.equal(200);
    expect(
      patchResp.data.config.aws_secret,
      'Should replace aws_secret with secret key reference'
    ).to.equal(`{vault://${hcvPrefix}/${hcvSecretPath}/aws_secret_key}`);

    await wait(waitTime); // eslint-disable-line no-restricted-syntax
    await doBasicRequestCheck();
  });

  it('should reference with aws access and secret keys hcv vault secrets', async function () {
    // changing aws-lambda plaintext aws_secret to hcv vault enittiy secret reference
    const patchResp = await axios({
      method: 'patch',
      url: `${pluginUrl}/${awsPluginId}`,
      data: {
        name: 'aws-lambda',
        config: {
          aws_key: `{vault://hcv/${hcvSecretPath}/aws_access_key}`,
          aws_secret: `{vault://hcv/${hcvSecretPath}/aws_secret_key}`,
        },
      },
    });
    logResponse(patchResp);

    expect(patchResp.status, 'Status should be 200').to.equal(200);
    expect(
      patchResp.data.config.aws_secret,
      'Should replace aws_secret with hcv secret key reference'
    ).to.equal(`{vault://hcv/${hcvSecretPath}/aws_secret_key}`);

    await wait(waitTime); // eslint-disable-line no-restricted-syntax
    await doBasicRequestCheck();
  });

  it('should reference with aws_access_key hcv and secret_key hcv vault entity secret', async function () {
    // changing aws-lambda plaintext aws_secret to hcv vault enittiy secret reference
    const patchResp = await axios({
      method: 'patch',
      url: `${pluginUrl}/${awsPluginId}`,
      data: {
        name: 'aws-lambda',
        config: {
          aws_key: `{vault://hcv/${hcvSecretPath}/aws_access_key}`,
          aws_secret: `{vault://${hcvPrefix}/${hcvSecretPath}/aws_secret_key}`,
        },
      },
    });
    logResponse(patchResp);

    expect(patchResp.status, 'Status should be 200').to.equal(200);
    expect(
      patchResp.data.config.aws_secret,
      'Should replace aws_secret with hcv secret key reference'
    ).to.equal(`{vault://${hcvPrefix}/${hcvSecretPath}/aws_secret_key}`);

    await wait(waitTime); // eslint-disable-line no-restricted-syntax
    await doBasicRequestCheck();
  });

  it('should reference with aws_access_key env and secret_key hcv vault entity', async function () {
    // changing aws-lambda aws_key to env secret reference
    const patchResp = await axios({
      method: 'patch',
      url: `${pluginUrl}/${awsPluginId}`,
      data: {
        name: 'aws-lambda',
        config: {
          aws_key: '{vault://env/aws_access_key_id}',
        },
      },
    });
    logResponse(patchResp);

    expect(patchResp.status, 'Status should be 200').to.equal(200);

    await wait(waitTime); // eslint-disable-line no-restricted-syntax
    await doBasicRequestCheck();
  });

  it('should reference with aws_access_key env and secret_key aws secrets', async function () {
    // changing aws-lambda aws_secret to aws secret reference
    const patchResp = await axios({
      method: 'patch',
      url: `${pluginUrl}/${awsPluginId}`,
      data: {
        name: 'aws-lambda',
        config: {
          aws_secret: '{vault://aws/gateway-secret-test/aws_secret_key}',
        },
      },
    });
    logResponse(patchResp);

    expect(patchResp.status, 'Status should be 200').to.equal(200);
    expect(
      patchResp.data.config.aws_secret,
      'Should replace aws_secret with secret key reference'
    ).to.equal('{vault://aws/gateway-secret-test/aws_secret_key}');

    await wait(waitTime); // eslint-disable-line no-restricted-syntax
    await doBasicRequestCheck();
  });

  it('should reference with aws_access_key env and secret_key aws vault entity secrets', async function () {
    // changing aws-lambda aws_secret to my-aws and aws_key to my-env vault enittiy reference
    const patchResp = await axios({
      method: 'patch',
      url: `${pluginUrl}/${awsPluginId}`,
      data: {
        name: 'aws-lambda',
        config: {
          // note, we are stripping aws_ part from the secret name
          aws_key: '{vault://my-env/access_key_id}',
          aws_secret: '{vault://my-aws/gateway-secret-test/aws_secret_key}',
        },
      },
    });
    logResponse(patchResp);

    expect(patchResp.status, 'Status should be 200').to.equal(200);

    await wait(waitTime); // eslint-disable-line no-restricted-syntax
    await doBasicRequestCheck();
  });

  it('should reference with aws_access_key hcv and secret_key aws vault entity secrets', async function () {
    const patchResp = await axios({
      method: 'patch',
      url: `${pluginUrl}/${awsPluginId}`,
      data: {
        name: 'aws-lambda',
        config: {
          aws_key: `{vault://${hcvPrefix}/${hcvSecretPath}/aws_access_key}`,
        },
      },
    });
    logResponse(patchResp);

    expect(patchResp.status, 'Status should be 200').to.equal(200);

    await wait(waitTime); // eslint-disable-line no-restricted-syntax
    await doBasicRequestCheck();
  });

  it('should reference with aws_access_key hcv and secret_key env vault entity secrets', async function () {
    const patchResp = await axios({
      method: 'patch',
      url: `${pluginUrl}/${awsPluginId}`,
      data: {
        name: 'aws-lambda',
        config: {
          // note, we are stripping aws_ part from the secret name
          aws_secret: '{vault://my-env/secret_access_key}',
        },
      },
    });
    logResponse(patchResp);

    expect(patchResp.status, 'Status should be 200').to.equal(200);

    await wait(waitTime); // eslint-disable-line no-restricted-syntax
    await doBasicRequestCheck();
  });

  it('should reference with aws_access_key aws vault and secret key aws vault entity secrets', async function () {
    const patchResp = await axios({
      method: 'patch',
      url: `${pluginUrl}/${awsPluginId}`,
      data: {
        name: 'aws-lambda',
        config: {
          aws_key: '{vault://aws/gateway-secret-test/aws_access_key}',
          aws_secret: '{vault://my-aws/gateway-secret-test/aws_secret_key}',
        },
      },
    });
    logResponse(patchResp);

    expect(patchResp.status, 'Status should be 200').to.equal(200);

    await wait(waitTime); // eslint-disable-line no-restricted-syntax
    await doBasicRequestCheck();
  });

  it('should reference with aws_access_key aws vault and secret key gcp vault entity secrets', async function () {
    const patchResp = await axios({
      method: 'patch',
      url: `${pluginUrl}/${awsPluginId}`,
      data: {
        name: 'aws-lambda',
        config: {
          aws_key: '{vault://aws/gateway-secret-test/aws_access_key}',
          aws_secret: '{vault://my-gcp/aws_secret_key}',
        },
      },
    });
    logResponse(patchResp);

    expect(patchResp.status, 'Status should be 200').to.equal(200);

    await wait(waitTime); // eslint-disable-line no-restricted-syntax
    await doBasicRequestCheck();
  });

  it('should reference with aws_access_key gcp vault and secret key gcp vault entity secrets', async function () {
    const patchResp = await axios({
      method: 'patch',
      url: `${pluginUrl}/${awsPluginId}`,
      data: {
        name: 'aws-lambda',
        config: {
          aws_key: `{vault://gcp/aws_access_key?project_id=${gcpProjectId}}`,
          aws_secret: '{vault://my-gcp/aws_secret_key}',
        },
      },
    });
    logResponse(patchResp);

    expect(patchResp.status, 'Status should be 200').to.equal(200);

    await wait(waitTime); // eslint-disable-line no-restricted-syntax
    await doBasicRequestCheck();
  });

  it('should reference with aws_access_key gcp vault and secret key hcv vault entity secrets', async function () {
    const patchResp = await axios({
      method: 'patch',
      url: `${pluginUrl}/${awsPluginId}`,
      data: {
        name: 'aws-lambda',
        config: {
          aws_secret: `{vault://${hcvPrefix}/${hcvSecretPath}/aws_secret_key}`,
        },
      },
    });
    logResponse(patchResp);

    expect(patchResp.status, 'Status should be 200').to.equal(200);

    await wait(waitTime); // eslint-disable-line no-restricted-syntax
    await doBasicRequestCheck();
  });

  it('should reference with aws_access_key gcp and secret key env vault entity secrets', async function () {
    const patchResp = await axios({
      method: 'patch',
      url: `${pluginUrl}/${awsPluginId}`,
      data: {
        name: 'aws-lambda',
        config: {
          aws_key: `{vault://my-env/access_key_id}`,
          aws_secret: '{vault://my-gcp/aws_secret_key}',
        },
      },
    });
    logResponse(patchResp);

    expect(patchResp.status, 'Status should be 200').to.equal(200);

    await wait(waitTime); // eslint-disable-line no-restricted-syntax
    await doBasicRequestCheck();
  });

  after(async function () {
    await deleteCache();
    await deleteHcvSecret(hcvMount, hcvSecretPath);
    await clearAllKongResources();
  });
});
