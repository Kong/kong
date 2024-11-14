import {
  client,
  createGatewayService,
  createRouteForService,
  Environment,
  expect,
  getGatewayContainerLogs,
  getKongContainerName,
  getBasePath,
  checkRedisDBSize,
  waitForRedisDBSize,
  checkRedisEntries,
  checkRedisConnectErrLog,
  isGwHybrid,
  logResponse,
  resetRedisDB,
  randomString,
  isGateway,
  wait,
  waitForConfigRebuild,
  eventually,
  findRegex,
  clearAllKongResources,
  sendRequestInWindow,
  verifyRateLimitingEffect
} from '@support';
import axios from 'axios';

//common constant shared in different contexts
const redisUsername = 'redisuser';
const redisPassword = 'redispassword';
const isHybrid = isGwHybrid();
const pluginUrl = `${getBasePath({
  environment: isGateway() ? Environment.gateway.admin : undefined,
})}/plugins`;
const proxyUrl = getBasePath({
  environment: isGateway() ? Environment.gateway.proxy : undefined,
});
//common constant shared in different contexts
const kongContainerName = isHybrid ? 'kong-dp1' : getKongContainerName();


describe('Kong Plugins: RLA namespace Test', function () {
  before(async function () {
    // connect to redis
    await client.connect();
  });
  context('when multiple RLAs config in same namespace but with different sync counter config', function () {

    const namespaceConfigErr = 'namespaceConfigErr';

    const pluginConfig = {
      limit: [1],
      window_size: [60],
      window_type: 'fixed',
      sync_rate: 0,
      strategy: 'redis',
      namespace: namespaceConfigErr,
      redis: {
        host: 'redis',
        port: 6379,
        username: redisUsername,
        password: redisPassword,
      },
    };
    const deepUpdatedPluginConfig = JSON.parse(JSON.stringify(pluginConfig));
    let serviceId: string;

    before(async function () {
      const service = await createGatewayService('RlaNameSpaceService');
      serviceId = service.id;
    });

    it('should create two RLA with same namespace but have different sync rate', async function () {
      const pluginConfig1Payload = {
        name: 'rate-limiting-advanced',
        service: {
          id: serviceId,
        },
        config: pluginConfig,
      };
      const resp1: any = await axios({ method: 'post', url: pluginUrl, data: pluginConfig1Payload, });
      logResponse(resp1);
      expect(resp1.status, 'Status should be 201').to.equal(201);

      deepUpdatedPluginConfig.sync_rate = 1;
      const pluginConfig2Payload = {
        name: 'rate-limiting-advanced',
        config: deepUpdatedPluginConfig,
      };
      const resp2: any = await axios({ method: 'post', url: pluginUrl, data: pluginConfig2Payload, });
      logResponse(resp2);
      expect(resp2.status, 'Status should be 201').to.equal(201);
    });

    it('should see error logs warning multiple RLA have different counter syncing configurations', async function () {
      await eventually(async () => {
        const currentLogs = getGatewayContainerLogs(kongContainerName, 20);

        const isLogFound = findRegex('have different counter syncing configurations. Please correct them to use the same configuration.', currentLogs);
        expect(
          isLogFound,
          'Should see different counter syncing warning log'
        ).to.be.true;
      });
    });

    after(async function () {
      await clearAllKongResources();
    });
  });

  context('When RLA Plugin print redis connection error log with lazy timer', function () {

    const namespaceInitial = 'namespaceInitial';
    const namespaceUpdate = 'namespaceUpdate';
    const path = `/${randomString()}`;
    const urlProxy = `${proxyUrl}${path}`;

    let serviceId: string;
    let routeId: string;
    let basePayload: any;
    let basePayloadUpdate: any;
    let pluginId: string;

    before(async function () {
      const service = await createGatewayService('RlaLazyTimerService');
      serviceId = service.id;
      const route = await createRouteForService(serviceId, [path]);
      routeId = route.id;

      basePayload = {
        name: 'rate-limiting-advanced',
        service: {
          id: serviceId,
        },
        route: {
          id: routeId,
        },
        config: {
          limit: [1],
          window_size: [30],
          window_type: 'fixed',
          sync_rate: 2,
          strategy: 'redis',
          namespace: namespaceInitial,
          redis: {
            host: 'redis',
            port: 6888, //Config Wrong Redis Port for error logs 
            username: redisUsername,
            password: redisPassword,
          },
        }
      };

      basePayloadUpdate = JSON.parse(JSON.stringify(basePayload));
    });

    it('should create RLA plugin with wrong Redis port in namespaceInitial', async function () {
      const resp = await axios({
        method: 'POST',
        url: pluginUrl,
        data: basePayload,
      });
      logResponse(resp);

      expect(resp.status, 'Status should be 201').to.equal(201);
      pluginId = resp.data.id;
      await waitForConfigRebuild();
    });

    it('should not see Redis connection error without proxy request', async function () {
      await checkRedisConnectErrLog('namespaceInitial', kongContainerName, false);
    });

    it('should send proxy request to trigger RLA plugin Redis connection error log', async function () {
      const resp = await axios({ method: 'GET', url: urlProxy });
      logResponse(resp);
      expect(resp.status, 'Status should be 200').to.equal(200);
    });

    it('should see Redis connection error after proxy request', async function () {
      await checkRedisConnectErrLog('namespaceInitial', kongContainerName, true);
    });

    it('should change RLA plugin config to namespaceUpdate', async function () {
      basePayloadUpdate.config.namespace = namespaceUpdate;
      const resp = await axios({
        method: 'PATCH',
        url: `${pluginUrl}/${pluginId}`,
        data: basePayloadUpdate,
      });
      logResponse(resp);

      expect(resp.status, 'Status should be 201').to.equal(200);
      await waitForConfigRebuild();
    });

    it('should not see Redis connection error after namespace change but before proxy request', async function () {
      await checkRedisConnectErrLog('namespaceUpdate', kongContainerName, false);
    });

    it('should send proxy request to trigger RLA plugin new namespace Redis connection error log', async function () {
      const resp = await axios({ method: 'GET', url: urlProxy });
      logResponse(resp);
      expect(resp.status, 'Status should be 200').to.equal(200);
      await checkRedisConnectErrLog('namespaceUpdate', kongContainerName, true);
    });

    after(async function () {
      await clearAllKongResources();
    });

  });

  context('when RLA Plugins sync counter to redis storage', function () {
    const path = `/${randomString()}`;
    const urlProxy = `${proxyUrl}${path}`;
    const limitHeader = 'X-Limit-Hit';
    const limitHeaderValue = 'redisSync';
    const limitHeaderValueUpdate = 'newHeaderUpdate';
    const headers = { [limitHeader]: limitHeaderValue };
    const namespaceValue = 'namespaceSync';
    const namespaceValueUpdate = 'namespacePeriodic';
    const rateLimit = 1;
    const windowLength = 20;

    let serviceId: string;
    let routeId: string;
    let basePayload: any;
    let pluginId: string;

    before(async function () {
      const service = await createGatewayService('RlaRedisSyncService');
      serviceId = service.id;
      const route = await createRouteForService(serviceId, [path]);
      routeId = route.id;

      basePayload = {
        name: 'rate-limiting-advanced',
        service: {
          id: serviceId,
        },
        route: {
          id: routeId,
        },
        config: {
          limit: [rateLimit],
          window_size: [windowLength],
          window_type: 'fixed',
          identifier: 'header',
          header_name: limitHeader,
          sync_rate: -1,
          strategy: 'redis',
          namespace: namespaceValue,
          redis: {
            host: 'redis',
            port: 6379,
            username: redisUsername,
            password: redisPassword,
          },
        }
      };
    });

    it('should create RLA plugin with Redis storage with negative sync rate', async function () {
      const resp = await axios({
        method: 'POST',
        url: pluginUrl,
        data: basePayload,
      });
      logResponse(resp);

      expect(resp.status, 'Status should be 201').to.equal(201);
      pluginId = resp.data.id;
      await waitForConfigRebuild();
    });

    it('should limit proxy request with matched Header successfully', async function () {
      await resetRedisDB();
      await wait(isHybrid ? 8000 : 7000); // eslint-disable-line no-restricted-syntax
      await verifyRateLimitingEffect({ rateLimit, url: urlProxy, headers });
    });

    it('should not sync counter to Redis storage with negative sync rate', async function () {
      await checkRedisDBSize(0);

      await resetRedisDB();
    });

    it('should change RLA plugin sync rate to 0 to enable synchronous mode', async function () {
      basePayload.config.sync_rate = 0;
      const resp = await axios({
        method: 'PATCH',
        url: `${pluginUrl}/${pluginId}`,
        data: basePayload,
      });
      logResponse(resp);

      expect(resp.status, 'Status should be 200').to.equal(200);
      await waitForConfigRebuild();
    });

    it('should limit proxy request with matched Header successfully', async function () {
      await verifyRateLimitingEffect({ rateLimit, url: urlProxy, headers });
    });

    it('should have key data sync to Redis storage contains correct header value and entry count', async function () {
      await checkRedisDBSize(1);

      await checkRedisEntries({
        expectedEntryCount: ['2'],
        expectedHost: limitHeaderValue,
      });
    });

    it('should limit proxy request and have entry count increased in Redis storage in synchronous mode', async function () {
      const result: any = await sendRequestInWindow({ url: `${urlProxy}`, headers: headers, containerName: kongContainerName, windowLengthInSeconds: windowLength, safeTimeBeforeNextWindowInSeconds: 3, rateLimit: 1 });
      const keyCheck = `${result.sendWindow}:${windowLength}:${namespaceValue}`;
      expect(result.response.status, 'Status should be 429').to.equal(429);
      
      await checkRedisEntries({
        expectedEntryCount: ['3','5'], //accept both entry counts to handle edge cases
        expectedHost: limitHeaderValue,
        keyName: keyCheck
      });
    });

    it('should change RLA plugin sync rate to 0.5 to enable periodic sync mode', async function () {
      basePayload.config.namespace = namespaceValueUpdate;
      basePayload.config.sync_rate = 0.5;
      const resp = await axios({
        method: 'PATCH',
        url: `${pluginUrl}/${pluginId}`,
        data: basePayload,
      });
      logResponse(resp);

      expect(resp.status, 'Status should be 200').to.equal(200);
      await waitForConfigRebuild();
    });

    it('should limit proxy request with updated RLA config', async function () {
      await resetRedisDB();
      await wait(isHybrid ? 8000 : 7000); // eslint-disable-line no-restricted-syntax
      headers[limitHeader] = limitHeaderValueUpdate;
      await verifyRateLimitingEffect({ rateLimit, url: urlProxy, headers });
    });

    it('should have key data periodic sync to Redis storage contains correct namespace with header value and entry count', async function () {
      //wait 1.5 seconds for counter sync
      await wait(1500);// eslint-disable-line no-restricted-syntax
      await checkRedisDBSize(1);

      await checkRedisEntries({
        expectedEntryCount: ['2'],
        expectedHost: limitHeaderValueUpdate,
        expectedNamespace: namespaceValueUpdate,
      });
    });

    it('should limit proxy request and have entry count increased in Redis storage periodic sync mode', async function () {
      const result: any = await sendRequestInWindow({ url: `${urlProxy}`, headers: headers, containerName: kongContainerName, windowLengthInSeconds: windowLength, safeTimeBeforeNextWindowInSeconds: 3, rateLimit: 1 });
      const keyCheck = `${result.sendWindow}:${windowLength}:${namespaceValueUpdate}`;
      expect(result.response.status, 'Status should be 429').to.equal(429);

      //wait 1.5 second for counter sync
      await wait(1500);// eslint-disable-line no-restricted-syntax

      await checkRedisEntries({
        expectedEntryCount: ['3','5'], //accept both entry counts to handle edge cases
        expectedHost: limitHeaderValueUpdate,
        expectedNamespace: namespaceValueUpdate,
        keyName: keyCheck
      });

    });

    after(async function () {
      await clearAllKongResources();
    });
  });

  context('when RLA Plugins expire synced counter in redis storage', function () {
    const path = `/${randomString()}`;
    const urlProxy = `${proxyUrl}${path}`;
    const limitHeader = 'X-Limit-Hit';
    const limitHeaderValue = 'redisExpire';
    const headers = { [limitHeader]: limitHeaderValue };
    const namespaceValue = 'namespaceExpire';

    let serviceId: string;
    let routeId: string;
    let basePayload: any;

    before(async function () {
      const service = await createGatewayService('RlaRedisExpireService');
      serviceId = service.id;
      const route = await createRouteForService(serviceId, [path]);
      routeId = route.id;

      basePayload = {
        name: 'rate-limiting-advanced',
        service: {
          id: serviceId,
        },
        route: {
          id: routeId,
        },
        config: {
          limit: [1],
          window_size: [10],
          window_type: 'fixed',
          identifier: 'header',
          header_name: limitHeader,
          sync_rate: 0.5,
          strategy: 'redis',
          namespace: namespaceValue,
          redis: {
            host: 'redis',
            port: 6379,
            username: redisUsername,
            password: redisPassword,
          },
        }
      };
    });

    it('should create RLA plugin with Redis storage with positive sync rate', async function () {
      await resetRedisDB();

      const resp = await axios({
        method: 'POST',
        url: pluginUrl,
        data: basePayload,
      });
      logResponse(resp);

      expect(resp.status, 'Status should be 201').to.equal(201);
      await waitForConfigRebuild();
    });

    it('should second limit proxy request according to RLA config', async function () {
      await verifyRateLimitingEffect({ rateLimit:1, url: urlProxy, headers });
    });

    it('should have key data periodic sync to Redis storage', async function () {
      //wait 1.5 seconds for counter sync
      await wait(1500);// eslint-disable-line no-restricted-syntax
      await checkRedisDBSize(1);

      await checkRedisEntries({
        expectedEntryCount: ['2'],
        expectedHost: limitHeaderValue,
        expectedNamespace: namespaceValue,
      });
    });

    it('should expire counter Redis storage in double window time', async function () {
      //wait for counter expire and gets deleted from redis
      await waitForRedisDBSize(0, 120000, 3000, true);
    });

    after(async function () {
      await clearAllKongResources();
    });

  });

  after(async function () {
    client.quit();
  });
});