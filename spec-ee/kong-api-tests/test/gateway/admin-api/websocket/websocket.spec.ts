import {
  createGatewayService,
  createRouteForService,
  expect,
  waitForConfigRebuild,
  postNegative,
  randomString,
  getGatewayBasePath,
  clearAllKongResources,
} from '@support';
import WebSocket from 'promise-ws';

describe('Gateway Websocket Tests', function () {
  ['ws', 'wss'].forEach(protocol => {
    const echoServer = `websocket-echo-server:${protocol == 'ws' ? 9000 : 9443}/.ws`;

    describe(`websocket ${protocol} related tests`, function () {
      const proxyUrl = getGatewayBasePath(`${protocol}Proxy`) + `/.${protocol}`;

      let ws: any;

      before(async function () {
        await createGatewayService('test-service', {
          url: `${protocol}://${echoServer}`,
        });
        await createRouteForService('test-service', undefined, {
          name: randomString(),
          paths: ['/.ws'],
          protocols: ['ws'],
        });
        await waitForConfigRebuild();
      });

      it('should send text message', async function () {
        ws = await WebSocket.create(proxyUrl, { rejectUnauthorized: false });
        const received = new Promise(resolve => ws.on('message', data => resolve(data)));
        ws.send('something-ws');
        expect(await received).to.equal('something-ws');
      });

      it('should send binary message', async function () {
        const buffer = Buffer.alloc(1, 210);

        ws = await WebSocket.create(proxyUrl, { rejectUnauthorized: false });
        const received: Promise<any> = new Promise(resolve => ws.on('message', data => resolve(data)));
        ws.send(buffer, { binary: true });
        const data = await received;
        expect(data.constructor).to.equal(Buffer);
        expect(data[0]).to.equal(210);
      });

      it('prefix routes should work', async function () {
        ws = await WebSocket.create(`${proxyUrl}12345`, {
          rejectUnauthorized: false,
        });
        const received = new Promise(resolve => ws.on('message', data => resolve(data)));
        await ws.send('send ws to prefix routes');
        expect(await received).to.equal('send ws to prefix routes');
      });

      afterEach(async function () {
        await ws.close();
      });

      after(clearAllKongResources);
    });
  });

  describe('service/routes mismatch negative tests', function () {
    before(async function () {
      await createGatewayService('ws-service', {
        url: 'ws://websocket-echo-server:9000',
      });
      await createGatewayService('wss-service', {
        url: 'wss://websocket-echo-server:9443',
      });
      await createGatewayService('http-service', {
        url: 'http://websocket-echo-server:9000',
      });
      await createGatewayService('https-service', {
        url: 'https://websocket-echo-server:9443',
      });

      await waitForConfigRebuild({ interval: 1000 });
    });

    it('should not create http route when service is websocket service', async function () {
      const wsResp = await postNegative(`${getGatewayBasePath('admin')}/services/ws-service/routes`, {
        name: randomString(),
        paths: ['/.wshttp'],
        protocols: ['http'],
      });

      expect(wsResp.status, 'Status should be 400').to.equal(400);

      expect(wsResp.data.message, 'Should have correct error message').to.contain(
        'schema violation (protocols: route/service protocol mismatch)',
      );
    });

    it('should not create http route when service is websocket secure service', async function () {
      const wssResp = await postNegative(`${getGatewayBasePath('admin')}/services/wss-service/routes`, {
        name: randomString(),
        paths: ['/.wsshttp'],
        protocols: ['http'],
      });

      expect(wssResp.status, 'Status should be 400').to.equal(400);

      expect(wssResp.data.message, 'Should have correct error message').to.contain(
        'schema violation (protocols: route/service protocol mismatch)',
      );
    });

    it('should not create https route when service is websocket service', async function () {
      const wsResp = await postNegative(`${getGatewayBasePath('admin')}/services/ws-service/routes`, {
        name: randomString(),
        paths: ['/.wshttps'],
        protocols: ['https'],
      });

      expect(wsResp.status, 'Status should be 400').to.equal(400);

      expect(wsResp.data.message, 'Should have correct error message').to.contain(
        'schema violation (protocols: route/service protocol mismatch)',
      );
    });

    it('should not create https route when service is websocket secure service', async function () {
      const wssResp = await postNegative(`${getGatewayBasePath('admin')}/services/wss-service/routes`, {
        name: randomString(),
        paths: ['/.wsshttps'],
        protocols: ['https'],
      });

      expect(wssResp.status, 'Status should be 400').to.equal(400);

      expect(wssResp.data.message, 'Should have correct error message').to.contain(
        'schema violation (protocols: route/service protocol mismatch)',
      );
    });

    it('should not create ws route when service is http', async function () {
      const resp = await postNegative(`${getGatewayBasePath('admin')}/services/http-service/routes`, {
        name: randomString(),
        paths: ['/httptows'],
        protocols: ['ws'],
      });

      expect(resp.status, 'Status should be 400').to.equal(400);

      expect(resp.data.message, 'Should have correct error message').to.contain(
        'schema violation (protocols: route/service protocol mismatch)',
      );
    });

    it('should not create wss route when service is https', async function () {
      const resp = await postNegative(`${getGatewayBasePath('admin')}/services/https-service/routes`, {
        name: randomString(),
        paths: ['/httpstowss'],
        protocols: ['wss'],
      });

      expect(resp.status, 'Status should be 400').to.equal(400);

      expect(resp.data.message, 'Should have correct error message').to.contain(
        'schema violation (protocols: route/service protocol mismatch)',
      );
    });

    after(clearAllKongResources);
  });

  describe('http/https service/route can still proxy ws/wss traffic', function () {
    before(async function () {
      await createGatewayService('http-service', {
        url: 'http://websocket-echo-server:9000',
      });
      await createRouteForService('http-service', undefined, {
        name: randomString(),
        paths: ['/.httpws'],
        protocols: ['http'],
      });
      await createGatewayService('https-service', {
        url: 'https://websocket-echo-server:9443',
      });
      await createRouteForService('https-service', undefined, {
        name: randomString(),
        paths: ['/.httpswss'],
        protocols: ['https'],
      });
      await waitForConfigRebuild({ interval: 1000 });
    });

    it('should route ws traffic when service and route is http', async function () {
      const ws = await WebSocket.create(getGatewayBasePath('wsProxy') + `/.httpws`);

      await ws.send('ws as http');
      const received = new Promise(resolve => ws.on('message', data => resolve(data)));
      expect(await received).to.equal('ws as http');
      ws.close();
    });

    it('should route wss traffic when service and route is https', async function () {
      const wss = await WebSocket.create(getGatewayBasePath('wssProxy') + `/.httpswss`, {
        rejectUnauthorized: false,
      });
      await wss.send('wss as https');
      const received = new Promise(resolve => wss.on('message', data => resolve(data)));
      expect(await received).to.equal('wss as https');
      wss.close();
    });

    after(clearAllKongResources);
  });
});
