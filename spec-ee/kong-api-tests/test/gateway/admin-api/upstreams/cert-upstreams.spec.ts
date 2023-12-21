import { authDetails } from '@fixtures';
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

describe('Gateway Admin API: Cert-Associated Upstreams', function () {
  const url = `${getBasePath({
    environment: isGateway() ? Environment.gateway.admin : undefined,
  })}/certificates`;

  const name = 'test-cert-upstream';
  const putName = 'put-test-cert';
  const patchName = 'patch-test-cert';
  const negTestName = 'negative-test';

  const uuid = 'b1acbb2f-c06e-4123-b2d7-f5d397eedd72';
  const invalidName = 'ÅÍÎÏÓÔÒÚÆ';
  const tag = 'certtag';
  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  const updateTag = 'certtag-2';
  const hostHeader = 'example.com';
  const invalidHeader = 'not a header';

  let certificateData: any;
  let upstreamData: any;

  before(async function () {
    // Create a mock certificate to associate with the upstream
    const certificate = await axios({
      method: 'post',
      url: url,
      data: {
        cert: authDetails.cert.certificate,
        key: authDetails.cert.key,
      },
    });
    certificateData = {
      cert: certificate.data.cert,
      key: certificate.data.key,
      id: certificate.data.id,
    };
  });

  it('should create cert-associated upstream by name', async function () {
    const certUpstream = await axios({
      url: `${url}/${certificateData.id}/upstreams`,
      method: 'post',
      data: {
        name: name,
      },
    });
    logResponse(certUpstream);

    upstreamData = {
      name: certUpstream.data.name,
      id: certUpstream.data.id,
    };

    expect(certUpstream.status, 'should return status 201').to.equal(201);
    expect(certUpstream.data, 'should have id field').to.have.property('id');
    expect(certUpstream.data.name, 'should have expected name').to.equal(name);
    expect(
      certUpstream.data,
      'should contain client_certificate field'
    ).to.have.property('client_certificate');
    expect(
      certUpstream.data.client_certificate.id,
      'should match cert id to expect id'
    ).to.equal(certificateData.id);
  });

  it('should get cert-associated upstream', async function () {
    const resp = await axios(`${url}/${certificateData.id}/upstreams`);
    logResponse(resp);

    expect(resp.status, 'should return status 200').to.equal(200);
    expect(resp.data.data.length, 'should contain upstream in resp').to.equal(
      1
    );
    expect(resp.data.data[0].id, 'should include upstream id').to.be.equal(
      upstreamData.id
    );
    expect(resp.data.data[0].name, 'should have expected name').to.be.equal(
      upstreamData.name
    );
  });

  it('should not create upstream with same name', async function () {
    const resp = await postNegative(
      `${url}/${certificateData.id}/upstreams`,
      { name: upstreamData.name },
      'post'
    );
    logResponse(resp);

    expect(resp.status, 'should return 409 status').to.equal(409);
    expect(resp.data.message, 'should return correct error message').to.equal(
      `UNIQUE violation detected on '{name="${upstreamData.name}"}'`
    );
  });

  it('should delete cert-associated upstream by id', async function () {
    const resp = await axios({
      url: `${url}/${certificateData.id}/upstreams/${upstreamData.id}`,
      method: 'delete',
    });
    logResponse(resp);

    expect(resp.status, 'should return status 204').to.equal(204);
  });

  it('should return 404 when attempting to delete upstream that does not exist', async function () {
    const resp = await postNegative(
      `${url}/${certificateData.id}/upstreams/not-an-upstream-at-all`,
      {},
      'delete'
    );
    logResponse(resp);

    expect(resp.status, 'should return status 404').to.equal(404);
  });

  it('should not create upstream with empty body', async function () {
    const resp = await postNegative(
      `${url}/${certificateData.id}/upstreams`,
      {},
      'post'
    );
    logResponse(resp);

    expect(resp.status, 'should return status 400').to.equal(400);
    expect(resp.data.message, 'should return correct error message').to.equal(
      'schema violation (name: required field missing)'
    );
  });

  it('should not create upstream with invalid name', async function () {
    const resp = await postNegative(
      `${url}/${certificateData.id}/upstreams`,
      { name: invalidName },
      'post'
    );
    logResponse(resp);

    expect(resp.status, 'should return status 400').to.equal(400);
    expect(resp.data.message, 'should return correct error message').to.equal(
      `schema violation (name: Invalid name ('${invalidName}'); must be a valid hostname)`
    );
  });

  // TODO: uncomment headers line and check when FT-2646 is resolved
  it('should create upstream with valid healthcheck parameters', async function () {
    const resp = await axios({
      url: `${url}/${certificateData.id}/upstreams/`,
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
      method: 'post',
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

    upstreamData.id = resp.data.id;
  });

  it('should delete the upstream with healthcheck params by name', async function () {
    const resp = await axios({
      url: `${url}/${certificateData.id}/upstreams/${upstreamData.name}`,
      method: 'delete',
    });
    logResponse(resp);

    expect(resp.status, 'should return status 204').to.equal(204);
  });

  it('should not create upstream with invalid healthcheck success parameters (active)', async function () {
    const resp = await postNegative(
      `${url}/${certificateData.id}/upstreams`,
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
      `${url}/${certificateData.id}/upstreams`,
      {
        name: negTestName,
        healthchecks: { active: { healthy: { http_statuses: ['200'] } } },
      },
      'post'
    );
    logResponse(resp);

    expect(resp.status, 'should return 400 status code').to.equal(400);
    expect(resp.data.message, 'should return correct error message').to.contain(
      'expected an integer'
    );
  });

  it('should not create upstream with invalid value passed into http_statuses (passive)', async function () {
    const resp = await postNegative(
      `${url}/${certificateData.id}/upstreams`,
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
      `${url}/${certificateData.id}/upstreams/`,
      {
        name: negTestName,
        healthchecks: {
          active: {
            headers: [{ 'not valid header': [''] }],
          },
        },
      },
      'post'
    );
    logResponse(resp);

    expect(resp.status, 'should return 400 status').to.equal(400);
    expect(resp.data.message, 'should have correct error message').to.contain(
      'headers = "expected a string"'
    );
  });

  // TODO: reenable these tests after FT-2643 is resolved
  it.skip('should create upstream with valid algorithm parameter', async function () {
    const resp = await axios({
      url: `${url}/${certificateData.id}/upstreams/`,
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
      url: `${url}/${certificateData.id}/upstreams/${upstreamData.name}`,
      method: 'delete',
    });
    logResponse(resp);

    expect(resp.status, 'should return status 204').to.equal(204);
  });

  it('should not create upstream with invalid algorithm', async function () {
    const resp = await postNegative(
      `${url}/${certificateData.id}/upstreams`,
      { name: negTestName, algorithm: 'not-algo' },
      'post'
    );
    logResponse(resp);

    expect(resp.status, 'should return status 400').to.equal(400);
    expect(resp.data.message, 'should return correct error message').to.equal(
      `schema violation (algorithm: expected one of: consistent-hashing, least-connections, round-robin, latency)`
    );
  });

  it('should create upstream with valid host header', async function () {
    const resp = await axios({
      url: `${url}/${certificateData.id}/upstreams/`,
      method: 'post',
      data: {
        name: upstreamData.name,
        host_header: hostHeader,
      },
    });
    logResponse(resp);

    expect(resp.status, 'should return 201 status').to.equal(201);
    expect(resp.data, 'should have id in response').to.have.property('id');
    expect(resp.data.host_header, 'should have correct host header').to.equal(
      hostHeader
    );
    expect(resp.data.name, 'should have correct name').to.equal(
      upstreamData.name
    );

    upstreamData.id = resp.data.id;
    upstreamData.host_header = resp.data.host_header;
  });

  it('should delete the upstream with host header by name', async function () {
    const resp = await axios({
      url: `${url}/${certificateData.id}/upstreams/${upstreamData.name}`,
      method: 'delete',
    });
    logResponse(resp);

    expect(resp.status, 'should return status 204').to.equal(204);
  });

  it('should not create upstream with invalid host header', async function () {
    const resp = await postNegative(
      `${url}/${certificateData.id}/upstreams/`,
      { name: negTestName, host_header: invalidHeader },
      'post'
    );
    logResponse(resp);

    expect(resp.status, 'should return 400 status').to.equal(400);
    expect(resp.data.message, 'should return error message').to.equal(
      'schema violation (host_header: invalid hostname: not a header)'
    );
  });

  it('should create upstream using PUT by name', async function () {
    const resp = await axios({
      url: `${url}/${certificateData.id}/upstreams/${upstreamData.name}`,
      method: 'put',
      data: {
        name: upstreamData.name,
      },
    });
    logResponse(resp);

    // status code should be 201 as per FT-2607 or docs updated
    expect(resp.status, 'should return status 200').to.equal(200);
    expect(resp.data, 'should contain an id in response').to.have.property(
      'id'
    );
    expect(resp.data.name, 'should have correct name').to.equal(
      upstreamData.name
    );

    upstreamData.id = resp.data.id;
  });

  it('should delete upstream by id', async function () {
    const resp = await axios({
      url: `${url}/${certificateData.id}/upstreams/${upstreamData.id}`,
      method: 'delete',
    });
    logResponse(resp);

    expect(resp.status, 'should return status 204').to.equal(204);
  });

  it('should create upstream using PUT and a valid uuid', async function () {
    upstreamData.id = uuid;

    const resp = await axios({
      url: `${url}/${certificateData.id}/upstreams/${upstreamData.id}`,
      method: 'put',
      data: {
        name: upstreamData.name,
      },
    });
    logResponse(resp);

    // Commenting until FT-2607 fixed
    // expect(resp.status, 'should return status 201').to.equal(201);
    expect(resp.data.id, 'should have correct id').to.equal(upstreamData.id);
    expect(resp.data.name, 'should have correct name').to.equal(
      upstreamData.name
    );
  });

  it('should not create upstream with invalid name using PUT', async function () {
    const resp = await postNegative(
      `${url}/${certificateData.id}/upstreams/${invalidName}`,
      { name: invalidName },
      'put'
    );
    logResponse(resp);

    expect(resp.status, 'should return 400 status').to.equal(400);
    expect(resp.data.message, 'should have correct error message').to.include(
      'must be a valid hostname'
    );
  });

  it('should edit the upstream with PUT by id', async function () {
    upstreamData.name = putName;

    const resp = await axios({
      url: `${url}/${certificateData.id}/upstreams/${upstreamData.id}`,
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

  it('should get updated upstream information by updated name', async function () {
    const resp = await axios(
      `${url}/${certificateData.id}/upstreams/${upstreamData.name}`
    );
    logResponse(resp);

    expect(resp.status, 'should return status 200').to.equal(200);
    expect(resp.data.name, 'should have updated name').to.be.equal(
      upstreamData.name
    );
  });

  it('should edit the upstream with PUT by name', async function () {
    const resp = await axios({
      url: `${url}/${certificateData.id}/upstreams/${upstreamData.name}`,
      method: 'put',
      data: {
        tags: [tag],
      },
    });
    logResponse(resp);

    expect(resp.status, 'status should be 200').to.equal(200);
    expect(resp.data.id, 'should return id in response').to.equal(
      upstreamData.id
    );
    expect(resp.data.name, 'should have expected name').to.equal(
      upstreamData.name
    );
    expect(resp.data.tags, 'should return expected tags').to.contain(tag);
  });

  it('should get PUT updated upstream information by id', async function () {
    const resp = await axios(
      `${url}/${certificateData.id}/upstreams/${upstreamData.id}`
    );
    logResponse(resp);

    expect(resp.status, 'should return status 200').to.equal(200);
    expect(resp.data.name, 'should have updated name').to.be.equal(
      upstreamData.name
    );
    expect(resp.data.tags, 'should include updated tags').to.contain(tag);
  });

  it('should edit the upstream with PATCH by id', async function () {
    upstreamData.name = patchName;

    const resp = await axios({
      url: `${url}/${certificateData.id}/upstreams/${upstreamData.id}`,
      method: 'patch',
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

  it('should get patched information', async function () {
    const resp = await axios(
      `${url}/${certificateData.id}/upstreams/${upstreamData.id}`
    );
    logResponse(resp);

    expect(resp.status, 'should return status 200').to.equal(200);
    expect(resp.data.name, 'should have updated name').to.be.equal(
      upstreamData.name
    );
  });

  it('should edit the upstream with PATCH by name', async function () {
    const resp = await axios({
      url: `${url}/${certificateData.id}/upstreams/${upstreamData.name}`,
      method: 'patch',
      data: {
        name: name,
      },
    });
    logResponse(resp);

    expect(resp.status, 'should return status 200').to.equal(200);
    expect(resp.data.id, 'should include upstream id').to.be.equal(
      upstreamData.id
    );
    expect(resp.data.name, 'should have updated name').to.be.equal(name);

    upstreamData.name = name;
  });

  it('should get patched upstream information by updated name', async function () {
    const resp = await axios(
      `${url}/${certificateData.id}/upstreams/${upstreamData.name}`
    );
    logResponse(resp);

    expect(resp.status, 'should return status 200').to.equal(200);
    expect(resp.data.name, 'should have updated name').to.be.equal(
      upstreamData.name
    );
  });

  it('should not edit upstream with PATCH and invalid name', async function () {
    const resp = await postNegative(
      `${url}/${certificateData.id}/upstreams/not-a-current-name`,
      { tags: ['test-tag'] },
      'patch'
    );
    logResponse(resp);

    expect(resp.status, 'should return status 404').to.equal(404);
    expect(resp.data.message, 'should have correct error message').to.equal(
      'Not found'
    );
  });

  it('should delete upstream by id', async function () {
    const resp = await axios({
      url: `${url}/${certificateData.id}/upstreams/${upstreamData.id}`,
      method: 'delete',
    });
    logResponse(resp);

    expect(resp.status, 'should return status 204').to.equal(204);
  });

  it('should return 404 for deleted upstream', async function () {
    const resp = await getNegative(
      `${url}/${certificateData.id}/upstreams/${upstreamData.id}`
    );
    logResponse(resp);

    expect(resp.status, 'should return status 404').to.equal(404);
  });

  after(async function () {
    // remove the certificate
    await axios({
      url: `${url}/${certificateData.id}`,
      method: 'delete',
    });
  });
});
