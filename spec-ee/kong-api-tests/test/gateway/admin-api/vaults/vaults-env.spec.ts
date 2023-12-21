import axios, { AxiosResponse } from 'axios';
import {
  expect,
  getNegative,
  postNegative,
  getBasePath,
  Environment,
  logResponse,
  isGateway,
} from '@support';

describe('Vaults: Environment Variables', function () {
  const url = `${getBasePath({
    environment: isGateway() ? Environment.gateway.admin : undefined,
  })}/vaults`;

  const vaultPrefix = 'evprefix';
  const vaultPrefix2 = 'evprefix2';
  const otherPrefixes = ['newprefix', 'someprefix'];
  const updatedPrefix = 'evuprefix';
  const vaultName = 'env';
  const uuid = '752dcda0-ee05-45df-b973-301f351c1b6a';
  let vaultId: string;

  const assertBasicDetails = (
    resp: AxiosResponse,
    vaultName: string,
    vaultPrefix: string
  ) => {
    expect(resp.data.name, 'Should have correct vault name').equal(vaultName);
    expect(resp.data.prefix, 'Should have correct vault prefix').equal(
      vaultPrefix
    );
  };

  it('should create a new env vault', async function () {
    const resp = await axios({
      method: 'post',
      url,
      data: {
        name: vaultName,
        prefix: vaultPrefix,
        description: 'env vault',
        tags: ['envtag'],
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 201').to.equal(201);
    expect(resp.data.tags[0], 'Should have correct tags').to.eq('envtag');
    assertBasicDetails(resp, vaultName, vaultPrefix);
    expect(resp.data.description, 'Should have correct description').equal(
      'env vault'
    );
  });

  it('should not create a new vault with same prefix', async function () {
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
      `UNIQUE violation detected on '{prefix="evprefix"}'`
    );
  });

  it('should not create a new vault with wrong vaultname', async function () {
    const resp = await postNegative(
      url,
      {
        name: 'wrong',
        prefix: vaultPrefix,
      },
      'post'
    );
    logResponse(resp);

    expect(resp.status, 'Status should be 400').to.equal(400);
    expect(resp.data.message, 'Should have correct error message').to.equal(
      "schema violation (name: vault 'wrong' is not installed)"
    );
  });

  it('should not create a new vault without vaultname', async function () {
    const resp = await postNegative(
      url,
      {
        prefix: vaultPrefix,
      },
      'post'
    );
    logResponse(resp);

    expect(resp.status, 'Status should be 400').to.equal(400);
    expect(resp.data.message, 'Should have correct error message').to.equal(
      'schema violation (name: required field missing)'
    );
  });

  it('should not create a new vault without vaultprefix', async function () {
    const resp = await postNegative(
      url,
      {
        name: vaultName,
      },
      'post'
    );

    expect(resp.status, 'Status should be 400').to.equal(400);
    expect(resp.data.message, 'Should have correct error message').to.equal(
      'schema violation (prefix: required field missing)'
    );
  });

  it('should not create a new vault with uppercase letter', async function () {
    const resp = await postNegative(
      url,
      {
        name: vaultName,
        prefix: 'H',
      },
      'post'
    );
    logResponse(resp);

    expect(resp.status, 'Status should be 400').to.equal(400);
    expect(resp.data.message, 'Should have correct error message').to.equal(
      'schema violation (prefix: invalid value: H)'
    );
  });

  it('should not patch the env vault with invalid tags', async function () {
    const resp = await postNegative(
      `${url}/${vaultPrefix}`,
      {
        tags: 'envtag',
        config: {
          prefix: 'SECURE_',
        },
      },
      'patch'
    );
    logResponse(resp);

    expect(resp.status, 'Status should be 400').to.equal(400);
    expect(resp.data.message, 'should have correct error message').to.eq(
      'schema violation (tags: expected a set)'
    );
  });

  it('should patch the env vault', async function () {
    const resp = await axios({
      method: 'patch',
      url: `${url}/${vaultPrefix}`,
      data: {
        prefix: updatedPrefix,
        description: 'my vault',
        tags: ['env', 'tag'],
        config: {
          prefix: 'SECURE_',
        },
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.tags, 'Should see 2 tags').to.have.lengthOf(2);
    expect(resp.data.config.prefix, 'Should see config prefix').to.equal(
      'SECURE_'
    );
    assertBasicDetails(resp, vaultName, updatedPrefix);
  });

  it('should retrieve the updated env vault by prefix', async function () {
    const resp = await axios(`${url}/${updatedPrefix}`);
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.config.prefix, 'Should see config prefix').to.equal(
      'SECURE_'
    );
    assertBasicDetails(resp, vaultName, updatedPrefix);
  });

  it('should create a vault with put request and given valid uuid', async function () {
    const resp = await axios({
      method: 'put',
      url: `${url}/${uuid}`,
      data: {
        name: vaultName,
        prefix: vaultPrefix2,
        config: {
          prefix: 'my',
        },
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.config.prefix, 'Should see config prefix').to.equal('my');
    expect(resp.data.id, 'Should have the given id').to.equal(uuid);
    assertBasicDetails(resp, vaultName, vaultPrefix2);
    vaultId = resp.data.id;
  });

  it('should list all vaults', async function () {
    const resp = await axios(url);
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.data, 'Should see 2 items in the list').to.have.lengthOf(
      2
    );

    expect(
      resp.data.data.map((vault) => vault.prefix),
      'Should see all vault prefixes'
    ).to.have.members([updatedPrefix, vaultPrefix2]);
  });

  it('should delete the env vault by prefix name', async function () {
    const resp = await axios({
      method: 'delete',
      url: `${url}/${updatedPrefix}`,
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 204').to.equal(204);
  });

  it('should not retrieve the deleted vault', async function () {
    const resp = await getNegative(`${url}/${updatedPrefix}`);
    logResponse(resp);

    expect(resp.status, 'Status should be 404').to.equal(404);
  });

  it('should not create a vault with put request without name', async function () {
    const resp = await postNegative(
      `${url}/${uuid}`,
      {
        prefix: vaultPrefix2,
      },
      'put'
    );
    logResponse(resp);

    expect(resp.status, 'Status should be 400').to.equal(400);
    expect(resp.data.message, 'Should have correct error message').to.equal(
      'schema violation (name: required field missing)'
    );
  });

  it('should not update a vault with put request with wrong config', async function () {
    const resp = await postNegative(
      `${url}/${uuid}`,
      {
        name: vaultName,
        prefix: vaultPrefix2,
        config: {
          foo: 'bar',
        },
      },
      'put'
    );
    logResponse(resp);

    expect(resp.status, 'Status should be 400').to.equal(400);
    expect(resp.data.message, 'Should have correct error message').to.equal(
      'schema violation (config.foo: unknown field)'
    );
  });

  it('should update a vault with put request with valid data', async function () {
    const resp = await axios({
      method: 'put',
      url: `${url}/${uuid}`,
      data: {
        name: vaultName,
        prefix: otherPrefixes[0],
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.prefix, 'Should have correct prefix').to.equal(
      'newprefix'
    );
  });

  it('should retrieve the env vault by id', async function () {
    const resp = await axios(`${url}/${vaultId}`);
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    assertBasicDetails(resp, vaultName, otherPrefixes[0]);
  });

  it('should delete the env vault by id', async function () {
    const resp = await axios({
      method: 'delete',
      url: `${url}/${vaultId}`,
    });

    expect(resp.status, 'Status should be 204').to.equal(204);
  });

  it('should create a vault with put request and given prefix', async function () {
    const resp = await axios({
      method: 'put',
      url: `${url}/someprefix`,
      data: {
        name: vaultName,
        prefix: otherPrefixes[1],
      },
    });
    logResponse(resp);

    assertBasicDetails(resp, vaultName, otherPrefixes[1]);
    expect(resp.data.id, 'Should have autogenerated an id').to.be.string;
  });

  after(async function () {
    await axios({
      method: 'delete',
      url: `${url}/${otherPrefixes[1]}`,
    });
  });
});
