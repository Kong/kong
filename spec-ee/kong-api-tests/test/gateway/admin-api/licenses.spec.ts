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
  isGateway,
  deleteUser,
  deletePlugin,
  waitForConfigRebuild,
  createConsumer,
  deleteConsumer,
  eventually,
} from '@support';

describe('Gateway /licenses API tests', function () {
  /**
   * This test requires EE license to be posted via API
  */

  const sampleId = '7ad8a306-cb1f-4b61-8b51-47c3604c3748';
  const licenseKey = 'ASDASDASDASDASDASDASDASDASD_a1VASASD';
  const validLicense = authDetails.license.valid;
  const inValidLicense = authDetails.license.invalid;
  const expiredLicense = authDetails.license.expired;
  const validLicenseAws = '{vault://aws/gateway-secret-test/ee_license}';
  const jwtPluginPayload = {
    name: 'jwt-signer',
    config: {}
  };
  const rbacUser = {
    name: 'user1',
    user_token: 'rbac1'
  }

  const url = `${getBasePath({
    environment: isGateway() ? Environment.gateway.admin : undefined,
  })}/licenses`;

  const pluginsUrl = `${getBasePath({
    environment: isGateway() ? Environment.gateway.admin : undefined,
  })}/plugins`;

  const rbacUsersUrl = `${getBasePath({
    environment: isGateway() ? Environment.gateway.admin : undefined,
  })}/rbac/users`;
  const reportUrl = `${url.split('licenses')[0]}license/report`;

  let licenseId: string;
  let expiredLicenseId: string;
  let licenseValidId: string;
  let serviceId: string;
  let expiredLicenseServiceId: string;
  let eeJWTPluginId: string;
  let eeKeyAuthEncPluginId: string;
  let basePayload: any;
  let rbacUserId: string;
  let consumerId: string;

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

    const consumer = await createConsumer();
    consumerId = consumer.id
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
  });

  it('should deploy an exipred license successfully', async function () {
    const resp = await postNegative(url, { payload: expiredLicense });
    logResponse(resp);

    expect(resp.status, 'Status should be 201').to.equal(201);
    assertBasicRespDetails(resp);

    expiredLicenseId = resp.data.id;
    await waitForConfigRebuild();
  });

  it('should get license report endpoint with expired license', async function () {
    const resp = await axios(`${url.split('licenses')[0]}license/report`);
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
  });

  it('should create a service successfully with expired license', async function () {
    const service = await createGatewayService(randomString());
    expiredLicenseServiceId = service.id;
  });

  it('should NOT be able to create a RBAC user with expired license', async function () {
    const resp = await postNegative(`${rbacUsersUrl}`, rbacUser);
    logResponse(resp);

    expect(resp.status, 'Status should be 403').to.equal(403);
    expect(resp.data.message, 'Should have correct message').to.contain(
      'Enterprise license missing or expired'
    );
  });

  it('should NOT be able to create jwt-signer plugin with expired license', async function () {
    const resp = await postNegative(`${pluginsUrl}`, jwtPluginPayload);
    logResponse(resp);
    expect(resp.status, 'Status should be 400').to.equal(400);
    expect(resp.data.message, 'Should have correct message').to.contain(
      'enterprise only plugin'
    );
  });

  it('should delete expired license successfully', async function () {
    const resp = await axios({
      method: 'delete',
      url: `${url}/${expiredLicenseId}`,
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 204').to.equal(204);
    await waitForConfigRebuild();
  });

  it('should POST a valid license after deleting expired license', async function () {
    const resp = await postNegative(url, { payload: validLicense });
    logResponse(resp);

    expect(resp.status, 'Status should be 201').equal(201);
    assertBasicRespDetails(resp);

    licenseValidId = resp.data.id;
    await waitForConfigRebuild();
  });

  it('should see correct entity counts in license/report', async function () {
    await eventually(async () => {
      const resp = await axios(reportUrl);

      expect(resp.status, 'Status should be 200').to.equal(200);
      expect(resp.data.workspaces_count, 'Should see workspaces_count in response').to.eq(1);
      expect(resp.data.services_count, 'Should see services_count in response').to.eq(2);
      expect(resp.data.consumers_count, 'Should see consumers_count in response').to.eq(1);
      expect(resp.data.rbac_users, 'Should see rbac_users in response').to.eq(1);
      expect(resp.data.plugins_count.tiers.enterprise, 'Should see no plugins').to.be.empty;
    });
  });

  it('should create a RBAC user with valid license successfully', async function () {
    const resp = await postNegative(`${rbacUsersUrl}`, rbacUser);
    logResponse(resp);

    expect(resp.status, 'Status should be 201').to.equal(201);
    expect(resp.data.id, 'ID is undefined').to.exist;
    rbacUserId = resp.data.id;
  });

  it('should create jwt-signer plugin with valid license successfully', async function () {
    const resp = await postNegative(`${pluginsUrl}`, jwtPluginPayload);
    logResponse(resp);

    expect(resp.status, 'Status should be 201').to.equal(201);

    eeJWTPluginId = resp.data.id;
  });

  it('should delete valid license successfully', async function () {
    const resp = await axios({
      method: 'delete',
      url: `${url}/${licenseValidId}`,
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 204').to.equal(204);
    await waitForConfigRebuild();
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


  it('should not enable key-auth-enc ee plugin without license', async function () {
    const pluginPayload = {
      ...basePayload,
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


  it('should POST a valid license', async function () {
    const resp = await postNegative(url, { payload: validLicense });
    logResponse(resp);

    licenseId = resp.data.id;
    assertBasicRespDetails(resp);
    await waitForConfigRebuild();
  });


  it('should enable key-auth-enc ee plugin with license', async function () {
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
    eeKeyAuthEncPluginId = resp.data.id;
  });


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

  it('should GET the license/report', async function () {
    const resp = await axios(reportUrl);
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.license.license_key, 'Should see correct license key').to.eq(
      licenseKey
    );
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
    expect(resp.data.services_count, 'Should see services_count in response').to.eq(2);
    expect(resp.data.consumers_count, 'Should see consumers_count in response').to.eq(1);
    expect(resp.data.rbac_users, 'Should see rbac_users in response').to.eq(2);

    expect(resp.data.plugins_count.tiers.enterprise, 'Should see existing plugins count').to.deep.equal({
      'key-auth-enc': 1,
      'jwt-signer': 1
    });
  });

  it('should see updated license/report after entity numbers change', async function () {
    // remove some resources to change the entity numbers in license report
    await deleteGatewayService(expiredLicenseServiceId);
    await deletePlugin(eeJWTPluginId);
    await deleteUser(rbacUserId);
    await deleteConsumer(consumerId);

    await eventually(async () => {
      const resp = await axios(reportUrl);

      expect(resp.status, 'Status should be 200').to.equal(200);
      expect(resp.data.workspaces_count, 'Should see workspaces_count in response').to.eq(1);
      expect(resp.data.services_count, 'Should see services_count in response').to.eq(1);
      expect(resp.data.consumers_count, 'Should see consumers_count if counter is 0').to.eq(0);
      expect(resp.data.rbac_users, 'Should see rbac_users in response').to.eq(1);
      expect(resp.data.plugins_count.tiers.enterprise, 'should see plugins').to.deep.equal({'key-auth-enc': 1});
    });
  });

  // unskip when https://konghq.atlassian.net/browse/KAG-4341 is fixed
  it.skip('should delete the license and post a new one from aws vault', async function () {
    let resp = await axios({
      method: 'delete',
      url: `${url}/${licenseId}`,
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 204').to.equal(204);

    resp = await postNegative(url, { payload: validLicenseAws });
    logResponse(resp);
    expect(resp.data.message, 'Should not see license decode error').to.not.include('Unable to validate license: could not decode license json')

    licenseId = resp.data.id;
    assertBasicRespDetails(resp);
  });

  after(async function () {
    // safegurad subsequent tests from failing due to ee license by additionally posting the ee license
    const resp = await postNegative(url, { payload: validLicense });
    logResponse(resp);

    await deleteGatewayService(serviceId);
    await deletePlugin(eeKeyAuthEncPluginId);
  });
});
