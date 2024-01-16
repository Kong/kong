import axios, { AxiosResponse } from 'axios';
import {
  expect,
  postNegative,
  getBasePath,
  Environment,
  logResponse,
  isGateway,
} from '@support';

describe('Vaults: Hashicorp', function () {
  const url = `${getBasePath({
    environment: isGateway() ? Environment.gateway.admin : undefined,
  })}/vaults`;

  const vaultPrefix = 'hcvprefix';
  const vaultPrefix2 = 'hcvprefix2';
  const vaultPrefix3 = 'hcvprefix3';
  const updatedPrefix = 'updatedhcvprefix';
  const vaultName = 'hcv';
  const hcvHost = 'localhost';
  const hcvTokens = ['s.xtECOru4kQgJYtuK8GPShdCf', 'someothertoken'];

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

  it('should create hcv vault with host config only', async function () {
    const resp = await axios({
      method: 'post',
      url,
      data: {
        name: vaultName,
        prefix: vaultPrefix,
        description: 'hcv vault',
        tags: ['hcvtag'],
        config: {
          token: hcvTokens[0],
        },
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 201').to.equal(201);
    expect(resp.data.tags[0], 'Should have correct tags').to.eq('hcvtag');
    assertBasicDetails(resp, vaultName, vaultPrefix);
    expect(resp.data.description, 'Should have correct description').equal(
      'hcv vault'
    );
    expect(resp.data.config.host, 'Should see config host').to.equal(
      '127.0.0.1'
    );
    expect(resp.data.config.token, 'Should see config token').to.equal(
      hcvTokens[0]
    );

    expect(resp.data.config.protocol, 'Should see config protocol').to.equal(
      'http'
    );
    expect(resp.data.config.port, 'Should see config port').to.equal(8200);
    expect(resp.data.config.mount, 'Should see config mount').to.equal(
      'secret'
    );
    expect(resp.data.config.kv, 'Should see config kv').to.equal('v1');
  });

  it('should not create hcv vault without configuration', async function () {
    const resp = await postNegative(
      url,
      {
        name: vaultName,
        prefix: vaultPrefix,
      },
      'post'
    );
    logResponse(resp);

    expect(resp.status, 'Status should be 400').to.equal(400);
    expect(resp.data.message, 'Should have correct error message').to.include(
      `config.token: required field missing`
    );
  });

  it('should not create hcv vault with wrong protocol', async function () {
    const resp = await postNegative(
      url,
      {
        name: vaultName,
        prefix: 'otherprefix',
        config: {
          token: 'token',
          protocol: 'tcp',
        },
      },
      'post'
    );
    logResponse(resp);

    expect(resp.status, 'Status should be 400').to.equal(400);
    expect(resp.data.message, 'Should have correct error message').to.include(
      `schema violation (config.protocol: expected one of: http, https)`
    );
  });

  it('should not create hcv vault with wrong kv', async function () {
    const resp = await postNegative(
      url,
      {
        name: vaultName,
        prefix: 'otherprefix',
        config: {
          token: 'token',
          kv: 'v12',
        },
      },
      'post'
    );
    logResponse(resp);

    expect(resp.status, 'Status should be 400').to.equal(400);
    expect(resp.data.message, 'Should have correct error message').to.include(
      `schema violation (config.kv: expected one of: v1, v2)`
    );
    expect(
      resp.data.fields.config.kv,
      'Should have correct error text in config'
    ).to.equal('expected one of: v1, v2');
  });

  it('should not patch the hcv vault with region config', async function () {
    const resp = await postNegative(
      `${url}/${vaultPrefix}`,
      {
        prefix: 'someotherprefix',
        config: {
          region: 'us-east-2',
        },
      },
      'patch'
    );
    logResponse(resp);

    expect(resp.status, 'Status should be 400').to.equal(400);
    expect(resp.data.message, 'Should have correct error message').to.include(
      `schema violation (config.region: unknown field)`
    );
  });

  it('should not patch the hcv vault with prefix config', async function () {
    const resp = await postNegative(
      `${url}/${vaultPrefix}`,
      {
        prefix: 'someotherprefix',
        config: {
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

  it('should patch the hcv vault', async function () {
    const resp = await axios({
      method: 'patch',
      url: `${url}/${vaultPrefix}`,
      data: {
        prefix: updatedPrefix,
        description: 'my vault',
        tags: ['hcv', 'tag', 'more', 'tags'],
        config: {
          host: 'google.com',
          token: hcvTokens[1],
          kv: 'v2',
          mount: 'secret2',
        },
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.tags, 'Should see 2 tags').to.have.lengthOf(4);
    expect(resp.data.config.token, 'Should see config token').to.equal(
      hcvTokens[1]
    );
    expect(resp.data.config.port, 'Should see config port').to.equal(8200);
    expect(resp.data.config.mount, 'Should see config mount').to.equal(
      'secret2'
    );
    expect(resp.data.config.kv, 'Should see updated config kv').to.equal('v2');
    assertBasicDetails(resp, vaultName, updatedPrefix);
  });

  it('should retrieve the hcv vault', async function () {
    const resp = await axios(`${url}/${updatedPrefix}`);
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.config.host, 'Should see config host').to.equal(
      'google.com'
    );
    assertBasicDetails(resp, vaultName, updatedPrefix);
  });

  it('should not update the vault with put request and wrong config', async function () {
    const resp = await postNegative(
      `${url}/${updatedPrefix}`,
      {
        name: vaultName,
        prefix: 'anotherprefix',
        config: {
          foo: 'bar',
        },
      },
      'put'
    );
    logResponse(resp);

    expect(resp.status, 'Status should be 400').to.equal(400);
    expect(resp.data.message, 'Should have correct error message').to.include(
      'config.foo: unknown field'
    );
  });

  it('should create hcv vault with put request', async function () {
    const resp = await axios({
      method: 'put',
      url: `${url}/${vaultPrefix2}`,
      data: {
        name: vaultName,
        prefix: vaultPrefix2,
        config: {
          token: 'bar',
          kv: 'v1',
          host: hcvHost,
        },
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.config.port, 'Should see config port').to.equal(8200);
    expect(resp.data.config.mount, 'Should see config mount').to.equal(
      'secret'
    );
    expect(resp.data.config.kv, 'Should see config kv').to.equal('v1');
    expect(resp.data.config.host, 'Should see config host').to.equal(hcvHost);
    expect(resp.data.config.token, 'Should see correct config token').to.equal(
      'bar'
    );
  });

  it('should not create hcv vault with approle auth method and without role id', async function () {
    const resp = await postNegative(
      `${url}/${vaultPrefix3}`,
      {
        name: vaultName,
        prefix: vaultPrefix3,
        config: {
          auth_method: 'approle',
          kv: 'v1',
          host: hcvHost,
          approle_secret_id: '00000000-0000-0000-0000-000000000000',
        },
      }, 'put'
    );
    logResponse(resp);

    expect(resp.status, 'Status should be 400').to.equal(400);
    expect(resp.data.message, 'Should have correct error message').to.include(
      'config.approle_role_id: required field missing'
    );
  });

  it('should create hcv vault with approle auth method', async function () {
    const resp = await axios({
      method: 'put',
      url: `${url}/${vaultPrefix3}`,
      data: {
        name: vaultName,
        prefix: vaultPrefix3,
        config: {
          auth_method: 'approle',
          kv: 'v1',
          host: hcvHost,
          approle_role_id: '00000000-0000-0000-0000-000000000000',
          approle_secret_id: '00000000-0000-0000-0000-000000000000',
        },
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.config.port, 'Should see config port').to.equal(8200);
    expect(resp.data.config.host, 'Should see config host').to.equal(hcvHost);
    expect(resp.data.config.auth_method, 'Should see correct config auth method').to.equal(
      'approle'
    );
    expect(resp.data.config.approle_role_id, 'Should see correct config approle role id').to.equal(
      '00000000-0000-0000-0000-000000000000'
    );
    expect(resp.data.config.approle_secret_id, 'Should see correct config approle secret id').to.equal(
      '00000000-0000-0000-0000-000000000000'
    );
  });

  it('should list all hcv vaults', async function () {
    const resp = await axios(url);
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.data, 'Should all 3 items in the list').to.have.lengthOf(
      3
    );
    expect(
      resp.data.data.map((vault) => vault.prefix),
      'Should see all vault prefixes'
    ).to.have.members([updatedPrefix, vaultPrefix2, vaultPrefix3]);
  });

  it('should delete hcv vaults', async function () {
    for (const prefix of [vaultPrefix2, updatedPrefix]) {
      const resp = await axios({
        method: 'delete',
        url: `${url}/${prefix}`,
      });
      logResponse(resp);
      expect(resp.status, 'Status should be 204').to.equal(204);
    }
  });
});
