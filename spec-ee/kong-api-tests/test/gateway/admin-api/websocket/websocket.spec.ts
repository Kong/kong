import {
  createGatewayService,
  createRouteForService,
  deleteGatewayRoute,
  deleteGatewayService,
  Environment,
  expect,
  getBasePath,
  isGwHybrid,
  waitForConfigRebuild,
  postNegative,
  randomString,
  wait,
} from '@support';
import WebSocket from 'promise-ws';

describe('Gateway Websocket Tests', function () {
  const hybridTimeout = 8000; // confirm timeout when hybrid is functioning
  const classicTimeout = 5000;
  const waitTime = 20;
  const isHybrid = isGwHybrid();
  const wsEchoServer = `${getBasePath({
    environment: Environment.gateway.ec2TestServer,
  })}`;
  describe('websocket ws related tests', function () {
    const wsProxyUrl =
      getBasePath({ environment: Environment.gateway.wsProxy }) + '/.ws';

    const wsServicePayload = {
      name: randomString(),
      url: `ws://${wsEchoServer}:8080`,
    };

    const wsRoutePayload = {
      name: randomString(),
      paths: ['/.ws'],
      protocols: ['ws'],
    };

    let wsServiceId: string;
    let wsRouteId: string;
    let ws: any;

    before(async function () {
      const wsService = await createGatewayService(
        wsServicePayload.name,
        wsServicePayload
      );
      wsServiceId = wsService.id;

      const wsRoute = await createRouteForService(
        wsServiceId,
        undefined,
        wsRoutePayload
      );
      wsRouteId = wsRoute.id;

      await waitForConfigRebuild();
    });

    it('should send text message via ws websocket connection', async function () {
      ws = await WebSocket.create(wsProxyUrl);
      ws.send('something-ws');
      await wait(waitTime);
      await ws.on('message', function incoming(data) {
        expect(data).to.equal('something-ws');
      });
    });

    it('should send binary message via ws websocket connection', async function () {
      const array = new Float32Array(5);
      for (let i = 0; i < array.length; ++i) {
        array[i] = i / 2;
      }

      ws = await WebSocket.create(wsProxyUrl);
      ws.send(array);
      await wait(waitTime);
      await ws.on('message', (data, isBinary) => {
        const message = isBinary ? data : data.toString();
        expect(message).to.equal(
          '\u0000\u0000\u0000\u0000\u0000\u0000\u0000?\u0000\u0000�?\u0000\u0000�?\u0000\u0000\u0000@'
        );
      });
    });

    it('should prefix routes work with ws', async function () {
      const wsPrefixProxyUrl =
        getBasePath({ environment: Environment.gateway.wsProxy }) + '/.ws12345';

      ws = await WebSocket.create(wsPrefixProxyUrl);
      await ws.send('send ws to prefix routes');
      await wait(waitTime);
      await ws.on('message', function incoming(data) {
        expect(data).to.equal('send ws to prefix routes');
      });
    });

    afterEach(async function () {
      await ws.close();
    });

    after(async function () {
      await deleteGatewayRoute(wsRouteId);
      await deleteGatewayService(wsServiceId);
    });
  });

  describe('websocket wss related tests', function () {
    const wssProxyUrl =
      getBasePath({ environment: Environment.gateway.wssProxy }) + '/.wss';

    const wssServicePayload = {
      name: randomString(),
      url: `wss://${wsEchoServer}:52000`,
    };

    const wssRoutePayload = {
      name: randomString(),
      paths: ['/.wss'],
      protocols: ['wss'],
    };

    let wssServiceId: string;
    let wssRouteId: string;
    let wss: any;

    before(async function () {
      const wssService = await createGatewayService(
        wssServicePayload.name,
        wssServicePayload
      );
      wssServiceId = wssService.id;

      const wssRoute = await createRouteForService(
        wssServiceId,
        undefined,
        wssRoutePayload
      );
      wssRouteId = wssRoute.id;

      await waitForConfigRebuild();
    });

    it('should send text message via wss websocket connection', async function () {
      wss = await WebSocket.create(wssProxyUrl, {
        rejectUnauthorized: false,
      });
      wss.send('something-wss');
      await wait(waitTime);
      await wss.on('message', function incoming(data) {
        expect(data).to.equal('something-wss');
      });
    });

    it('should send binary message via wss websocket connection', async function () {
      const array = new Float32Array(5);
      for (let i = 0; i < array.length; ++i) {
        array[i] = i / 2;
      }

      wss = await WebSocket.create(wssProxyUrl, {
        rejectUnauthorized: false,
      });
      wss.send(array);
      await wait(waitTime);
      await wss.on('message', function (data, isBinary) {
        const message = isBinary ? data : data.toString();
        expect(message).to.equal(
          '\u0000\u0000\u0000\u0000\u0000\u0000\u0000?\u0000\u0000�?\u0000\u0000�?\u0000\u0000\u0000@'
        );
      });
    });

    it('should prefix routes work with wss', async function () {
      const wssPrefixProxyUrl =
        getBasePath({ environment: Environment.gateway.wssProxy }) +
        '/.wss12345';

      wss = await WebSocket.create(wssPrefixProxyUrl, {
        rejectUnauthorized: false,
      });
      await wss.send('send wss to prefix routes');
      await wait(waitTime);
      await wss.on('message', function incoming(data) {
        expect(data).to.equal('send wss to prefix routes');
      });
    });

    afterEach(async function () {
      await wss.close();
    });

    after(async function () {
      await deleteGatewayRoute(wssRouteId);
      await deleteGatewayService(wssServiceId);
    });
  });

  describe('service/routes mismatch negative tests', function () {
    const wsServicePayload = {
      name: randomString(),
      url: `ws://${wsEchoServer}:8080`,
    };

    const wssServicePayload = {
      name: randomString(),
      url: `wss://${wsEchoServer}:52000`,
    };

    const httpServicePayload = {
      name: randomString(),
      url: `http://${wsEchoServer}:8080`,
    };

    const httpsServicePayload = {
      name: randomString(),
      url: `https://${wsEchoServer}:52000`,
    };

    let wsServiceId: string;
    let wssServiceId: string;
    let httpServiceId: string;
    let httpsServiceId: string;

    before(async function () {
      const wsService = await createGatewayService(
        wsServicePayload.name,
        wsServicePayload
      );
      wsServiceId = wsService.id;

      const wssService = await createGatewayService(
        wssServicePayload.name,
        wssServicePayload
      );
      wssServiceId = wssService.id;

      const httpService = await createGatewayService(
        httpServicePayload.name,
        httpServicePayload
      );
      httpServiceId = httpService.id;

      const httpsService = await createGatewayService(
        httpsServicePayload.name,
        httpsServicePayload
      );
      httpsServiceId = httpsService.id;

      await wait(isHybrid ? hybridTimeout : classicTimeout);
    });

    it('should not create http route when service is websocket service', async function () {
      const wsHttpPayload = {
        name: randomString(),
        paths: ['/.wshttp'],
        protocols: ['http'],
      };

      const wsUrl = `${getBasePath({
        environment: Environment.gateway.admin,
      })}/services/${wsServiceId}/routes`;

      const wsResp = await postNegative(wsUrl, wsHttpPayload);

      expect(wsResp.status, 'Status should be 400').to.equal(400);

      expect(
        wsResp.data.message,
        'Should have correct error message'
      ).to.contain(
        'schema violation (protocols: route/service protocol mismatch)'
      );
    });

    it('should not create http route when service is websocket secure service', async function () {
      const wssHttpPayload = {
        name: randomString(),
        paths: ['/.wsshttp'],
        protocols: ['http'],
      };

      const wssUrl = `${getBasePath({
        environment: Environment.gateway.admin,
      })}/services/${wssServiceId}/routes`;

      const wssResp = await postNegative(wssUrl, wssHttpPayload);

      expect(wssResp.status, 'Status should be 400').to.equal(400);

      expect(
        wssResp.data.message,
        'Should have correct error message'
      ).to.contain(
        'schema violation (protocols: route/service protocol mismatch)'
      );
    });

    it('should not create https route when service is websocket service', async function () {
      const wsHttpsPayload = {
        name: randomString(),
        paths: ['/.wshttps'],
        protocols: ['https'],
      };

      const wsUrl = `${getBasePath({
        environment: Environment.gateway.admin,
      })}/services/${wsServiceId}/routes`;

      const wsResp = await postNegative(wsUrl, wsHttpsPayload);

      expect(wsResp.status, 'Status should be 400').to.equal(400);

      expect(
        wsResp.data.message,
        'Should have correct error message'
      ).to.contain(
        'schema violation (protocols: route/service protocol mismatch)'
      );
    });

    it('should not create https route when service is websocket secure service', async function () {
      const wssHttpsPayload = {
        name: randomString(),
        paths: ['/.wsshttps'],
        protocols: ['https'],
      };

      const wssUrl = `${getBasePath({
        environment: Environment.gateway.admin,
      })}/services/${wssServiceId}/routes`;

      const wssResp = await postNegative(wssUrl, wssHttpsPayload);

      expect(wssResp.status, 'Status should be 400').to.equal(400);

      expect(
        wssResp.data.message,
        'Should have correct error message'
      ).to.contain(
        'schema violation (protocols: route/service protocol mismatch)'
      );
    });

    it('should not create ws route when service is http', async function () {
      const httpRoutePayload = {
        name: randomString(),
        paths: ['/httptows'],
        protocols: ['ws'],
      };

      const url = `${getBasePath({
        environment: Environment.gateway.admin,
      })}/services/${httpServiceId}/routes`;

      const resp = await postNegative(url, httpRoutePayload);

      expect(resp.status, 'Status should be 400').to.equal(400);

      expect(resp.data.message, 'Should have correct error message').to.contain(
        'schema violation (protocols: route/service protocol mismatch)'
      );
    });

    it('should not create wss route when service is https', async function () {
      const httpsRoutePayload = {
        name: randomString(),
        paths: ['/httpstowss'],
        protocols: ['wss'],
      };

      const url = `${getBasePath({
        environment: Environment.gateway.admin,
      })}/services/${httpsServiceId}/routes`;

      const resp = await postNegative(url, httpsRoutePayload);

      expect(resp.status, 'Status should be 400').to.equal(400);

      expect(resp.data.message, 'Should have correct error message').to.contain(
        'schema violation (protocols: route/service protocol mismatch)'
      );
    });

    after(async function () {
      [wsServiceId, wssServiceId, httpsServiceId, httpServiceId].forEach(
        async (service) => await deleteGatewayService(service)
      );
    });
  });

  describe('http/https service/route can still proxy ws/wss traffic', function () {
    const httpServicePayload = {
      name: randomString(),
      url: `http://${wsEchoServer}:8080`,
    };

    const httpRoutePayload = {
      name: randomString(),
      paths: ['/.httpws'],
      protocols: ['http'],
    };

    const httpsServicePayload = {
      name: randomString(),
      url: `https://${wsEchoServer}:52000`,
    };

    const httpsRoutePayload = {
      name: randomString(),
      paths: ['/.httpswss'],
      protocols: ['https'],
    };

    let httpServiceId: string;
    let httpRouteId: string;
    let httpsServiceId: string;
    let httpsRouteId: string;
    let ws: any;
    let wss: any;

    before(async function () {
      const httpService = await createGatewayService(
        httpServicePayload.name,
        httpServicePayload
      );
      httpServiceId = httpService.id;

      const httpRoute = await createRouteForService(
        httpServiceId,
        undefined,
        httpRoutePayload
      );
      httpRouteId = httpRoute.id;

      const httpsService = await createGatewayService(
        httpsServicePayload.name,
        httpsServicePayload
      );
      httpsServiceId = httpsService.id;

      const httpsRoute = await createRouteForService(
        httpsServiceId,
        undefined,
        httpsRoutePayload
      );
      httpsRouteId = httpsRoute.id;

      await wait(isHybrid ? hybridTimeout : classicTimeout);

      const wsHttpProxyUrl =
        getBasePath({ environment: Environment.gateway.wsProxy }) + '/.httpws';
      ws = await WebSocket.create(wsHttpProxyUrl);

      const wssHttpsProxyUrl =
        getBasePath({ environment: Environment.gateway.wssProxy }) +
        '/.httpswss';
      wss = await WebSocket.create(wssHttpsProxyUrl, {
        rejectUnauthorized: false,
      });
    });

    it('should route ws traffic when service and route is http', async function () {
      await ws.send('ws as http');
      await wait(waitTime);
      await ws.on('message', function incoming(data) {
        expect(data).to.equal('ws as http');
      });
    });

    it('should route wss traffic when service and route is https', async function () {
      await wss.send('wss as https');
      await wait(waitTime);
      await wss.on('message', function incoming(data) {
        expect(data).to.equal('wss as https');
      });
    });

    after(async function () {
      ws.close();
      wss.close();
      await deleteGatewayRoute(httpRouteId);
      await deleteGatewayRoute(httpsRouteId);
      await deleteGatewayService(httpServicePayload.name);
      await deleteGatewayService(httpsServicePayload.name);
    });
  });
});
