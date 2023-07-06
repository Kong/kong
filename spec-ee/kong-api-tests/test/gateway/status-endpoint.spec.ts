import {
  expect,
  isGwHybrid,
  isLocalDatabase,
  expectStatusReadyEndpointOk,
  expectStatusReadyEndpoint503,
  waitForTargetStatus,
  runDockerContainerCommand,
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
    runDockerContainerCommand(databaseContainerName, 'stop');

    // wait up to 10 seconds, ensure 503 is returned in that time
    expect(await waitForTargetStatus(503, 10000)).to.equal(true);
    expectStatusReadyEndpoint503('failed to connect to database');
  });

  if (isHybrid) {
    it('should return 200 in DP status when connection to database is severed', async function () {
      // wait up to 10 seconds, ensure 200 is returned in that time
      expect(await waitForTargetStatus(200, 10000, dpPortNumber)).to.equal(true);
    });
  }

  it('should return 200 OK for CP status when connection to database is restored', async function () {
    // restore connection between Kong and database
    runDockerContainerCommand(databaseContainerName, 'start');

    // wait up to 10 seconds, ensure 200 is returned in that time
    expect(await waitForTargetStatus(200, 15000)).to.equal(true);
  });
});
