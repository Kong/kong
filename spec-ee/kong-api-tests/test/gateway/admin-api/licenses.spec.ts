import axios, { AxiosResponse } from 'axios';
import { authDetails } from '@fixtures';
import {
  expect,
  Environment,
  getBasePath,
  postNegative,
  deleteGatewayService,
  logResponse,
  randomString,
  createGatewayService,
  isCI,
  wait,
} from '@support';

describe('Gateway /licenses API tests', function () {
  const isCIrun = isCI();
  const waitTime = 5000;
  const sampleId = '7ad8a306-cb1f-4b61-8b51-47c3604c3748';
  const licenseKey = 'ASDASDASDASDASDASDASDASDASD_a1VASASD';
  const validLicense = authDetails.license.valid;
  const inValidLicense = authDetails.license.invalid;

  const url = `${getBasePath({
    environment: Environment.gateway.admin,
  })}/licenses`;

  const pluginsUrl = `${getBasePath({
    environment: Environment.gateway.admin,
  })}/plugins`;

  let licenseId: string;
  let serviceId: string;
  let basePayload: any;

  const assertBasicRespDetails = (resp: AxiosResponse) => {
    expect(resp.data.created_at, 'Should have created_at entry').to.be.a(
      'number'
    );
    expect(resp.data.id, 'Should have id').to.be.string;
    expect(resp.data.updated_at, 'Should have updated_at entry').to.be.a(
      'number'
    );
    expect(resp.data.payload, 'Should have payload entry').to.be.string;
  };

  before(async function () {
    const service = await createGatewayService(randomString());
    serviceId = service.id;

    basePayload = {
      name: 'key-auth-enc',
      service: {
        id: serviceId,
      },
    };
  });

  it('should GET all licenses and see the existing license', async function () {
    const resp = await axios(url);
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.data, 'Should see 1 license in licenses').to.have.lengthOf(
      1
    );
    licenseId = resp.data.data[0].id;
  });

  it('should delete the license by id', async function () {
    const resp = await axios({
      method: 'delete',
      url: `${url}/${licenseId}`,
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 204').to.equal(204);
    await wait(waitTime); // eslint-disable-line no-restricted-syntax
  });

  it('should not POST an invalid license', async function () {
    const resp = await postNegative(url, { payload: inValidLicense });
    logResponse(resp);

    expect(resp.status, 'Status should be 400').to.equal(400);
    expect(resp.data.message, 'Should see correct error message').to.include(
      'Unable to validate license: validation failed'
    );
  });

  it('should not PATCH create a valid license', async function () {
    const resp = await postNegative(
      `${url}/${sampleId}`,
      { payload: validLicense },
      'PATCH'
    );
    logResponse(resp);

    expect(resp.status, 'Status should be 404').to.equal(404);
    expect(resp.data.message, 'Should see correct error message').to.include(
      'could not find the entity with primary key'
    );
  });

  if (isCIrun) {
    it('should not enable key-auth-enc ee plugin without license', async function () {
      const pluginPayload = {
        name: 'key-auth-enc',
        config: { key_names: ['apiKey'] },
      };

      const resp = await postNegative(pluginsUrl, pluginPayload);
      logResponse(resp);

      expect(resp.status, 'Status should be 400').to.equal(400);
      expect(
        resp.data.message,
        'Should see correct error message for plugin creation'
      ).to.include(`'key-auth-enc' is an enterprise only plugin`);
    });
  }

  it('should POST a valid license', async function () {
    const resp = await postNegative(url, { payload: validLicense });
    logResponse(resp);

    licenseId = resp.data.id;
    assertBasicRespDetails(resp);
  });

  if (isCIrun) {
    it('should enable key-auth-enc ee plugin with license', async function () {
      await wait(waitTime); // eslint-disable-line no-restricted-syntax

      const pluginPayload = {
        ...basePayload,
        config: { key_names: ['apiKey'] },
      };

      const resp = await axios({
        method: 'post',
        url: pluginsUrl,
        data: pluginPayload,
      });
      logResponse(resp);

      expect(resp.status, 'Status should be 201').to.equal(201);
    });
  }

  it('should not POST a duplicate valid license', async function () {
    const resp = await postNegative(url, { payload: validLicense });
    logResponse(resp);

    expect(resp.status, 'Status should be 409').to.equal(409);
    expect(resp.data.message, 'Should see correct error message').to.include(
      'UNIQUE violation detected'
    );
  });

  it('should not PUT a duplicate valid license with different id', async function () {
    const resp = await postNegative(
      `${url}/${sampleId}`,
      { payload: validLicense },
      'PUT'
    );
    logResponse(resp);

    expect(resp.status, 'Status should be 409').to.equal(409);
    expect(resp.data.message, 'Should see correct error message').to.include(
      'UNIQUE violation detected'
    );
  });

  it('should not PATCH an existing license with invalid poayload', async function () {
    const resp = await postNegative(
      `${url}/${licenseId}`,
      { payload: inValidLicense },
      'PATCH'
    );
    logResponse(resp);

    expect(resp.status, 'Status should be 400').to.equal(400);
    expect(resp.data.message, 'Should see correct error message').to.include(
      'Unable to validate license: validation failed'
    );
  });

  it('should PATCH an existing license with valid poayload', async function () {
    const resp = await postNegative(
      `${url}/${licenseId}`,
      { payload: validLicense },
      'PATCH'
    );
    logResponse(resp);

    assertBasicRespDetails(resp);
  });

  it('should PUT a duplicate valid license with same primary key id', async function () {
    const resp = await postNegative(
      `${url}/${licenseId}`,
      { payload: validLicense },
      'PUT'
    );
    logResponse(resp);

    assertBasicRespDetails(resp);
  });

  it('should GET the license by id', async function () {
    const resp = await axios(`${url}/${licenseId}`);
    logResponse(resp);

    assertBasicRespDetails(resp);
  });

  it('should GET the license report', async function () {
    const reportUrl = `${url.split('licenses')[0]}license/report`;
    const resp = await axios(reportUrl);
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.license.license_key, 'Should see correct license key').to.eq(
      licenseKey
    );
    expect(resp.data.plugins_count, 'Should see plugins_count in response').to
      .exist;
    expect(resp.data.deployment_info, 'Should see deployment_info in response').to
      .exist;
    expect(resp.data.timestamp, 'Should see timestamp in response').to
      .exist;
    expect(resp.data.checksum, 'Should see checksum in response').to
      .exist;
    expect(resp.data.system_info, 'Should see system_info in response').to
      .exist;
    expect(
      resp.data.counters.buckets[0].request_count,
      'Should see request_count'
    ).to.be.greaterThanOrEqual(0);
    expect(
      resp.data.counters.total_requests,
      'Should see total_requests'
    ).to.be.greaterThanOrEqual(0);

    expect(
      resp.data.workspaces_count,
      'Should see workspaces_count in response'
    ).to.eq(1);
    expect(
      resp.data.db_version,
      'Should see db_version in response'
    ).to.include('postgres');
  });

  after(async function () {
    // safegurad subsequent tests from failing due to ee license by additionally posting the ee license
    const resp = await postNegative(url, { payload: validLicense });
    logResponse(resp);
    await deleteGatewayService(serviceId);
  });
});
