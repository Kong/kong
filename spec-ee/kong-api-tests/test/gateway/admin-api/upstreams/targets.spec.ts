import {
  Environment,
  expect,
  getBasePath,
  getNegative,
  isGwHybrid,
  postNegative,
  wait,
  logResponse,
  retryRequest,
} from '@support';
import axios from 'axios';

describe('Gateway Admin API: Targets', function () {
  const url = `${getBasePath({
    environment: Environment.gateway.admin,
  })}/upstreams`;

  const name = 'test-upstream';
  const target = 'example.com:8000';
  const targetNoPort = 'example.com';
  const updatedTarget = 'example.org:8000';
  const targetCreationMethod = 'post';
  const waitTime = 5000;
  const isHybrid = isGwHybrid();

  const tag = 'testtag';

  let upstreamData: any;
  let targetData: any;

  before(async function () {
    // Create an upstream to associate with the target
    const resp = await axios({
      method: 'post',
      url: url,
      data: {
        name: name,
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

    upstreamData = {
      name: resp.data.name,
      id: resp.data.id,
    };
  });

  it('should create target associated with upstream by upstream id', async function () {
    const resp = await axios({
      url: `${url}/${upstreamData.id}/targets`,
      method: targetCreationMethod,
      data: {
        target: target,
      },
    });
    logResponse(resp);

    expect(resp.status, 'should return 201 status').to.equal(201);
  });

  it('should see created target associated with upstream by upstream id', async function () {
    const resp = await axios(`${url}/${upstreamData.id}/targets`);
    targetData = {
      target: resp.data.data[0].target, // returned as host:8000 (or host:port if port given)
      id: resp.data.data[0].id,
    };
    logResponse(resp);

    expect(resp.status, 'should return 200 status').to.equal(200);
    expect(resp.data.data.length, 'should have one target in list').to.equal(1);
    expect(resp.data.data.id, 'should return id');
  });

  it('should not create target if not given target field', async function () {
    const resp = await postNegative(
      `${url}/${upstreamData.id}/targets`,
      {},
      targetCreationMethod
    );
    logResponse(resp);

    expect(resp.data.message, 'should return correct error message').to.equal(
      'schema violation (target: required field missing)'
    );
    expect(resp.status, 'should return 400 status code').to.equal(400);
  });

  it('should not create target if given invalid target field', async function () {
    const resp = await postNegative(
      `${url}/${upstreamData.name}/targets`,
      { target: 'not a valid target' },
      targetCreationMethod
    );
    logResponse(resp);

    expect(resp.data.message, 'should return correct error message').to.equal(
      'schema violation (target: Invalid target; not a valid hostname or ip address)'
    );
    expect(resp.status, 'should return 400 status code').to.equal(400);
  });

  //TODO: reenable this test when FT-2644 is resolved
  it.skip('should not create duplicate of existing target using host:port', async function () {
    const resp = await postNegative(
      `${url}/${upstreamData.id}/targets`,
      { target: target },
      'put'
    );
    logResponse(resp);

    expect(resp.status, 'should return 409 status code').to.equal(409);
    expect(resp.message, 'should return correct error message').to.equal(
      'UNIQUE violation detected on \'{target="example.com:8000"}\''
    );
  });

  it('should see created target associated with upstream using upstream id and /all', async function () {
    const resp = await axios(`${url}/${upstreamData.id}/targets/all`);
    logResponse(resp);

    expect(resp.status, 'should return 200 status').to.equal(200);
    expect(resp.data.data.length, 'should have one target in list').to.equal(1);
    expect(resp.data.data.id, 'should return id');
  });

  it('should delete given upstream target by upstream id and target host:port', async function () {
    const resp = await axios({
      url: `${url}/${upstreamData.id}/targets/${targetData.target}`,
      method: 'delete',
    });
    logResponse(resp);

    expect(resp.status, 'should return status 204').to.equal(204);
  });

  it('should create target associated with upstream by upstream id and using host only', async function () {
    const resp = await axios({
      url: `${url}/${upstreamData.id}/targets`,
      method: targetCreationMethod,
      data: {
        target: targetNoPort,
      },
    });
    logResponse(resp);

    expect(resp.status, 'should return 201 status').to.equal(201);
  });

  it('should not create duplicate of existing target using host only', async function () {
    const resp = await postNegative(
      `${url}/${upstreamData.id}/targets`,
      { target: targetNoPort },
      targetCreationMethod
    );
    logResponse(resp);

    expect(resp.status, 'should return 409 status code').to.equal(409);
    expect(resp.data.message, 'should return correct error message').to.contain(
      'UNIQUE violation detected on \'{target="example.com:8000"'
    );
  });

  it('should see created target associated with upstream by upstream id', async function () {
    const resp = await axios(`${url}/${upstreamData.id}/targets`);
    logResponse(resp);
    targetData.target = resp.data.data[0].target; // returned as host:8000 (or host:port if port given)
    targetData.id = resp.data.data[0].id;

    expect(resp.status, 'should return 200 status').to.equal(200);
    expect(resp.data.data.length, 'should have one target in list').to.equal(1);
    expect(resp.data.data.id, 'should return id');
  });

  it('should delete given upstream target by upstream id and target id', async function () {
    const resp = await axios({
      url: `${url}/${upstreamData.id}/targets/${targetData.id}`,
      method: 'delete',
    });
    logResponse(resp);

    expect(resp.status, 'should return status 204').to.equal(204);
  });

  it('should create target associated with upstream by upstream name', async function () {
    const resp = await axios({
      url: `${url}/${upstreamData.name}/targets`,
      method: targetCreationMethod,
      data: {
        target: target,
      },
    });
    logResponse(resp);

    expect(resp.status, 'should return 201 status').to.equal(201);
    expect(resp.data.target, 'should return correct target').to.equal(target);
    expect(resp.data, 'should return id in response').to.have.property('id');
    expect(resp.data, 'should have associated upstream').to.have.property(
      'upstream'
    );
    expect(resp.data.upstream.id, 'should have correct upstream id').to.equal(
      upstreamData.id
    );

    targetData.id = resp.data.id;
  });

  it('should edit target with PATCH using upstream id and target id', async function () {
    const resp = await axios({
      url: `${url}/${upstreamData.id}/targets/${targetData.id}`,
      method: 'patch',
      data: {
        target: updatedTarget,
      },
    });
    logResponse(resp);

    expect(resp.status, 'should return 200 status').to.equal(200);
    expect(resp.data.id, 'expect id to be in response').to.equal(targetData.id);
    expect(resp.data.target, 'expect updated target in response').to.equal(
      updatedTarget
    );

    targetData.target = updatedTarget;
  });

  it('should edit target with PATCH using upstream id and target', async function () {
    const resp = await axios({
      url: `${url}/${upstreamData.id}/targets/${targetData.target}`,
      method: 'patch',
      data: {
        tags: [tag],
      },
    });
    logResponse(resp);

    expect(resp.status, 'should return 200 status').to.equal(200);
    expect(resp.data.id, 'expect id to be in response').to.equal(targetData.id);
    expect(resp.data.target, 'expect updated target in response').to.equal(
      targetData.target
    );
    expect(resp.data.tags, 'should have updated tags').to.contain(tag);
  });

  it('should not edit target with PATCH if given invalid target', async function () {
    const resp = await postNegative(
      `${url}/${upstreamData.id}/targets/${targetData.target}`,
      { target: 'not a valid target' },
      'patch'
    );
    logResponse(resp);

    expect(resp.status, 'should return 400 status').to.equal(400);
    expect(resp.data.message, 'should have correct error message').to.equal(
      "schema violation (target: Invalid target ('not a valid target'); not a valid hostname or ip address)"
    );
  });

  it('should see updated target associated with upstream using upstream id', async function () {
    const resp = await axios(`${url}/${upstreamData.id}/targets`);
    logResponse(resp);

    expect(resp.status, 'should return 200 status').to.equal(200);
    expect(resp.data.data.length, 'should have one target in list').to.equal(1);
    expect(resp.data.data[0].id, 'should return id').to.equal(targetData.id);
    expect(resp.data.data[0].tags, 'should have updated tags').to.contain(tag);
    expect(resp.data.data[0].target, 'should have updated target').to.equal(
      targetData.target
    );
  });

  it('should edit target with PATCH using upstream name and target id', async function () {
    const resp = await axios({
      url: `${url}/${upstreamData.name}/targets/${targetData.id}`,
      method: 'patch',
      data: {
        target: target,
      },
    });
    logResponse(resp);

    expect(resp.status, 'should return 200 status').to.equal(200);
    expect(resp.data.id, 'expect id to be in response').to.equal(targetData.id);
    expect(resp.data.target, 'expect updated target in response').to.equal(
      target
    );

    targetData.target = target;
  });

  it('should edit target with PATCH using upstream name and target', async function () {
    const resp = await axios({
      url: `${url}/${upstreamData.name}/targets/${targetData.target}`,
      method: 'patch',
      data: {
        tags: [],
      },
    });
    logResponse(resp);

    expect(resp.status, 'should return 200 status').to.equal(200);
    expect(resp.data.id, 'expect id to be in response').to.equal(targetData.id);
    expect(resp.data.tags, 'expect updated tags in response').to.be.empty;
  });

  it('should see updated target associated with upstream using upstream name', async function () {
    const resp = await axios(`${url}/${upstreamData.name}/targets`);
    logResponse(resp);

    expect(resp.status, 'should return 200 status').to.equal(200);
    expect(resp.data.data.length, 'should have one target in list').to.equal(1);
    expect(resp.data.data[0].id, 'should return id').to.equal(targetData.id);
    expect(resp.data.data[0].tags, 'should have updated tags').to.be.empty;
    expect(resp.data.data[0].target, 'should have updated target').to.equal(
      targetData.target
    );
  });

  it('should set target to healthy using target id and address', async function () {
    // WAR: use POST /upstreams/{upstream id}/targets/{id}/healthy
    if (isHybrid) {
      this.skip();
    }
    await wait(waitTime); // eslint-disable-line no-restricted-syntax
    const resp = await axios({
      url: `${url}/${upstreamData.id}/targets/${targetData.id}/healthy`,
      method: 'put',
    });
    logResponse(resp);

    expect(resp.status, 'should return 204 status').to.equal(204);
  });

  it('should confirm healthy status', async function () {
    if (isHybrid) {
      this.skip();
    }

    const req = () => axios(`${url}/${upstreamData.id}/health`);

    const assertions = (resp) => {
      expect(resp.status, 'should return 200 status').to.equal(200);
      expect(resp.data.data[0].id, 'should match target id').to.equal(
        targetData.id
      );
      expect(
        resp.data.data[0].health,
        'should show a status of HEALTHY'
      ).to.equal('HEALTHY');
      expect(
        resp.data.data[0].upstream.id,
        'should show associated upstream in response'
      ).to.equal(upstreamData.id);
    };

    await retryRequest(req, assertions, 10000);
  });

  it('should set target to unhealthy using target', async function () {
    if (isHybrid) {
      this.skip();
    }
    const resp = await axios({
      url: `${url}/${upstreamData.id}/targets/${targetData.id}/unhealthy`,
      method: 'put',
    });
    logResponse(resp);

    expect(resp.status, 'should return 204 status').to.equal(204);
  });

  it('should confirm unhealthy status', async function () {
    if (isHybrid) {
      this.skip();
    }

    const req = () => axios(`${url}/${upstreamData.id}/health`);

    const assertions = (resp) => {
      expect(resp.status, 'should return 200 status').to.equal(200);
      expect(resp.data.data[0].id, 'should match target id').to.equal(
        targetData.id
      );
      expect(
        resp.data.data[0].health,
        'should show a status of UNHEALTHY'
      ).to.equal('UNHEALTHY');
      expect(
        resp.data.data[0].upstream.id,
        'should show associated upstream in response'
      ).to.equal(upstreamData.id);
    };

    await retryRequest(req, assertions, 10000);
  });

  it('should delete target by id associated with upstream by id', async function () {
    const resp = await axios({
      url: `${url}/${upstreamData.id}/targets/${targetData.id}`,
      method: 'delete',
    });
    logResponse(resp);

    expect(resp.status, 'should return 204 status').to.equal(204);
  });

  it('should return empty target list', async function () {
    const resp = await getNegative(`${url}/${upstreamData.id}/targets`);
    logResponse(resp);

    expect(resp.status, 'should return 200 status').to.equal(200);
    expect(resp.data.data.length, 'should have no targets').to.equal(0);
  });

  after(async function () {
    await axios({
      method: 'delete',
      url: `${url}/${upstreamData.id}`,
    });
  });
});
