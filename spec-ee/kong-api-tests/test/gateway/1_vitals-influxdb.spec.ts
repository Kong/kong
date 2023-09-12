import {
  createGatewayService,
  createInfluxDBConnection,
  createRouteForService,
  deleteAllDataFromKongDatastoreCache,
  deleteAllDataFromKongRequest,
  deleteGatewayRoute,
  deleteGatewayService,
  Environment,
  executeCustomQuery,
  expect,
  getAllEntriesFromKongDatastoreCache,
  getAllEntriesFromKongRequest,
  getBasePath,
  getNegative,
  getWorkspaces,
  isGwHybrid,
  retryRequest,
  isLocalDatabase,
  wait,
} from '@support';
import axios from 'axios';

describe.skip('Vitals with InfluxDB Tests', function () {
  this.timeout(50000);
  const todaysDate = new Date().toISOString().split('T')[0];

  const proxyUrl = getBasePath({ environment: Environment.gateway.proxy });
  // isHybrid is being used across the test to control test flow for hybrid mode run
  const isHybrid = isGwHybrid();
  const isLocalDb = isLocalDatabase();
  const classicWait = 5000;
  const longWait = 7000;

  let serviceId: string;
  let routeId: string;
  let serviceId2: string;
  let routeId2: string;
  let defaultWorkspaceId: string;
  let hostname: string;
  let kongLatency: number;

  before(async function () {
    // skip classic mode test run due to https://konghq.atlassian.net/browse/KAG-363
    if (!isHybrid) {
      this.skip();
    }

    // connect to influxdb
    createInfluxDBConnection();
    await wait(longWait);
    await deleteAllDataFromKongRequest();
    await wait(classicWait);
    await deleteAllDataFromKongDatastoreCache();
    await wait(longWait);

    const service = await createGatewayService('VitalsService', {
      url: 'http://httpbin/status',
    });
    serviceId = service.id;

    const route = await createRouteForService(serviceId, ['/']);
    routeId = route.id;

    const workspaces: any = await getWorkspaces();

    for (const workspace of workspaces.data) {
      if (workspace.name === 'default') {
        defaultWorkspaceId = workspace.id;
        break;
      } else {
        console.log("Couldn't find default workspace id");
      }
    }

    await wait(isLocalDb ? classicWait : longWait);
  });

  const assertKongRequestDetails = (response: any) => {
    expect(response.time, 'Should have time object in kong_request').to.not.be
      .null;
    expect(response.time._nanoISO).to.contain(todaysDate);
    expect(response.route, 'Should have correct route id').to.eq(routeId);
    expect(response.service, 'Should have correct service id').to.eq(serviceId);
    expect(response.hostname, 'Should have correct hostname').to.eq(hostname);
    expect(response.wid, 'Should have "wid" field in kong_request').to.be
      .string;
    expect(response.workspace, 'Should have default workspace id').to.eq(
      defaultWorkspaceId
    );

    expect(response.kong_latency, 'Should have integer kong_latency').to.be.a(
      'number'
    );
    expect(response.proxy_latency, 'Should have integer proxy_latency').to.be.a(
      'number'
    );
    expect(
      response.request_latency,
      'Should have integer request_latency'
    ).to.be.a('number');
  };

  it('should add entry in influxdb kong_request after request', async function () {
    await wait(isHybrid ? longWait : classicWait);
    await axios(`${proxyUrl}/200`);
    // wait for request metric to be added to influxdb
    await wait(isHybrid ? longWait : 0);

    const requestEntries: any = await getAllEntriesFromKongRequest(1);

    expect(
      requestEntries.length,
      'Should have 1 entry in kong_request'
    ).to.equal(1);
    expect(requestEntries[0].kong_latency, 'Should have kong_latency').to.be.a(
      'number'
    );

    hostname = requestEntries[0].hostname;
    kongLatency = requestEntries[0].kong_latency;
  });

  it('should add entry in influxdb kong_datastore_cache after request', async function () {
    const cacheEntries: any = await getAllEntriesFromKongDatastoreCache();
    expect(
      cacheEntries.length,
      'Should have 1 entry in kong_datastore_cache'
    ).to.equal(1);
  });

  it('should see Tag keys', async function () {
    const tagKeys: any = await executeCustomQuery('show TAG keys');

    expect(
      tagKeys.groupRows[0].name,
      'should see kong_datastore_cache tag'
    ).to.equal('kong_datastore_cache');
    expect(tagKeys.groupRows[1].name, 'should see kong_request tag').to.equal(
      'kong_request'
    );
    expect(tagKeys[0], 'Should see tagKey hostname ').to.haveOwnProperty(
      'tagKey',
      'hostname'
    );
    expect(tagKeys[1], 'Should see tagKey wid').to.haveOwnProperty(
      'tagKey',
      'wid'
    );
  });

  it('should see Field keys', async function () {
    const fieldKeys: any = await executeCustomQuery('show FIELD keys');

    expect(
      fieldKeys.groupRows[0].name,
      'should see kong_datastore_cache field'
    ).to.equal('kong_datastore_cache');
    expect(
      fieldKeys.groupRows[1].name,
      'should see kong_request field'
    ).to.equal('kong_request');
    expect(fieldKeys[0], 'Should see fieldKey hits').to.haveOwnProperty(
      'fieldKey',
      'hits'
    );
    expect(fieldKeys[0], 'Should see fieldKey hits type').to.haveOwnProperty(
      'fieldType',
      'integer'
    );
  });

  it('should have correct data in kong_request measurement', async function () {
    const requestEntries: any = await getAllEntriesFromKongRequest();

    assertKongRequestDetails(requestEntries[0]);
    expect(requestEntries[0].status, 'Should have status 200').to.eq(200);
  });

  it('should have correct data in kong_datastore_cache measurement', async function () {
    const cacheEntries: any = await getAllEntriesFromKongDatastoreCache();

    expect(cacheEntries[0].time, 'Should have time object in kong_request').to
      .not.be.null;
    expect(cacheEntries[0].hostname, 'Should have correct hostname').to.eq(
      hostname
    );

    expect(cacheEntries[0].misses, 'Should have "misses" field').to.be.a(
      'number'
    );
    expect(cacheEntries[0].hits, 'Should have "hits" field').to.be.a('number');
    expect(
      cacheEntries[0].wid,
      'Should have "wid" field in kong_datastore_cache'
    ).be.string;
  });

  it('should add multiple entries in influxdb kong_request after multiple requests', async function () {
    await getNegative(`${proxyUrl}/404`);
    await getNegative(`${proxyUrl}/500`);
    await getNegative(`${proxyUrl}/200`);

    const requestEntries: any = await getAllEntriesFromKongRequest(4);

    expect(
      requestEntries.length,
      'Should have 4 entries in kong_request'
    ).to.equal(4);

    requestEntries.forEach((entry: any, i: number) => {
      assertKongRequestDetails(entry);

      if (i === 0 || i === 3) {
        expect(entry.status, 'Should have status 200').to.eq(200);
        if (i === 3) {
          expect(
            entry.kong_latency,
            'Should have reduced kong_latency for a repeated request'
          ).to.be.lte(kongLatency);
        }
      } else if (i === 1) {
        expect(entry.status, 'Should have status 404').to.eq(404);
      } else if (i === 2) {
        expect(entry.status, 'Should have status 500').to.eq(500);
      }
    });
  });

  it('should see an entry in kong_request for a request with a new route and service', async function () {
    const service = await createGatewayService('VitalsService2', {
      url: 'http://httpbin/anything',
    });
    serviceId2 = service.id;

    await wait(isHybrid ? longWait : classicWait);

    const route = await createRouteForService(serviceId2, ['/influxdb']);
    routeId2 = route.id;

    await wait(isHybrid ? longWait : classicWait);
    await axios(`${proxyUrl}/influxdb`);

    const requestEntries: any = await getAllEntriesFromKongRequest(5);

    expect(requestEntries[4].route, 'Should have correct route id').to.eq(
      routeId2
    );
    expect(requestEntries[4].service, 'Should have correct service id').to.eq(
      serviceId2
    );
    expect(requestEntries[4].hostname, 'Should have correct hostname').to.eq(
      hostname
    );
    expect(requestEntries[4].status, 'Should have status 2').to.eq(200);
    expect(requestEntries[4].time._nanoISO).to.contain(todaysDate);
  });

  it('should see an entry in kong_datastore_cache for a request with a new route and service', async function () {
    const cacheEntries: any = await getAllEntriesFromKongDatastoreCache();

    expect(
      cacheEntries.length,
      'Should have 2 entries in kong_datastore_cache'
    ).to.be.greaterThanOrEqual(2);
  });

  after(async function () {
    await deleteGatewayRoute(routeId);
    await deleteGatewayService(serviceId);
    await deleteGatewayRoute(routeId2);
    await deleteGatewayService(serviceId2);
  });
});
