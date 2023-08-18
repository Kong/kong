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
} from '@support';

const isHybrid = isGwHybrid();
const isLocalDb = isLocalDatabase();
const databaseContainerName = 'kong-ee-database';
const dpPortNumber = 8101;

describe('/status Endpoint tests', function () {
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

    expect(await waitForTargetStatus(503, 10000)).to.equal(true);
    await expectStatusReadyEndpoint503('failed to connect to database');
  });

  if (isHybrid) {
    it('should return 200 in DP status when connection to database is severed', async function () {
      expect(await waitForTargetStatus(200, 10000, dpPortNumber)).to.equal(true);
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

    expect(await waitForTargetStatus(200, 10000)).to.equal(true);
  });
});
