import axios from 'axios';
import {
  expect,
  postNegative,
  getBasePath,
  Environment,
  logResponse,
  wait,
  isGwHybrid,
  getGatewayContainerLogs,
  findRegex,
  isGateway,
  eventually,
  getClusteringDataPlanes,
} from '@support';

//  unskip this test suite whenever the RPC changes are re-enabled
//  https://konghq.atlassian.net/browse/KAG-4407
describe.skip('RPC Log Level Tests: Data Plane', function () {
  this.timeout(40000);

  let currentLogs: any;
  let dpNodeId: string;
  let url: string;

  const isHybrid = isGwHybrid();
  const kongContainerName = 'kong-dp1';

  const logLevels = ['warn', 'info', 'error', 'crit', 'debug'];
  const wrongLogLevels = ['debian', 10, '198', 'err'];
  const originalLogLevel = 'info'

  before(async function () {
    // skip test runs for classic mode
    if (!isHybrid) {
      this.skip();
    }

    const resp = await getClusteringDataPlanes();
    dpNodeId = resp.data[0].id

    url = `${getBasePath({
      environment: isGateway() ? Environment.gateway.admin : undefined,
    })}/clustering/data-planes/${dpNodeId}/log-level`;
  });

  it('should get current dp log level', async function () {
    const resp = await axios(url);
    logResponse(resp);
  
    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.current_level, 'Should have correct current log-level').to.equal(
      originalLogLevel
    );
    expect(resp.data.original_level, 'Should have correct original log-level').to.equal(
      originalLogLevel
    );
    expect(resp.data.timeout, 'Should see timeout').to.equal(0);
  });

  wrongLogLevels.forEach((wrongLogLevel) => {
    it(`should not change dp log-level to wrong level ${wrongLogLevel}`, async function () {
      const resp = await postNegative(
        url,
        {current_level: wrongLogLevel},
        'put'
      );
      logResponse(resp);

      expect(resp.status, 'Status should be 500').to.equal(500);
      expect(resp.data.message, 'Should have correct error message for wrong log level').to.include(
        `unknown log level: ${wrongLogLevel}`
      );
    });
  });

  logLevels.forEach((logLevel) => {
    it(`should change dp node log-level to ${logLevel}`, async function () {
      let resp = await axios({
        method: 'put',
        url: url,
        data: {current_level: logLevel}
      });
      logResponse(resp);

      expect(resp.status, 'Status should be 201').to.equal(201);

      resp = await axios(url);
      logResponse(resp);

      expect(resp.status, 'Status should be 200').to.equal(200);
      expect(resp.data.original_level, 'Should have unchanged original log-level').to.equal(
        originalLogLevel
      );
      expect(resp.data.current_level, 'Should have changed current log-level').to.equal(
        logLevel
      );

      if (logLevel === originalLogLevel) {
        expect(resp.data.timeout, 'Should see correct timeout for original log-level').to.equal(0);
      } else {
        expect(resp.data.timeout, 'Should see 60s or less timeout for new log-levels').to.be.lte(
          60
        );
      }
    });
  });

  it('should change dp log-level to debug for 10 seconds', async function () {
    const resp = await postNegative(
      url,
      {current_level: 'debug', timeout: 10},
      'put'
    );
    logResponse(resp);

    expect(resp.status, 'Status should be 201').to.equal(201);
  });

  it('should get and see the updated log-level', async function () {
    const resp = await axios(url)
    logResponse(resp);

    expect(resp.data.timeout, 'Should see less than 10 seconds timeout').to.be.lte(
      10
    );
    expect(resp.data.current_level, 'Should have changed current log-level').to.equal(
      'debug'
    );
  });

  it('should see debug logs in container', async function () {
    await eventually(async () => {
      currentLogs = getGatewayContainerLogs(
        kongContainerName, 5
      );

      const isLogFound = findRegex('\\[debug\\]', currentLogs);
      expect(
        isLogFound,
        'Should see debug logs after setting log-level to debug'
      ).to.be.true;
    });
  });

  it('should not see debug logs in data plane after timeout is expired', async function () {
    // wait for 6 sseconds for timeout to expire
    // eslint-disable-next-line no-restricted-syntax
    await wait(6000)

    await eventually(async () => {
      currentLogs = getGatewayContainerLogs(
        kongContainerName, 3
      );
      const isLogFound = findRegex('\\[debug\\]', currentLogs);
      expect(
        isLogFound,
        'Should not see debug logs after setting log-level to notice'
      ).to.be.false;
    });
  });

  it('should get and see the original log-level after timeout expire', async function () {
    const resp = await axios(url)
    logResponse(resp);

    expect(resp.data.current_level, 'Should have changed to original log-level after timeout').to.equal(
      originalLogLevel
    );
    expect(resp.data.original_level, 'Should see original log-level').to.equal(
      originalLogLevel
    );
  });
});
