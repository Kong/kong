import {
  Environment,
  expect,
  getBasePath,
  getNegative,
  postNegative,
  logResponse,
  isGateway,
} from '@support';
import axios from 'axios';

describe('@smoke: Gateway Admin API: Upstreams', function () {
  const url = `${getBasePath({
    environment: isGateway() ? Environment.gateway.admin : undefined,
  })}/upstreams`;

  // Setting up test variables
  const name = 'test-upstream';
  const putName = 'put-test';
  const patchName = 'patch-test';
  const negTestName = 'negative-test';

  const uuid = 'd0ffcef9-a28c-470c-9e6f-e40075a7c179';
  const invalidName = 'ÅÍÎÏ˝ÓÔÒÚÆ';
  const tag = 'testtag';
  const updateTag = 'testtag2';

  let upstreamData: any;

  it('should create upstream by name', async function () {
    const resp = await axios({
      method: 'post',
      url: url,
      data: {
        name: name,
      },
    });
    upstreamData = {
      name: resp.data.name,
      id: resp.data.id,
    };

    expect(resp.status, 'should return status 201').to.equal(201);
    expect(resp.data, 'should return id').to.have.property('id');
    expect(resp.data.name, 'should return expected name').to.equal(
      upstreamData.name
    );
  });

  it('should get the created upstream', async function () {
    const resp = await axios(url);
    logResponse(resp);

    expect(resp.status, 'should return status 200').to.equal(200);
    expect(
      resp.data.data.length,
      'should have at least one upstream in list'
    ).to.be.at.least(1);
    expect(resp.data.data[0].id, 'should have correct id').to.equal(
      upstreamData.id
    );
    expect(resp.data.data[0].name, 'should have expected name').to.equal(
      upstreamData.name
    );
    expect(
      resp.data.data[0].algorithm,
      'should have round-robin algo by default'
    ).to.equal('round-robin');
  });

  it('should not create upstream with same name', async function () {
    const resp = await postNegative(url, { name: upstreamData.name }, 'post');
    logResponse(resp);

    expect(resp.status, 'should return 409 status').to.equal(409);
    expect(resp.data.message, 'should return correct error message').to.equal(
      `UNIQUE violation detected on '{name="${upstreamData.name}"}'`
    );
  });

  it('should delete upstream by id', async function () {
    const resp = await axios({
      url: `${url}/${upstreamData.id}`,
      method: 'delete',
    });
    logResponse(resp);

    expect(resp.status, 'should return status 204').to.equal(204);
  });

  it.skip('should return 404 when attempting to delete upstream that does not exist', async function () {
    // eslint-disable-next-line @typescript-eslint/no-unused-vars
    const resp = await postNegative(
      `${url}/not-an-upstream-at-all`,
      {},
      'delete'
    );
    logResponse(resp);
    // TODO: uncomment this check when FT-2645 is resolved
    //expect(resp.status, 'should return status 404').to.equal(404);
  });

  it('should not create upstream with empty body', async function () {
    const resp = await postNegative(`${url}`, {}, 'post');
    logResponse(resp);

    expect(resp.status, 'should return 400 status code').to.equal(400);
    expect(resp.data.message, 'should return correct error message').to.equal(
      'schema violation (name: required field missing)'
    );
  });

  it('should not create upstream with invalid name', async function () {
    const resp = await postNegative(`${url}`, { name: invalidName }, 'post');
    logResponse(resp);

    expect(resp.status, 'should return 400 status code').to.equal(400);
    expect(resp.data.message, 'should return correct error message').to.equal(
      "schema violation (name: Invalid name ('ÅÍÎÏ˝ÓÔÒÚÆ'); must be a valid hostname)"
    );
  });

  // TODO: uncomment headers line and check when FT-2646 is resolved
  it('should create upstream with valid healthcheck parameters', async function () {
    const resp = await axios({
      url: `${url}`,
      method: 'post',
      data: {
        name: upstreamData.name,
        healthchecks: {
          active: {
            timeout: 2,
            unhealthy: {
              interval: 1,
              tcp_failures: 5,
              timeouts: 1,
              http_failures: 5,
              http_statuses: [500],
            },
            type: 'http',
            concurrency: 11,
            // headers: [{ 'X-Content-Type-Options': ['nosniff'] }],
            healthy: {
              interval: 1,
              successes: 1,
              http_statuses: [200, 204, 302, 201],
            },
            http_path: '/',
            https_sni: 'example.com',
            https_verify_certificate: true,
          },
          passive: {
            type: 'http',
            unhealthy: {
              http_statuses: [500],
              http_failures: 3,
              timeouts: 1,
              tcp_failures: 1,
            },
            healthy: {
              http_statuses: [200, 201],
              successes: 2,
            },
          },
          threshold: 23,
        },
      },
    });
    logResponse(resp);

    expect(resp.status, 'should return 201 status').to.equal(201);
    expect(resp.data, 'should have id in response').to.have.property('id');
    expect(
      resp.data.healthchecks.active.healthy.successes,
      'should have correct healthcheck active success value'
    ).to.equal(1);
    expect(
      resp.data.healthchecks.active.unhealthy.http_failures,
      'should have correct healthcheck http failure value'
    ).to.equal(5);
    expect(
      resp.data.healthchecks.passive.healthy.successes,
      'should have correct healthcheck passive success value'
    ).to.equal(2);
    expect(
      resp.data.healthchecks.passive.unhealthy.http_failures,
      'should have correct healthcheck passive http failure value'
    ).to.equal(3);
    expect(
      resp.data.healthchecks.threshold,
      'should have correct healthcheck threshold value'
    ).to.equal(23);
    // expect(
    //   resp.data.healthchecks.active.headers,
    //   'should have correct headers'
    // ).to.equal(`[{ 'X-Content-Type-Options': ['nosniff'] }]`);
  });

  it('should delete upstream with healthcheck params by name', async function () {
    const resp = await axios({
      url: `${url}/${upstreamData.name}`,
      method: 'delete',
    });
    logResponse(resp);

    expect(resp.status, 'should return status 204').to.equal(204);
  });

  it('should not create upstream with invalid healthcheck success parameters (active)', async function () {
    const resp = await postNegative(
      `${url}`,
      {
        name: negTestName,
        healthchecks: {
          active: {
            healthy: {
              successes: -1,
            },
          },
        },
      },
      'post'
    );
    logResponse(resp);

    expect(resp.status, 'should return 400 status').to.equal(400);
    expect(resp.data.message, 'should have correct error message').to.contain(
      'value should be between 0 and 255'
    );
  });

  it('should not create upstream with invalid value passed into http_statuses (active)', async function () {
    const resp = await postNegative(
      `${url}`,
      {
        name: negTestName,
        healthchecks: { active: { healthy: { http_statuses: ['200'] } } },
      },
      'post'
    );

    expect(resp.status, 'should return 400 status code').to.equal(400);
    expect(resp.data.message, 'should return correct error message').to.contain(
      'expected an integer'
    );
  });

  it('should not create upstream with invalid value passed into http_statuses (passive)', async function () {
    const resp = await postNegative(
      `${url}`,
      {
        name: negTestName,
        healthchecks: { passive: { healthy: { http_statuses: ['200'] } } },
      },
      'post'
    );
    logResponse(resp);

    expect(resp.status, 'should return 400 status code').to.equal(400);
    expect(resp.data.message, 'should return correct error message').to.contain(
      'expected an integer'
    );
  });

  it('should not create upstream with invalid headers passed into active healthchecks', async function () {
    const resp = await postNegative(
      `${url}`,
      {
        name: negTestName,
        healthchecks: {
          active: { headers: [{ 'not a header': ['test'] }] },
        },
      },
      'post'
    );
    logResponse(resp);

    expect(resp.status, 'should return 400 status code').to.equal(400);
    //TODO: uncomment when header bug fixed
    // expect(resp.data.message, 'should return correct error message').to.contain(
    //   'invalid header'
    // );
  });

  // TODO: reenable these tests after FT-2643 is resolved
  it.skip('should create upstream with valid algorithm parameter', async function () {
    const resp = await axios({
      url: `${url}/`,
      method: 'post',
      data: {
        name: upstreamData.name,
        algorithm: 'consistent-hashing',
      },
    });
    logResponse(resp);

    expect(resp.status, 'should return 201 status').to.equal(201);
    expect(resp.data, 'should have id in response').to.have.property('id');
    expect(resp.data.name, 'should return correct name').to.equal(
      upstreamData.name
    );
    expect(resp.data.algorithm, 'should have updated algorithm').to.equal(
      'consistent-hashing'
    );
  });

  it.skip('should delete the upstream with algorithm param by name', async function () {
    const resp = await axios({
      url: `${url}/${upstreamData.name}`,
      method: 'delete',
    });
    logResponse(resp);

    expect(resp.status, 'should return status 204').to.equal(204);
  });

  it('should not create upstream with invalid algorithm', async function () {
    const resp = await postNegative(
      `${url}`,
      {
        name: negTestName,
        algorithm: 'round-connections',
      },
      'post'
    );
    logResponse(resp);

    expect(resp.status, 'should return 400 status code').to.equal(400);
    expect(resp.data.message, 'should return correct error message').to.equal(
      'schema violation (algorithm: expected one of: consistent-hashing, least-connections, round-robin, latency)'
    );
  });

  it('should create upstream with valid host header', async function () {
    const resp = await axios({
      url: `${url}`,
      method: 'post',
      data: {
        name: upstreamData.name,
        host_header: 'example.com',
      },
    });
    logResponse(resp);

    expect(resp.status, 'should return 201 status').to.equal(201);
    expect(resp.data, 'should have id in response').to.have.property('id');
    expect(resp.data.host_header, 'should have correct host header').to.equal(
      'example.com'
    );
  });

  it('should delete the upstream with host header by name', async function () {
    const resp = await axios({
      url: `${url}/${upstreamData.name}`,
      method: 'delete',
    });
    logResponse(resp);

    expect(resp.status, 'should return status 204').to.equal(204);
  });

  it('should not create upstream with invalid host header', async function () {
    const resp = await postNegative(
      `${url}`,
      { name: negTestName, host_header: 'not a header' },
      'post'
    );
    logResponse(resp);

    expect(resp.status, 'should return 400 status').to.equal(400);
    expect(resp.data.message, 'should have correct error message').to.equal(
      'schema violation (host_header: invalid hostname: not a header)'
    );
  });

  it('should create upstream using PUT by name', async function () {
    // set new expected name
    upstreamData.name = putName;

    const resp = await axios({
      url: `${url}/${upstreamData.name}`,
      method: 'put',
      data: {
        name: upstreamData.name,
      },
    });
    logResponse(resp);

    // Commenting until FT-2607 fixed
    //expect(resp.status, 'should return status 201').to.equal(201);
    expect(resp.data.name, 'should have expected name').to.equal(
      upstreamData.name
    );
    expect(resp.data, 'should return id in response').to.have.property('id');

    // update current upstreamData
    upstreamData.id = resp.data.id;
  });

  it('should delete upstream by id', async function () {
    const resp = await axios({
      url: `${url}/${upstreamData.id}`,
      method: 'delete',
    });
    logResponse(resp);

    expect(resp.status, 'should return status 204').to.equal(204);
  });

  it('should create upstream using PUT and a valid uuid', async function () {
    // set new expected name
    upstreamData.name = name;

    const resp = await axios({
      url: `${url}/${uuid}`,
      method: 'put',
      data: {
        name: upstreamData.name,
      },
    });
    logResponse(resp);

    // commenting until FT-2607 fixed
    //expect(resp.status, 'should return status 201').to.equal(201);
    expect(resp.data.name, 'should have expected name').to.equal(
      upstreamData.name
    );
    expect(resp.data, 'should return id in response').to.have.property('id');

    // update current upstreamData
    upstreamData.id = resp.data.id;
  });

  it('should not create upstream with an invalid name using PUT', async function () {
    const resp = await postNegative(`${url}/invalid%20name`, {}, 'put');
    logResponse(resp);

    expect(resp.status, 'should return 400 status').to.equal(400);
    expect(resp.data.message, 'should return correct error message').to.equal(
      "Invalid name ('invalid name'); must be a valid hostname"
    );
  });

  it('should edit the upstream with PUT by id', async function () {
    // update upstream name
    upstreamData.name = putName;

    const resp = await axios({
      url: `${url}/${upstreamData.id}`,
      method: 'put',
      data: {
        name: upstreamData.name,
      },
    });
    logResponse(resp);

    expect(resp.status, 'should return status 200').to.equal(200);
    expect(resp.data.id, 'should include upstream id').to.be.equal(
      upstreamData.id
    );
    expect(resp.data.name, 'should have updated name').to.be.equal(
      upstreamData.name
    );
  });

  it('should get updated information getting by updated name', async function () {
    const resp = await axios(`${url}/${upstreamData.name}`);
    logResponse(resp);

    expect(resp.status, 'should return status 200').to.equal(200);
    expect(resp.data.name, 'should have updated name').to.be.equal(
      upstreamData.name
    );
  });

  it('should edit the upstream with PUT by name', async function () {
    const resp = await axios({
      url: `${url}/${upstreamData.name}`,
      method: 'put',
      data: {
        tags: [tag],
      },
    });
    logResponse(resp);

    expect(resp.status, 'should return status 200').to.equal(200);
    expect(resp.data.id, 'should include upstream id').to.be.equal(
      upstreamData.id
    );
    expect(resp.data.tags, 'should have updated tags').to.contain(tag);
  });

  it('should get PUT updated information getting by id', async function () {
    const resp = await axios(`${url}/${upstreamData.id}`);
    logResponse(resp);

    expect(resp.status, 'should return status 200').to.equal(200);
    expect(resp.data.name, 'should have expected name').to.be.equal(
      upstreamData.name
    );
    expect(resp.data.tags, 'should have updated tags').to.contain(tag);
  });

  it('should edit the upstream with PATCH by id', async function () {
    upstreamData.name = patchName;

    const resp = await axios({
      url: `${url}/${upstreamData.id}`,
      method: 'patch',
      data: {
        name: upstreamData.name,
        healthchecks: {
          passive: {
            unhealthy: {
              http_failures: 3,
            },
          },
        },
      },
    });
    logResponse(resp);

    expect(resp.status, 'should return status 200').to.equal(200);
    expect(resp.data.id, 'should include upstream id').to.be.equal(
      upstreamData.id
    );
    expect(resp.data.name, 'should have updated name').to.be.equal(
      upstreamData.name
    );
    expect(
      resp.data.healthchecks.passive.unhealthy.http_failures,
      'should have set failures to 3'
    ).to.equal(3);
  });

  it('should get patched information', async function () {
    const resp = await axios(`${url}/${upstreamData.id}`);
    logResponse(resp);

    expect(resp.status, 'should return status 200').to.equal(200);
    expect(resp.data.name, 'should have updated name').to.be.equal(
      upstreamData.name
    );
    expect(
      resp.data.healthchecks.passive.unhealthy.http_failures,
      'should have set failures to 3'
    ).to.equal(3);
  });

  it('should edit the upstream with PATCH by name', async function () {
    const resp = await axios({
      url: `${url}/${upstreamData.name}`,
      method: 'patch',
      data: {
        name: name,
        tags: [updateTag],
      },
    });
    logResponse(resp);

    upstreamData.name = name;

    expect(resp.status, 'should return status 200').to.equal(200);
    expect(resp.data.id, 'should include upstream id').to.be.equal(
      upstreamData.id
    );
    expect(resp.data.name, 'should have updated name').to.be.equal(
      upstreamData.name
    );
    expect(resp.data.tags, 'should have updated tags').to.contain(updateTag);
  });

  it('should get patched information by updated name', async function () {
    const resp = await axios(`${url}/${upstreamData.name}`);
    logResponse(resp);

    expect(resp.status, 'should return status 200').to.equal(200);
    expect(resp.data.name, 'should have updated name').to.be.equal(
      upstreamData.name
    );
    expect(resp.data.tags, 'should still include tags').to.contain(updateTag);
  });

  it('should not patch information with invalid name', async function () {
    const resp = await postNegative(
      `${url}/${upstreamData.id}`,
      { name: invalidName },
      'patch'
    );
    logResponse(resp);

    expect(resp.status, 'should return 400 status').to.equal(400);
    expect(resp.data.message, 'should return correct error message').to.equal(
      "schema violation (name: Invalid name ('ÅÍÎÏ˝ÓÔÒÚÆ'); must be a valid hostname)"
    );
  });

  it('should delete given upstream by id', async function () {
    const resp = await axios({
      url: `${url}/${upstreamData.id}`,
      method: 'delete',
    });
    logResponse(resp);

    expect(resp.status, 'should return status 204').to.equal(204);
  });

  it('should return 404 for deleted upstream', async function () {
    const resp = await getNegative(`${url}/${upstreamData.id}`);
    logResponse(resp);

    expect(resp.status, 'should return status 404').to.equal(404);
  });
});
