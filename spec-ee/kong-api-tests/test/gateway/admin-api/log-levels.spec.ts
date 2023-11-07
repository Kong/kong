import axios from 'axios';
import {
  expect,
  postNegative,
  getBasePath,
  Environment,
  logResponse,
  randomString,
  deleteGatewayService,
  deleteGatewayRoute,
  createRouteForService,
  createGatewayService,
  wait,
  isGwHybrid,
  getGatewayContainerLogs,
  findRegex,
  addRoleToUser,
  createRoleEndpointPermission,
  createRole,
  createUser,
  deleteUser,
  getNegative,
  deleteRole,
  createPlugin,
  isGwNative,
  getKongContainerName,
  retryRequest,
} from '@support';

describe('Dynamic Log Level Tests', function () {
  this.timeout(30000);
  const url = `${getBasePath({
    environment: Environment.gateway.admin,
  })}/debug`;

  const proxyUrl = getBasePath({ environment: Environment.gateway.proxy });

  let serviceId: string;
  let routeId: string;
  let currentLogs: any;
  const path = `/${randomString()}`;
  const isHybrid = isGwHybrid();
  const isKongNative = isGwNative();
  const kongContainerName = getKongContainerName();

  const logUrl = isHybrid
    ? 'cluster/control-planes-nodes/log-level'
    : 'cluster/log-level';

  const logLevels = ['warn', 'info', 'error', 'crit', 'debug'];
  const wrongLogLevels = ['debian', 10, '198', 'err'];
  const logLevelEndpoints = ['/debug/node/log-level', `/debug/${logUrl}`];

  const user = { name: randomString(), token: randomString(), id: '' };
  const userHeader = { 'kong-admin-token': user.token };
  const role = { name: randomString(), id: '' };

  before(async function () {
    const service = await createGatewayService(randomString());
    serviceId = service.id;
    const route = await createRouteForService(serviceId, [path]);
    routeId = route.id;

    // create role
    const roleReq = await createRole(role.name);
    role.id = roleReq.id;

    // create user
    const userReq = await createUser(user.name, user.token);
    user.id = userReq.id;

    // attach role to a user
    await addRoleToUser(user.name, role.name);

    // create role endpoint permission to read logLevelEndpoints[0]
    await createRoleEndpointPermission(role.id, logLevelEndpoints[0], 'read');
    // create role endpoint permission to have all permissions on logLevelEndpoints[0]/crit
    await createRoleEndpointPermission(role.id, `${logLevelEndpoints[0]}/crit`);
    // create role endpoint permission to have all permissions on logLevelEndpoints[1]/*
    await createRoleEndpointPermission(
      role.id,
      `${logLevelEndpoints[1]}/*`,
      'update'
    );

    await wait(isHybrid ? 7000 : 5000); // eslint-disable-line no-restricted-syntax
  });

  it('should get current log level', async function () {
    const resp = await axios(`${url}/node/log-level`);
    logResponse(resp);
    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.message, 'Should have correct log-level').to.equal(
      'Current log level: info'
    );
  });

  logLevels.forEach((logLevel) => {
    it(`should change node log-level to ${logLevel}`, async function () {
      let resp = await axios({
        method: 'put',
        url: `${url}/node/log-level/${logLevel}`,
      });
      logResponse(resp);

      expect(resp.status, 'Status should be 200').to.equal(200);
      expect(resp.data.message, 'Should change log level').to.equal(
        `Log level changed to ${logLevel}`
      );

      resp = await axios(`${url}/node/log-level`);
      logResponse(resp);

      expect(resp.status, 'Status should be 200').to.equal(200);
      expect(resp.data.message, 'Should have correct log-level').to.equal(
        `Current log level: ${logLevel}`
      );
    });
  });

  it('should have correct message when log-level is already set', async function () {
    const lastLogLevelInTheList = logLevels[logLevels.length - 1];
    const resp = await postNegative(
      `${url}/node/log-level/${lastLogLevelInTheList}`,
      {},
      'put'
    );
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.message, 'Should have correct error message').to.include(
      `Log level is already ${lastLogLevelInTheList}`
    );
  });

  it('should proxy traffic after log-level change', async function () {
    const resp = await axios(`${proxyUrl}${path}`);
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
  });

  it('should see debug logs in container', async function () {
    await wait(3000); // eslint-disable-line no-restricted-syntax
    const logs = getGatewayContainerLogs(kongContainerName);
    const isLogFound = findRegex('\\[debug\\]', logs);
    expect(isLogFound, 'Should see debug logs').to.be.true;
  });

  it(`should change node log-level to notice`, async function () {
    let resp = await axios({
      method: 'put',
      url: `${url}/node/log-level/notice`,
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.message, 'Should change log level').to.equal(
      `Log level changed to notice`
    );

    resp = await axios(`${url}/node/log-level`);
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.message, 'Should have correct log-level').to.equal(
      `Current log level: notice`
    );
  });

  it('should not see debug logs in container after log is set to notice', async function () {
    await wait(isKongNative ? 10000 : 8000); // eslint-disable-line no-restricted-syntax
    // read the last 2 lines of logs for package tests to avoid flakiness
    currentLogs = getGatewayContainerLogs(
      kongContainerName,
      isKongNative ? 2 : 4
    );

    const isLogFound = findRegex('\\[debug\\]', currentLogs);
    expect(
      isLogFound,
      'Should not see debug logs after setting loge-level to notice'
    ).to.be.false;
  });

  it('should see notice logs after log is set to notice', async function () {
    const isLogFound = findRegex('\\[notice\\]', currentLogs);
    expect(
      isLogFound,
      'Should see notice logs after setting loge-level to notice'
    ).to.be.true;
  });

  wrongLogLevels.forEach((wrongLogLevel) => {
    it(`should not change log-level to wrong level ${wrongLogLevel}`, async function () {
      const resp = await postNegative(
        `${url}/node/log-level/${wrongLogLevel}`,
        {},
        'put'
      );
      logResponse(resp);

      expect(resp.status, 'Status should be 400').to.equal(400);
      expect(resp.data.message, 'Should have correct message').to.include(
        `Unknown log level: ${wrongLogLevel}`
      );
    });
  });

  it('should change log-level for all cluster CP nodes', async function () {
    const logLevel = 'error';
    const resp = await postNegative(`${url}/${logUrl}/${logLevel}`, {}, 'put');
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.message, 'Should change log level').to.equal(
      `Log level changed to ${logLevel}`
    );
  });

  it('should have correct message when log-level is already set for cluster CP nodes', async function () {
    const logLevel = 'error';
    const resp = await postNegative(`${url}/${logUrl}/${logLevel}`, {}, 'put');
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.message, 'Should have correct error message').to.include(
      `Log level is already ${logLevel}`
    );
  });

  it('should have correct message for setting node log-level when log-level is already set for Cluster', async function () {
    const logLevel = 'error';
    const resp = await postNegative(
      `${url}/node/log-level/${logLevel}`,
      {},
      'put'
    );
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.message, 'Should have correct message').to.include(
      `Log level is already ${logLevel}`
    );
  });

  it('should get log-level after changing it for all cluster CP nodes', async function () {
    const logLevel = 'error';
    const resp = await axios(`${url}/node/log-level`);
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.message, 'Should have correct log-level').to.equal(
      `Current log level: ${logLevel}`
    );
  });

  it(`should change node log-level to alert for 10 seconds`, async function () {
    // creating datadog plugin with wrong config to simulate error logs
    await createPlugin({
      name: 'datadog',
      service: {
        id: serviceId,
      },
      route: {
        id: routeId,
      },
    });

    let resp = await axios({
      method: 'put',
      url: `${url}/${logUrl}/alert?timeout=10`,
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.message, 'Should change log level').to.equal(
      `Log level changed to alert`
    );

    await wait(2000); // eslint-disable-line no-restricted-syntax

    resp = await axios(`${url}/node/log-level`);
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.message, 'Should have correct log-level').to.equal(
      `Current log level: alert`
    );
  });

  it('should not see error logs after log-level is set to alert', async function () {
    // sending request to simulate DD error in the logs
    const resp = await getNegative(`${proxyUrl}${path}`);
    logResponse(resp);

    const logs = getGatewayContainerLogs(kongContainerName);

    const isLogFound = findRegex('\\[error\\]', logs);
    const isInfoLogFound = findRegex('\\[info\\]', logs);
    const isDebugLogFound = findRegex('\\[debug\\]', logs);

    [isLogFound, isInfoLogFound, isDebugLogFound].forEach((logLevel) => {
      expect(
        logLevel,
        `Should not see ${logLevel} logs after setting loge-level to alert`
      ).to.be.false;
    });
  });

  it('should see log level change back to info after 10 seconds', async function () {
    // checking the the log level is info after 10 seconds alert
    const req = () => axios(`${url}/node/log-level`);

    const assertions = (resp) => {
      expect(resp.status, 'Status should be 200').to.equal(200);
      expect(resp.data.message, 'Should have correct log-level').to.equal(
        `Current log level: info`
      );
    };

    /*
      * Adding 5 seconds to the timeout to avoid flakiness
      * as the behavior of the timeout of the log_level is not very exact.
      *
      * For example, if we set the timeout to 10 seconds,
      * the log level will be changed back to info after 10 seconds,
      * but the request to get the log level might be sent at 10.00001 seconds,
      * the internal mechanism of the timeout of the log_level
      * can't be that exact, so we might see the log level is not expected.
    */
    await retryRequest(req, assertions, 12000);
  });

  it('should see error logs as alert level was changed to info after 10 seconds', async function () {
    // sending request to simulate DD error in the logs
    const resp = await getNegative(`${proxyUrl}${path}`);
    logResponse(resp);

    await wait(isHybrid ? 7000 : 2000); // eslint-disable-line no-restricted-syntax
    const logs = getGatewayContainerLogs(
      isHybrid ? 'kong-dp1' : kongContainerName
    );

    const isLogFound = findRegex('\\[error\\]', logs);
    expect(isLogFound, 'Should see error logs').to.be.true;
  });

  it('should change log-level back to info with timeout of 0 seconds', async function () {
    const resp = await axios({
      method: 'put',
      url: `${url}/node/log-level/notice?timeout=0`,
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);

    const req = () => axios({
      method: 'get',
      url: `${url}/node/log-level`,
    });

    const assertions = (resp) => {
      expect(resp.status, 'Status should be 200').to.equal(200);
      expect(resp.data.message, 'Should have correct log-level').to.equal(
        `Current log level: info`
      );
    };

    await retryRequest(req, assertions, 10000);
  });

  describe('Dynamic Log Level RBAC Permissions for a User', function () {
    it('should GET /node/log-level with permission', async function () {
      const resp = await axios({
        url: `${url}/node/log-level`,
        headers: userHeader,
      });
      logResponse(resp);

      expect(resp.status, 'Status should be 200').to.equal(200);
      expect(resp.data.message, 'Should have correct log-level').to.equal(
        `Current log level: info`
      );
    });

    it('should not GET /node/log-level with wrong token', async function () {
      const resp = await getNegative(`${url}/node/log-level`, {
        'kong-admin-token': 'wrong',
      });
      logResponse(resp);

      expect(resp.status, 'Status should be 401').to.equal(401);
    });

    it(`should PUT /node/log-level/crit with permission`, async function () {
      const logLevel = 'crit';

      let resp = await axios({
        method: 'put',
        url: `${url}/node/log-level/${logLevel}`,
        headers: userHeader,
      });
      logResponse(resp);

      expect(resp.status, 'Status should be 200').to.equal(200);
      expect(resp.data.message, 'Should change log level').to.equal(
        `Log level changed to ${logLevel}`
      );

      resp = await axios(`${url}/node/log-level`);
      logResponse(resp);

      expect(resp.status, 'Status should be 200').to.equal(200);
      expect(resp.data.message, 'Should have correct log-level').to.equal(
        `Current log level: ${logLevel}`
      );
    });

    it(`should not PUT /node/log-level/alert with no permission`, async function () {
      const logLevel = 'alert';

      const resp = await postNegative(
        `${url}/node/log-level/${logLevel}`,
        {},
        'put',
        userHeader
      );
      logResponse(resp);

      expect(resp.status, 'Status should be 403').to.equal(403);
    });

    it(`should PUT ${logUrl}/notice with ${logUrl}/* update permission`, async function () {
      const logLevel = 'notice';

      let resp = await axios({
        method: 'put',
        url: `${url}/${logUrl}/${logLevel}`,
        headers: userHeader,
      });
      logResponse(resp);

      expect(resp.status, 'Status should be 200').to.equal(200);
      expect(resp.data.message, 'Should change log level').to.equal(
        `Log level changed to ${logLevel}`
      );

      resp = await axios(`${url}/node/log-level`);
      logResponse(resp);

      expect(resp.status, 'Status should be 200').to.equal(200);
      expect(resp.data.message, 'Should have correct log-level').to.equal(
        `Current log level: ${logLevel}`
      );
    });

    it(`should PUT ${logUrl}/warn with ${logUrl}/* update permission`, async function () {
      const logLevel = 'warn';

      let resp = await axios({
        method: 'put',
        url: `${url}/${logUrl}/${logLevel}`,
        headers: userHeader,
      });
      logResponse(resp);

      expect(resp.status, 'Status should be 200').to.equal(200);
      expect(resp.data.message, 'Should change log level').to.equal(
        `Log level changed to ${logLevel}`
      );

      resp = await axios(`${url}/node/log-level`);
      logResponse(resp);

      expect(resp.status, 'Status should be 200').to.equal(200);
      expect(resp.data.message, 'Should have correct log-level').to.equal(
        `Current log level: ${logLevel}`
      );
    });
  });

  after(async function () {
    await deleteGatewayRoute(routeId);
    await deleteGatewayService(serviceId);
    await deleteUser(user.id);
    await deleteRole(role.id);

    // set log-level back to info
    const resp = await postNegative(`${url}/node/log-level/info`, {}, 'put');
    logResponse(resp);
  });
});
