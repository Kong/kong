import axios from 'axios';
import {
  expect,
  getBasePath,
  Environment,
  createGatewayService,
  createRouteForService,
  deleteGatewayRoute,
  deleteGatewayService,
  randomString,
  deleteVaultEntity,
  deleteCache,
  logResponse,
  createAzureVaultEntity,
  waitForConfigRebuild,
  getNegative,
  checkGwVars,
  vars
} from '@support';

// ********* Note *********
// In order for this test to successfully run you need to 
// successfully staret gateway with AZURE_VAULT=true in https://github.com/Kong/gateway-docker-compose-generator
// 
// You will also need to have AZURE_FUNCTION_KEY variable defined in your test environment
// ********* End **********

describe('Vaults: Azure Secret referencing in Azure functions plugin', function () {
  checkGwVars('azure');
  this.timeout(50000)

  let serviceId = '';
  let routeId = '';
  let azurePluginId = '';

  const path = `/${randomString()}`;
  const pluginUrl = `${getBasePath({
    environment: Environment.gateway.admin,
  })}/plugins`;

  const proxyUrl = getBasePath({ environment: Environment.gateway.proxy });

  const azureFunctionKey = vars.azure.AZURE_FUNCTION_KEY;


  before(async function () {
    const service = await createGatewayService('AzureVaultFunctionService', { url: 'http://httpbin' });
    serviceId = service.id;
    const route = await createRouteForService(serviceId, [path]);
    routeId = route.id;

    await createAzureVaultEntity('my-azure', { ttl: 60, neg_ttl: 60, resurrect_ttl: 60 })
  });

  it('should create azure functions plugin', async function () {
    const pluginPayload = {
      name: 'azure-functions',
      service: {
        id: serviceId,
      },
      route: {
        id: routeId,
      },
      config: {
        apikey: azureFunctionKey,
        appname: 'sdet-function',
        functionname: 'sdet-http-trigger',
      },
    };

    const resp: any = await axios({
      method: 'post',
      url: pluginUrl,
      data: pluginPayload,
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 201').to.equal(201);
    azurePluginId  = resp.data.id;

    expect(azurePluginId , 'Plugin Id should be a string').to.be.string;
    expect(resp.data.config.apikey, 'Should have apikey referenced').to.equal(azureFunctionKey);

    await waitForConfigRebuild()
  });

  it('should trigger the azure function', async function () {
    const resp = await axios(`${proxyUrl}${path}?name=azureTest`);
    logResponse(resp);
  
    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data, 'Should have correct response text from function').to.include('azureTest')
  });

  it('should patch azure-functions plugin and reference apikey as Azure vault secret', async function () {
    // changing azure-functions apikey to a referenced secret value from Azure Vault
    const patchResp = await axios({
      method: 'patch',
      url: `${pluginUrl}/${azurePluginId}`,
      data: {
        name: 'azure-functions',
        config: {
          apikey: '{vault://azure/automation-azure-function-key}',
        },
      },
    });
    logResponse(patchResp);

    expect(patchResp.status, 'Status should be 200').to.equal(200);
    expect(
      patchResp.data.config.apikey,
      'Should replace apikey with azure secret reference'
    ).to.equal('{vault://azure/automation-azure-function-key}');

    await waitForConfigRebuild()
  });

  it('should trigger the azure function when apikey is referenced as Azure Vault secret', async function () {
    const resp = await axios(`${proxyUrl}${path}?name=azureTest88`);
    logResponse(resp);
  
    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data, 'Should have correct response text from function').to.include('azureTest88')
  });

  it('should trigger the azure function when apikey is referenced as Azure Vault entity secret', async function () {
    const patchResp = await axios({
      method: 'patch',
      url: `${pluginUrl}/${azurePluginId}`,
      data: {
        name: 'azure-functions',
        config: {
          apikey: '{vault://my-azure/automation-azure-function-key}',
        },
      },
    });
    logResponse(patchResp);

    expect(patchResp.status, 'Status should be 200').to.equal(200);
    expect(
      patchResp.data.config.apikey,
      'Should replace apikey with azure secret reference'
    ).to.equal('{vault://my-azure/automation-azure-function-key}');

    await waitForConfigRebuild()

    const resp = await axios(`${proxyUrl}${path}?name=azureTestEntity`);
    logResponse(resp);
  
    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data, 'Should have correct response text from function').to.include('azureTestEntity')
  });

  it('should not trigger the azure function when apikey is referenced as wrong Azure Vault entity secret', async function () {
    const patchResp = await axios({
      method: 'patch',
      url: `${pluginUrl}/${azurePluginId}`,
      data: {
        name: 'azure-functions',
        config: {
          apikey: '{vault://my-azure/automation-azure-function-wrong-key}',
        },
      },
    });
    logResponse(patchResp);

    expect(patchResp.status, 'Status should be 200').to.equal(200);
    expect(
      patchResp.data.config.apikey,
      'Should replace apikey with azure secret reference'
    ).to.equal('{vault://my-azure/automation-azure-function-wrong-key}');

    await waitForConfigRebuild()

    const resp = await getNegative(`${proxyUrl}${path}?name=azureWrongEntity`);
    logResponse(resp);
  
    expect(resp.status, 'Status should be 401').to.equal(401);
  });


  after(async function () {
    // need to delete cache for secret referencing to work with updated secrets
    await deleteCache();
    await deleteGatewayRoute(routeId);
    await deleteGatewayService(serviceId);
    await deleteVaultEntity('my-azure')
  });
});
