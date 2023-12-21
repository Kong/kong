import axios, { AxiosResponse } from 'axios';
import {
  expect,
  postNegative,
  getBasePath,
  Environment,
  logResponse,
  isGateway,
} from '@support';

describe('Vaults: GCP', function () {
  const url = `${getBasePath({
    environment: isGateway() ? Environment.gateway.admin : undefined,
  })}/vaults`;

  const vaultPrefix = 'gcpprefix';
  const vaultPrefix2 = 'gcpprefix2';
  const updatedPrefix = 'updatedgcpprefix';
  const vaultName = 'gcp';
  const gcpProjectId = 'gcp-sdet';

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

  it('should create a new gcp vault', async function () {
    const resp = await axios({
      method: 'post',
      url,
      data: {
        name: vaultName,
        prefix: vaultPrefix,
        description: 'gcp vault',
        config: {
          project_id: gcpProjectId,
        },
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 201').to.equal(201);
    assertBasicDetails(resp, vaultName, vaultPrefix);
    expect(resp.data.description, 'Should have correct description').equal(
      'gcp vault'
    );
    expect(resp.data.config.project_id, 'Should see project_id').to.equal(
      gcpProjectId
    );
  });

  it('should not create gcp vault with same prefix', async function () {
    const resp = await postNegative(
      url,
      {
        name: vaultName,
        prefix: vaultPrefix,
        config: {
          project_id: gcpProjectId,
        },
      },
      'post'
    );
    logResponse(resp);

    expect(resp.status, 'Status should be 409').to.equal(409);
    expect(resp.data.message, 'Should have correct error message').to.equal(
      `UNIQUE violation detected on '{prefix="gcpprefix"}'`
    );
  });

  it('should not create gcp vault with wrong config key', async function () {
    const resp = await postNegative(
      url,
      {
        name: vaultName,
        prefix: 'someprefix',
        config: {
          project: 'wrong-project-keyname',
        },
      },
      'post'
    );
    logResponse(resp);

    expect(resp.status, 'Status should be 400').to.equal(400);
    expect(resp.data.message, 'Should have correct error message').to.include(
      `2 schema violations (config.project: unknown field; config.project_id: required field missing)`
    );
  });

  it('should patch the gcp vault', async function () {
    const resp = await axios({
      method: 'patch',
      url: `${url}/${vaultPrefix}`,
      data: {
        prefix: updatedPrefix,
        description: 'my patched vault',
        tags: ['gcp', 'tag', 'more', 'tags'],
        config: {
          project_id: 'testid',
        },
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.tags, 'Should see 4 tags').to.have.lengthOf(4);
    expect(
      resp.data.config.project_id,
      'Should see updated project_id'
    ).to.equal('testid');
    assertBasicDetails(resp, vaultName, updatedPrefix);
  });

  it('should not patch the gcp vault with wrong project_id', async function () {
    const resp = await postNegative(
      `${url}/${updatedPrefix}`,
      {
        prefix: 'someotherprefix',
        config: {
          project_id: true,
        },
      },
      'patch'
    );
    logResponse(resp);

    expect(resp.status, 'Status should be 400').to.equal(400);
    expect(resp.data.message, 'Should have correct error message').to.include(
      `schema violation (config.project_id: expected a string)`
    );
  });

  it('should not patch the gcp vault with config.prefix', async function () {
    const resp = await postNegative(
      `${url}/${updatedPrefix}`,
      {
        prefix: 'someotherprefix',
        config: {
          project_id: 'test',
          preifx: 'SECURE_',
        },
      },
      'patch'
    );
    logResponse(resp);

    expect(resp.status, 'Status should be 400').to.equal(400);
    expect(resp.data.message, 'Should have correct error message').to.include(
      `schema violation (config.preifx: unknown field)`
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
          project_id: gcpProjectId,
        },
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.prefix, 'Should see config prefix').to.equal(vaultPrefix2);
    assertBasicDetails(resp, vaultName, vaultPrefix2);
  });

  it('should not update the vault with put request and wrong config', async function () {
    const resp = await postNegative(
      `${url}/${vaultPrefix2}`,
      {
        name: vaultName,
        prefix: vaultPrefix2,
        config: {
          prefix: 'bar',
        },
      },
      'put'
    );
    logResponse(resp);

    expect(resp.status, 'Status should be 400').to.equal(400);
    expect(resp.data.message, 'Should have correct error message').to.include(
      'schema violations (config.prefix: unknown field; config.project_id: required field missing)'
    );
  });

  it('should update the vault with put request and prefix in uri', async function () {
    const resp = await axios({
      method: 'put',
      url: `${url}/newprefix`,
      data: {
        name: vaultName,
        prefix: vaultPrefix2,
        config: {
          project_id: 'test',
        },
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(
      resp.data.config.project_id,
      'Should see updated config project_id'
    ).to.equal('test');
    assertBasicDetails(resp, vaultName, 'newprefix');
  });

  it('should retrieve the updated gcp vault', async function () {
    const resp = await axios(`${url}/newprefix`);
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(
      resp.data.config.project_id,
      'Should see config project_id'
    ).to.equal('test');
    assertBasicDetails(resp, vaultName, 'newprefix');
  });

  it('should list all gcp vaults', async function () {
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

  it('should delete gcp vaults', async function () {
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
