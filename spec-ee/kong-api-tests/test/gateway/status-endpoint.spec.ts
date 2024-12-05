// This test requires `make generate STATUS_LISTEN=true HTTP2=true  GW_MODE=hybrid` to pass

import {
  expect,
  isGwHybrid,
  isLocalDatabase,
  expectStatusReadyEndpointOk,
  expectStatusReadyEndpoint503,
  waitForTargetStatus,
  runDockerContainerCommand,
  eventually,
  isGwNative
} from '@support';

const isHybrid = isGwHybrid();
const isLocalDb = isLocalDatabase();
const databaseContainerName = 'kong-ee-database';
const dpPortNumber = 8101;

const isPackageTest = isGwNative();

// skip tests for package mode due to failures in the last test
// needs to be investigated why the kong-ee-database throws cert access denied error and doesn't start
(isPackageTest ? describe.skip : describe)('@oss: /status Endpoint tests', function () {
  before(async function () {
    if (!isLocalDb) {
      this.skip();
    }
  });

  it('should return 200 OK for CP status when Kong is loaded and ready', async function () {
    await expectStatusReadyEndpointOk();
  });

  it('should return 503 for CP status when connection to database is lost', async function () {
    // Sever connection between Kong and database
    await runDockerContainerCommand(databaseContainerName, 'stop');
    await runDockerContainerCommand(databaseContainerName, 'container wait');

    await waitForTargetStatus(503, 10000);
    await expectStatusReadyEndpoint503('failed to connect to database');
  });

  if (isHybrid) {
    it('should return 200 in DP status when connection to database is severed', async function () {
      await waitForTargetStatus(200, 10000, dpPortNumber);
    });
  }

  it('should return 200 OK for CP status when connection to database is restored', async function () {
    // Restore connection between Kong and database
    await runDockerContainerCommand(databaseContainerName, 'start');
    await eventually(async () => {
      const containerStatus = JSON.parse(await runDockerContainerCommand(databaseContainerName, "inspect"))
      expect(typeof containerStatus).to.equal("object")
      expect(typeof containerStatus[0]).to.equal("object")
      expect(containerStatus[0]?.State?.Health?.Status).to.equal("healthy")
    }, 60000, 1000)

    await waitForTargetStatus(200, 10000);
  });
});
