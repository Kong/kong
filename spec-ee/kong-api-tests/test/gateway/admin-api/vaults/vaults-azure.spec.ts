import axios, { AxiosResponse } from 'axios';
import {
  expect,
  postNegative,
  getBasePath,
  Environment,
  logResponse,
  isGateway,
} from '@support';

describe('Vaults: Azure', function () {
  const url = `${getBasePath({
    environment: isGateway() ? Environment.gateway.admin : undefined,
  })}/vaults`;

  const vaultPrefix = 'azureprefix';
  const vaultPrefix2 = 'azureprefix2';
  const updatedPrefix = 'updatedazureprefix';
  const vaultName = 'azure';
  const vault_uri = 'http://azure-sdet.azure.com';

  const assertBasicDetails = (
    resp: AxiosResponse,
    vaultName: string,
    vaultPrefix: string
  ) => {
    expect(resp.data.name, 'Should have correct vault name').equal(vaultName);
    expect(resp.data.prefix, 'Should have correct vault prefix').equal(
      vaultPrefix
    );
    expect(resp.data.created_at, 'Should see created_at number').to.be.a(
      'number'
    );
    expect(resp.data.updated_at, 'Should see updated_at number').to.be.a(
      'number'
    );
  };

  it('should create a new Azure vault', async function () {
    const resp = await axios({
      method: 'post',
      url,
      data: {
        name: vaultName,
        prefix: vaultPrefix,
        description: 'Azure vault',
        config: {
          vault_uri: vault_uri,
          location: 'eastus',
        },
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 201').to.equal(201);
    assertBasicDetails(resp, vaultName, vaultPrefix);
    expect(resp.data.description, 'Should have correct description').equal(
      'Azure vault'
    );
    expect(resp.data.config.vault_uri, 'Should see vault_uri').to.equal(
      vault_uri
    );
  });

  it('should not create Azure vault with same prefix', async function () {
    const resp = await postNegative(
      url,
      {
        name: vaultName,
        prefix: vaultPrefix,
        config: {
          vault_uri: vault_uri,
          location: 'eastus',
        },
      },
      'post'
    );
    logResponse(resp);

    expect(resp.status, 'Status should be 409').to.equal(409);
    expect(resp.data.message, 'Should have correct error message').to.equal(
      `UNIQUE violation detected on '{prefix="azureprefix"}'`
    );
  });

  it('should not create Azure vault with wrong config key', async function () {
    const resp = await postNegative(
      url,
      {
        name: vaultName,
        prefix: 'someprefix',
        config: {
          unknown: 'unknown-keyname',
          location: "eastus",
        },
      },
      'post'
    );
    logResponse(resp);

    expect(resp.status, 'Status should be 400').to.equal(400);
    expect(resp.data.message, 'Should have correct error message').to.include(
      `2 schema violations (config.unknown: unknown field; config.vault_uri: required field missing)`
    );
  });

  it('should patch the Azure vault', async function () {
    const resp = await axios({
      method: 'patch',
      url: `${url}/${vaultPrefix}`,
      data: {
        prefix: updatedPrefix,
        description: 'my patched vault',
        tags: ['Azure', 'tag', 'more', 'tags'],
        config: {
          vault_uri: 'http://testid.com',
          location: 'westus',
        },
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.tags, 'Should see 4 tags').to.have.lengthOf(4);
    expect(
      resp.data.config.vault_uri,
      'Should see updated vault_uri'
    ).to.equal('http://testid.com');
    assertBasicDetails(resp, vaultName, updatedPrefix);
  });

  it('should not patch the Azure vault with wrong vault_uri', async function () {
    const resp = await postNegative(
      `${url}/${updatedPrefix}`,
      {
        prefix: 'someotherprefix',
        config: {
          vault_uri: true,
        },
      },
      'patch'
    );
    logResponse(resp);

    expect(resp.status, 'Status should be 400').to.equal(400);
    expect(resp.data.message, 'Should have correct error message').to.include(
      `schema violation (config.vault_uri: expected a string)`
    );
  });

  it('should create a vault with put request', async function () {
    const resp = await axios({
      method: 'put',
      url: `${url}/${vaultPrefix2}`,
      data: {
        name: vaultName,
        prefix: 'secondaryprefix',
        config: {
          vault_uri: vault_uri,
          location: 'eastus',
        },
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.prefix, 'Should see config prefix').to.equal(vaultPrefix2);
    assertBasicDetails(resp, vaultName, vaultPrefix2);
  });

  it('should update the vault with put request and prefix in uri', async function () {
    const resp = await axios({
      method: 'put',
      url: `${url}/newprefix`,
      data: {
        name: vaultName,
        prefix: vaultPrefix2,
        config: {
          location: 'test',
          vault_uri: 'http://test.com',
        },
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(
      resp.data.config.location,
      'Should see updated config location'
    ).to.equal('test');
    assertBasicDetails(resp, vaultName, 'newprefix');
  });

  it('should retrieve the updated Azure vault', async function () {
    const resp = await axios(`${url}/newprefix`);
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(
      resp.data.config.location,
      'Should see config location'
    ).to.equal('test');
    assertBasicDetails(resp, vaultName, 'newprefix');
  });

  it('should list all Azure vaults', async function () {
    const resp = await axios(url);
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(
      resp.data.data,
      'Should see all 3 items in the list'
    ).to.have.lengthOf(3);
    expect(
      resp.data.data.map((vault) => vault.prefix),
      'Should see all vault prefixes'
    ).to.have.members(['newprefix', updatedPrefix, vaultPrefix2]);
  });

  it('should delete Azure vaults', async function () {
    for (const prefix of ['newprefix', vaultPrefix2, updatedPrefix]) {
      const resp = await axios({
        method: 'delete',
        url: `${url}/${prefix}`,
      });
      logResponse(resp);

      expect(resp.status, 'Status should be 204').to.equal(204);
    }
  });
});
