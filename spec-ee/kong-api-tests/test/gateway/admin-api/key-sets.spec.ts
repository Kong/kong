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

describe('Gateway Admin API: Key-Sets For jwe-decrypt plugin', function () {
  const url = `${getBasePath({
    environment: isGateway() ? Environment.gateway.admin : undefined,
  })}/key-sets`;

  const keySetPayload = {
    name: 'jwe-key-set',
  };
  let keySetId = String;
  let keySetNoNameId = String;
  let keySetPatchId = String;
  const tag1 = 'jwe-key-set-tag';

  const assertRespDetails = (response: AxiosResponse) => {
    const resp = response.data;
    expect(resp.tags, 'Should not have tags').to.be.null;
    expect(resp.id, 'Should have id of type string').to.be.a('string');
    expect(resp.created_at, 'created_at should be a number').to.be.a('number');
    expect(resp.updated_at, 'updated_at should be a number').to.be.a('number');
  };

  it('should create a key set', async function () {
    const resp = await axios({
      method: 'post',
      url,
      data: keySetPayload,
    });

    logResponse(resp);
    expect(resp.status, 'Status should be 201').equal(201);
    expect(resp.data.name, 'Should have correct service name').equal(
      keySetPayload.name
    );
    assertRespDetails(resp);
    keySetId = resp.data.id;
  });

  it('should create a key set without supplying payload', async function () {
    const resp = await axios({
      method: 'post',
      url,
    });

    logResponse(resp);
    expect(resp.status, 'Status should be 201').equal(201);
    expect(resp.data.name, 'Should have "null" as name').equal(null);
    assertRespDetails(resp);
    keySetNoNameId = resp.data.id;
  });

  it('should not create a key set with same name', async function () {
    const resp = await postNegative(url, keySetPayload);
    logResponse(resp);

    expect(resp.status, 'Status should be 409').equal(409);
    expect(resp.data.name, 'Should have correct error name').equal(
      'unique constraint violation'
    );
    expect(resp.data.message, 'Should have correct error name').equal(
      `UNIQUE violation detected on '{name="${keySetPayload.name}"}'`
    );
  });

  it('should get the key set by name', async function () {
    const resp = await axios(`${url}/${keySetPayload.name}`);
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.name, 'Should have correct service name').equal(
      keySetPayload.name
    );
    assertRespDetails(resp);
  });

  it('should get the key-set by id', async function () {
    const resp = await axios(`${url}/${keySetId}`);
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.name, 'Should have correct service name').equal(
      keySetPayload.name
    );
    assertRespDetails(resp);
  });

  it('should patch the key set', async function () {
    const resp = await axios({
      method: 'patch',
      url: `${url}/${keySetId}`,
      data: {
        tags: [tag1],
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.tags, 'Array Size should equal 1').length(1);
    expect(
      resp.data.tags[0],
      'Single tag should be "jwe-key-set-tag"'
    ).to.equal(tag1);
    keySetPatchId = resp.data.id;
  });

  it('should get the recently patched key set', async function () {
    const resp = await axios(`${url}/${keySetPatchId}`);
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.name, 'Should have correct service name').equal(
      keySetPayload.name
    );
    expect(
      resp.data.tags[0],
      'Single tag should be "jwe-key-set-tag"'
    ).to.equal(tag1);
  });

  it('should get the key-sets', async function () {
    const resp = await axios(`${url}`);
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.data, 'Should have correct array length').to.have.length(
      2
    );
  });

  it('should not get the key set by wrong name', async function () {
    const resp = await getNegative(`${url}/wrong`);
    logResponse(resp);

    expect(resp.status, 'Should have correct error code').to.equal(404);
    expect(resp.data.message, 'Should have correct error message').to.equal(
      'Not found'
    );
  });

  it('should not get the key set by wrong id', async function () {
    const resp = await getNegative(
      `${url}/650d4122-3928-45a1-909d-73921163bb13`
    );
    logResponse(resp);

    expect(resp.status, 'Should respond with error').to.equal(404);
    expect(resp.data.message, 'Should have correct error message').to.equal(
      'Not found'
    );
  });

  it('should delete the key set by name', async function () {
    const resp = await axios({
      method: 'delete',
      url: `${url}/${keySetPayload.name}`,
    });
    logResponse(resp);
    expect(resp.status, 'Status should be 204').to.equal(204);
  });

  it('should delete the key set by id', async function () {
    const resp = await axios({
      method: 'delete',
      url: `${url}/${keySetNoNameId}`,
    });
    logResponse(resp);
    expect(resp.status, 'Status should be 204').to.equal(204);
  });
});
