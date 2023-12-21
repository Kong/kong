import axios, { AxiosResponse } from 'axios';
import {
  expect,
  postNegative,
  getBasePath,
  Environment,
  logResponse,
  isGateway,
} from '@support';

describe('Vaults: AWS', function () {
  const url = `${getBasePath({
    environment: isGateway() ? Environment.gateway.admin : undefined,
  })}/vaults`;

  const vaultPrefix = 'awsprefix';
  const vaultPrefix2 = 'awsprefix2';
  const updatedPrefix = 'updatedawsprefix';
  const vaultName = 'aws';

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

  it('should create a new aws vault', async function () {
    const resp = await axios({
      method: 'post',
      url,
      data: {
        name: vaultName,
        prefix: vaultPrefix,
        description: 'aws vault',
        tags: ['awstag'],
        config: {
          region: 'us-east-2',
        },
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 201').to.equal(201);
    expect(resp.data.tags[0], 'Should have correct tags').to.eq('awstag');
    assertBasicDetails(resp, vaultName, vaultPrefix);
    expect(resp.data.description, 'Should have correct description').equal(
      'aws vault'
    );
    expect(resp.data.config.region, 'Should see region config').to.equal(
      'us-east-2'
    );
  });

  it('should not create aws vault with same prefix', async function () {
    const resp = await postNegative(
      url,
      {
        name: vaultName,
        prefix: vaultPrefix,
      },
      'post'
    );
    logResponse(resp);

    expect(resp.status, 'Status should be 409').to.equal(409);
    expect(resp.data.message, 'Should have correct error message').to.equal(
      `UNIQUE violation detected on '{prefix="awsprefix"}'`
    );
  });

  it('should not create aws vault with wrong region', async function () {
    const resp = await postNegative(
      url,
      {
        name: vaultName,
        prefix: 'otherprefix',
        config: {
          region: 'wrong-east-2',
        },
      },
      'post'
    );
    logResponse(resp);

    expect(resp.status, 'Status should be 400').to.equal(400);
    expect(resp.data.message, 'Should have correct error message').to.include(
      `schema violation (config.region: expected one of: us-east-2, us-east-1`
    );
  });

  it('should patch the aws vault', async function () {
    const resp = await axios({
      method: 'patch',
      url: `${url}/${vaultPrefix}`,
      data: {
        prefix: updatedPrefix,
        description: 'my vault',
        tags: ['aws', 'tag', 'more', 'tags'],
        config: {
          region: 'us-east-1',
        },
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.tags, 'Should see 4 tags').to.have.lengthOf(4);
    expect(resp.data.config.region, 'Should see config prefix').to.equal(
      'us-east-1'
    );
    assertBasicDetails(resp, vaultName, updatedPrefix);
  });

  it('should not patch the aws vault with wrong region', async function () {
    const resp = await postNegative(
      `${url}/${updatedPrefix}`,
      {
        prefix: 'someotherprefix',
        config: {
          region: 'us-east-23',
        },
      },
      'patch'
    );
    logResponse(resp);

    expect(resp.status, 'Status should be 400').to.equal(400);
    expect(resp.data.message, 'Should have correct error message').to.include(
      `schema violation (config.region: expected one of: us-east-2, us-east-1`
    );
    expect(
      resp.data.fields.config.region,
      'Should have correct error message for config'
    ).to.include(`expected one of: us-east-2, us-east-1, us-west-1`);
  });

  it('should not patch the aws vault with config.prefix', async function () {
    const resp = await postNegative(
      `${url}/${updatedPrefix}`,
      {
        prefix: 'someotherprefix',
        config: {
          region: 'us-west-2',
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
          region: 'us-west-2',
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
    expect(resp.data.message, 'Should have correct error message').to.equal(
      'schema violation (config.prefix: unknown field)'
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
          region: 'me-south-1',
        },
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(
      resp.data.config.region,
      'Should see updated config region'
    ).to.equal('me-south-1');
    assertBasicDetails(resp, vaultName, 'newprefix');
  });

  it('should retrieve the updated aws vault', async function () {
    const resp = await axios(`${url}/newprefix`);
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.config.region, 'Should see config region').to.equal(
      'me-south-1'
    );
    assertBasicDetails(resp, vaultName, 'newprefix');
  });

  it('should list all aws vaults', async function () {
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

  it('should delete aws vaults', async function () {
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
