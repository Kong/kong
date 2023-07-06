import {
  createGatewayService,
  createRouteForService,
  deleteGatewayRoute,
  deleteGatewayService,
  Environment,
  expect,
  getBasePath,
  isGwHybrid,
  isLocalDatabase,
  randomString,
  wait,
  logResponse,
} from '@support';
import axios from 'axios';
import WebSocket from 'promise-ws';

describe('Websocket Size Limit Plugin Tests', function () {
  const hybridTimeout = 8000; //confirm timeout when hybrid is functioning
  const classicTimeout = 5000;
  const waitTime = 20;
  const isLocalDb = isLocalDatabase();
  const isHybrid = isGwHybrid();
  const baseUrl = getBasePath({
    environment: Environment.gateway.admin,
  });
  const wsEchoServer = `${getBasePath({
    environment: Environment.gateway.ec2TestServer,
  })}`;

  describe('Tests with "ws" protocol', function () {
    const url = `${baseUrl}/plugins`;

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
    let basePayload: any;
    let pluginId: string;
    let client_max_payload: number;
    let upstream_max_payload: number;

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

      basePayload = {
        name: 'websocket-size-limit',
        service: {
          id: wsServiceId,
        },
        route: {
          id: wsRouteId,
        },
      };

      await wait(isHybrid ? hybridTimeout : classicTimeout);
    });

    it('should be able to add websocket size limit plugin', async function () {
      client_max_payload = 42;
      upstream_max_payload = 1000;

      const pluginPayload = {
        ...basePayload,
        config: {
          client_max_payload: client_max_payload,
          upstream_max_payload: upstream_max_payload,
        },
      };

      const resp = await axios({
        method: 'post',
        url,
        data: pluginPayload,
      });
      logResponse(resp);

      expect(resp.status, 'Status should be 201').to.equal(201);
      pluginId = resp.data.id;
    });

    it('should send message when the size is below the limit', async function () {
      ws = await WebSocket.create(wsProxyUrl);
      ws.send(345);
      await wait(waitTime);

      await ws.on('message', function incoming(data) {
        expect(data).to.equal('345');
      });

      await ws.close();
    });

    it('should be able to patch the plugin with client payload size limited ', async function () {
      client_max_payload = 3;
      upstream_max_payload = 400;
      const patchUrl = `${url}/${pluginId}`;

      const pluginPayload = {
        ...basePayload,
        config: {
          client_max_payload: client_max_payload,
          upstream_max_payload: upstream_max_payload,
        },
      };

      const resp = await axios({
        method: 'patch',
        url: patchUrl,
        data: pluginPayload,
      });
      logResponse(resp);

      expect(resp.status, 'Status should be 200').to.equal(200);
      await wait(isHybrid ? hybridTimeout : classicTimeout);
    });

    it('should not send data when size is limited', async function () {
      await wait(isLocalDb ? 0 : hybridTimeout);
      ws = await WebSocket.create(wsProxyUrl);
      ws.send('12345');
      await wait(waitTime);

      await ws.on('message', function incoming(data) {
        expect(data).to.equal('12345');
      });

      await ws.addEventListener('close', function (data) {
        expect(data.code).to.equal(1009);
        expect(data.reason).to.equal('Payload Too Large');
      });

      await ws.close();
    });

    after(async function () {
      await deleteGatewayRoute(wsRouteId);
      await deleteGatewayService(wsServiceId);
    });
  });

  describe('Tests with "wss" protocol', function () {
    const url = `${baseUrl}/plugins`;

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
    let basePayload: any;
    let pluginId: string;
    let client_max_payload: number;
    let upstream_max_payload: number;

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

      basePayload = {
        name: 'websocket-size-limit',
        service: {
          id: wssServiceId,
        },
        route: {
          id: wssRouteId,
        },
      };

      await wait(isHybrid ? hybridTimeout : classicTimeout);
    });

    it('should be able to add websocket size limit plugin for wss', async function () {
      client_max_payload = 42;
      upstream_max_payload = 1000;

      const pluginPayload = {
        ...basePayload,
        config: {
          client_max_payload: client_max_payload,
          upstream_max_payload: upstream_max_payload,
        },
      };

      const resp = await axios({
        method: 'post',
        url,
        data: pluginPayload,
      });
      logResponse(resp);

      expect(resp.status, 'Status should be 201').to.equal(201);
      pluginId = resp.data.id;
    });

    it('should send message when the size is below the limit for wss', async function () {
      wss = await WebSocket.create(wssProxyUrl, {
        rejectUnauthorized: false,
      });
      wss.send(345);
      await wait(waitTime);

      await wss.on('message', function incoming(data) {
        expect(data).to.equal('345');
      });

      await wss.close();
    });

    it('should be able to patch the plugin with client payload size limited for wss', async function () {
      client_max_payload = 3;
      upstream_max_payload = 400;
      const patchUrl = `${url}/${pluginId}`;

      const pluginPayload = {
        ...basePayload,
        config: {
          client_max_payload: client_max_payload,
          upstream_max_payload: upstream_max_payload,
        },
      };

      const resp = await axios({
        method: 'patch',
        url: patchUrl,
        data: pluginPayload,
      });
      logResponse(resp);

      expect(resp.status, 'Status should be 200').to.equal(200);
      await wait(isHybrid ? hybridTimeout : classicTimeout);
    });

    it('should not send data when size is limited for wss', async function () {
      await wait(isHybrid ? hybridTimeout : classicTimeout);

      wss = await WebSocket.create(wssProxyUrl, {
        rejectUnauthorized: false,
      });
      wss.send('12345');
      await wait(waitTime);

      await wss.on('message', function incoming(data) {
        expect(data).to.equal('12345');
      });

      await wss.addEventListener('close', function (data) {
        expect(data.code).to.equal(1009);
        expect(data.reason).to.equal('Payload Too Large');
      });

      await wss.close();
    });

    after(async function () {
      await deleteGatewayRoute(wssRouteId);
      await deleteGatewayService(wssServiceId);
    });
  });
});
