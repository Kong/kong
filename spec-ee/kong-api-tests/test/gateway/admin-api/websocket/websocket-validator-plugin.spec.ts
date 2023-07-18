import {
  createGatewayService,
  createRouteForService,
  deleteGatewayRoute,
  deleteGatewayService,
  Environment,
  expect,
  getBasePath,
  postNegative,
  randomString,
  wait,
  logResponse,
  waitForConfigRebuild,
} from '@support';
import axios from 'axios';
import WebSocket from 'promise-ws';

describe('Websocket Validator Plugin Tests', function () {
  const waitTime = 20;
  const wsEchoServer = `${getBasePath({
    environment: Environment.gateway.ec2TestServer,
  })}`;
  const baseUrl = getBasePath({
    environment: Environment.gateway.admin,
  });
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
    let textFrameDataType: string;
    let binaryFrameDataType: string;

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
        name: 'websocket-validator',
        service: {
          id: wsServiceId,
        },
        route: {
          id: wsRouteId,
        },
      };

      await waitForConfigRebuild();
    });

    it('should send message via ws websocket connection before adding plugin', async function () {
      ws = await WebSocket.create(wsProxyUrl);
      ws.send(345);
      await wait(waitTime);

      await ws.on('message', function incoming(data) {
        expect(data).to.equal('345');
      });

      await ws.close();
    });

    it('should be able add websocket validator plugin', async function () {
      textFrameDataType = 'string';
      binaryFrameDataType = 'string';

      const pluginPayload = {
        ...basePayload,
        config: {
          client: {
            text: {
              schema: `{"type":"${textFrameDataType}"}`,
              type: 'draft4',
            },
            binary: {
              schema: `{"type":"${binaryFrameDataType}"}`,
              type: 'draft4',
            },
          },
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
      await waitForConfigRebuild();
    });

    it('should send string ', async function () {
      ws = await WebSocket.create(wsProxyUrl);
      ws.send('"something-ws"');
      await wait(waitTime);

      await ws.on('message', function incoming(data) {
        expect(data).to.equal('"something-ws"');
      });

      await ws.close();
    });

    it('should send string in binary format ', async function () {
      ws = await WebSocket.create(wsProxyUrl);
      const encoder = new TextEncoder();
      const textBuffer = encoder.encode('"something-ws-binary"');
      ws.send(textBuffer);
      await wait(waitTime);

      await ws.on('message', (data, isBinary) => {
        const message = isBinary ? data : data.toString();
        expect(message).to.equal('"something-ws-binary"');
      });

      await ws.close();
    });

    it('should not send non string data', async function () {
      ws = await WebSocket.create(wsProxyUrl);
      ws.send(5);
      await wait(waitTime);

      await ws.addEventListener('close', function (data) {
        expect(data.code).to.equal(1007);
        expect(data.reason).to.equal('Invalid Frame Payload Data');
      });

      await ws.close();
    });

    it('should not patch the plugin when schema is not correct ', async function () {
      textFrameDataType = 'strin**';
      binaryFrameDataType = 'strin**';
      const patchUrl = `${url}/${pluginId}`;

      const pluginPayload = {
        ...basePayload,
        config: {
          client: {
            text: {
              schema: `{"type":"${textFrameDataType}"}`,
              type: 'draft4',
            },
            binary: {
              schema: `{"type":"${binaryFrameDataType}"}`,
              type: 'defat4',
            },
          },
        },
      };

      const resp = await postNegative(patchUrl, pluginPayload, 'patch');
      expect(resp.status, 'Status should be 400').to.equal(400);
      expect(resp.data.message, 'should have correct error message').to.contain(
        `schema violation`
      );
    });

    it('should be able to patch the plugin with number ', async function () {
      textFrameDataType = 'number';
      binaryFrameDataType = 'number';
      const patchUrl = `${url}/${pluginId}`;

      const pluginPayload = {
        ...basePayload,
        config: {
          client: {
            text: {
              schema: `{"type":"${textFrameDataType}"}`,
              type: 'draft4',
            },
            binary: {
              schema: `{"type":"${binaryFrameDataType}"}`,
              type: 'draft4',
            },
          },
        },
      };

      const resp = await axios({
        method: 'patch',
        url: patchUrl,
        data: pluginPayload,
      });
      logResponse(resp);

      expect(resp.status, 'Status should be 200').to.equal(200);
      await waitForConfigRebuild();
    });

    it('should be able to send number', async function () {
      ws = await WebSocket.create(wsProxyUrl);
      ws.send(5);
      await wait(waitTime);

      await ws.on('message', function incoming(data) {
        expect(data).to.equal('5');
      });

      await ws.addEventListener('close', function (data) {
        expect(data.code).to.equal(1005);
      });

      await ws.close();
    });

    it('should send number in binary format ', async function () {
      ws = await WebSocket.create(wsProxyUrl);
      const b_number = Number(235).toString(2);
      ws.send(b_number);
      await wait(waitTime);

      await ws.on('message', (data, isBinary) => {
        const message = isBinary ? data : data.toString();
        expect(message).to.equal('11101011');
      });

      await ws.addEventListener('close', function (data) {
        expect(data.code).to.equal(1005);
      });

      await ws.close();
    });

    it('should not send non number data when plugin is configured for number', async function () {
      const myData = 'test';
      ws = await WebSocket.create(wsProxyUrl);
      ws.send(myData);
      await wait(waitTime);

      await ws.addEventListener('close', function (data) {
        expect(data.code).to.equal(1007);
        expect(data.reason).to.equal('Invalid Frame Payload Data');
      });

      await ws.close();
    });

    it('should be able to patch the plugin with boolean ', async function () {
      textFrameDataType = 'boolean';
      binaryFrameDataType = 'boolean';
      const patchUrl = `${url}/${pluginId}`;

      const pluginPayload = {
        ...basePayload,
        config: {
          client: {
            text: {
              schema: `{"type":"${textFrameDataType}"}`,
              type: 'draft4',
            },
            binary: {
              schema: `{"type":"${binaryFrameDataType}"}`,
              type: 'draft4',
            },
          },
        },
      };

      const resp = await axios({
        method: 'patch',
        url: patchUrl,
        data: pluginPayload,
      });
      logResponse(resp);

      expect(resp.status, 'Status should be 200').to.equal(200);
      await waitForConfigRebuild();
    });

    it('should send boolean', async function () {
      ws = await WebSocket.create(wsProxyUrl);
      ws.send('true');
      await wait(waitTime);

      await ws.on('message', function incoming(data) {
        expect(data).to.equal('true');
      });

      await ws.addEventListener('close', function (data) {
        expect(data.code).to.equal(1005);
      });

      await ws.close();
    });

    it('should send boolean in binary format ', async function () {
      ws = await WebSocket.create(wsProxyUrl);
      ws.send('true', { binary: true });
      await wait(waitTime);

      await ws.on('message', (data, isBinary) => {
        const message = isBinary ? data : data.toString();
        expect(message).to.equal('true');
      });

      await ws.addEventListener('close', function (data) {
        expect(data.code).to.equal(1005);
      });

      await ws.close();
    });

    it('should not send non boolean data when plugin is configured for boolean', async function () {
      const myData = 'test_boolean';
      ws = await WebSocket.create(wsProxyUrl);
      ws.send(myData);
      await wait(waitTime);

      await ws.addEventListener('close', function (data) {
        expect(data.code).to.equal(1007);
        expect(data.reason).to.equal('Invalid Frame Payload Data');
      });

      await ws.close();
    });

    it('should be able to patch the plugin with object ', async function () {
      textFrameDataType = 'object';
      binaryFrameDataType = 'object';
      const patchUrl = `${url}/${pluginId}`;

      const pluginPayload = {
        ...basePayload,
        config: {
          client: {
            text: {
              schema: `{"type":"${textFrameDataType}"}`,
              type: 'draft4',
            },
            binary: {
              schema: `{"type":"${binaryFrameDataType}"}`,
              type: 'draft4',
            },
          },
        },
      };

      const resp = await axios({
        method: 'patch',
        url: patchUrl,
        data: pluginPayload,
      });
      logResponse(resp);

      expect(resp.status, 'Status should be 200').to.equal(200);
      await waitForConfigRebuild();
    });

    it('should send object', async function () {
      ws = await WebSocket.create(wsProxyUrl);
      ws.send(
        JSON.stringify({
          id: 'client1',
        })
      );
      await wait(waitTime);

      await ws.on('message', function incoming(data) {
        expect(data).to.equal(
          JSON.stringify({
            id: 'client1',
          })
        );
      });

      await ws.addEventListener('close', function (data) {
        expect(data.code).to.equal(1005);
      });

      await ws.close();
    });

    it('should send object in binary format', async function () {
      ws = await WebSocket.create(wsProxyUrl);
      const bjson_arr = [
        123, 34, 107, 101, 121, 34, 58, 34, 118, 97, 108, 117, 101, 34, 125,
      ];

      ws.send(bjson_arr);
      await wait(waitTime);

      await ws.on('message', (data, isBinary) => {
        const message = isBinary ? data : data.toString();
        expect(message).to.equal('{"key":"value"}');
      });

      await ws.addEventListener('close', function (data) {
        expect(data.code).to.equal(1005);
      });

      await ws.close();
    });

    it('should not send non object data when plugin is configured for object', async function () {
      ws = await WebSocket.create(wsProxyUrl);
      ws.send(1245);
      await wait(waitTime);

      await ws.addEventListener('close', function (data) {
        expect(data.code).to.equal(1007);
        expect(data.reason).to.equal('Invalid Frame Payload Data');
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
    let textFrameDataType: string;
    let binaryFrameDataType: string;

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
        name: 'websocket-validator',
        service: {
          id: wssServiceId,
        },
        route: {
          id: wssRouteId,
        },
      };

      await waitForConfigRebuild();
    });

    it('should send message via wss websocket connection before adding plugin', async function () {
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

    it('should be able add websocket validator plugin', async function () {
      textFrameDataType = 'string';
      binaryFrameDataType = 'string';

      const pluginPayload = {
        ...basePayload,
        config: {
          client: {
            text: {
              schema: `{"type":"${textFrameDataType}"}`,
              type: 'draft4',
            },
            binary: {
              schema: `{"type":"${binaryFrameDataType}"}`,
              type: 'draft4',
            },
          },
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

      await waitForConfigRebuild();
    });

    it('should send string for wss ', async function () {
      wss = await WebSocket.create(wssProxyUrl, {
        rejectUnauthorized: false,
      });
      wss.send('"something-wss"');
      await wait(waitTime);

      await wss.on('message', function incoming(data) {
        expect(data).to.equal('"something-wss"');
      });
      await wss.close();
    });

    it('should send string in binary format ', async function () {
      wss = await WebSocket.create(wssProxyUrl, {
        rejectUnauthorized: false,
      });
      const encoder = new TextEncoder();
      const textBuffer = encoder.encode('"something-wss-binary"');
      wss.send(textBuffer);
      await wait(waitTime);

      await wss.on('message', (data, isBinary) => {
        const message = isBinary ? data : data.toString();
        expect(message).to.equal('"something-wss-binary"');
      });

      await wss.close();
    });

    it('should not send non string data for wss', async function () {
      wss = await WebSocket.create(wssProxyUrl, {
        rejectUnauthorized: false,
      });
      wss.send(5);
      await wait(waitTime);

      await wss.addEventListener('close', function (data) {
        expect(data.code).to.equal(1007);
        expect(data.reason).to.equal('Invalid Frame Payload Data');
      });

      await wss.close();
    });

    it('should be able to patch the plugin with number ', async function () {
      textFrameDataType = 'number';
      binaryFrameDataType = 'number';
      const patchUrl = `${url}/${pluginId}`;

      const pluginPayload = {
        ...basePayload,
        config: {
          client: {
            text: {
              schema: `{"type":"${textFrameDataType}"}`,
              type: 'draft4',
            },
            binary: {
              schema: `{"type":"${binaryFrameDataType}"}`,
              type: 'draft4',
            },
          },
        },
      };

      const resp = await axios({
        method: 'patch',
        url: patchUrl,
        data: pluginPayload,
      });
      logResponse(resp);

      expect(resp.status, 'Status should be 200').to.equal(200);

      await waitForConfigRebuild();
    });

    it('should be able to send number for wss', async function () {
      wss = await WebSocket.create(wssProxyUrl, {
        rejectUnauthorized: false,
      });
      wss.send(5);
      await wait(waitTime);

      await wss.on('message', function incoming(data) {
        expect(data).to.equal('5');
      });

      await wss.addEventListener('close', function (data) {
        expect(data.code).to.equal(1005);
      });

      await wss.close();
    });

    it('should send number in binary format for wss', async function () {
      wss = await WebSocket.create(wssProxyUrl, {
        rejectUnauthorized: false,
      });
      const b_number = Number(235).toString(2);
      wss.send(b_number);
      await wait(waitTime);

      await wss.on('message', (data, isBinary) => {
        const message = isBinary ? data : data.toString();
        expect(message).to.equal('11101011');
      });

      await wss.addEventListener('close', function (data) {
        expect(data.code).to.equal(1005);
      });

      await wss.close();
    });

    it('should not send non number data when plugin is configured for number for wss', async function () {
      const myData = 'test';
      wss = await WebSocket.create(wssProxyUrl, {
        rejectUnauthorized: false,
      });
      wss.send(myData);
      await wait(waitTime);

      await wss.addEventListener('close', function (data) {
        expect(data.code).to.equal(1007);
        expect(data.reason).to.equal('Invalid Frame Payload Data');
      });

      await wss.close();
    });

    it('should be able to patch the plugin with boolean ', async function () {
      textFrameDataType = 'boolean';
      binaryFrameDataType = 'boolean';
      const patchUrl = `${url}/${pluginId}`;

      const pluginPayload = {
        ...basePayload,
        config: {
          client: {
            text: {
              schema: `{"type":"${textFrameDataType}"}`,
              type: 'draft4',
            },
            binary: {
              schema: `{"type":"${binaryFrameDataType}"}`,
              type: 'draft4',
            },
          },
        },
      };

      const resp = await axios({
        method: 'patch',
        url: patchUrl,
        data: pluginPayload,
      });
      logResponse(resp);

      expect(resp.status, 'Status should be 200').to.equal(200);

      await waitForConfigRebuild();
    });

    it('should send boolean for wss', async function () {
      wss = await WebSocket.create(wssProxyUrl, {
        rejectUnauthorized: false,
      });
      wss.send('true');
      await wait(waitTime);

      await wss.on('message', function incoming(data) {
        expect(data).to.equal('true');
      });

      await wss.addEventListener('close', function (data) {
        expect(data.code).to.equal(1005);
      });

      await wss.close();
    });

    it('should send boolean in binary format for wss', async function () {
      wss = await WebSocket.create(wssProxyUrl, {
        rejectUnauthorized: false,
      });
      wss.send('true', { binary: true });
      await wait(waitTime);

      await wss.on('message', (data, isBinary) => {
        const message = isBinary ? data : data.toString();
        expect(message).to.equal('true');
      });

      await wss.addEventListener('close', function (data) {
        expect(data.code).to.equal(1005);
      });

      await wss.close();
    });

    it('should not send non boolean data when plugin is configured for boolean for wss', async function () {
      const myData = 'test_boolean';
      wss = await WebSocket.create(wssProxyUrl, {
        rejectUnauthorized: false,
      });
      wss.send(myData);
      await wait(waitTime);

      await wss.addEventListener('close', function (data) {
        expect(data.code).to.equal(1007);
        expect(data.reason).to.equal('Invalid Frame Payload Data');
      });

      await wss.close();
    });

    it('should be able to patch the plugin with object', async function () {
      textFrameDataType = 'object';
      binaryFrameDataType = 'object';
      const patchUrl = `${url}/${pluginId}`;

      const pluginPayload = {
        ...basePayload,
        config: {
          client: {
            text: {
              schema: `{"type":"${textFrameDataType}"}`,
              type: 'draft4',
            },
            binary: {
              schema: `{"type":"${binaryFrameDataType}"}`,
              type: 'draft4',
            },
          },
        },
      };

      const resp = await axios({
        method: 'patch',
        url: patchUrl,
        data: pluginPayload,
      });
      logResponse(resp);

      expect(resp.status, 'Status should be 200').to.equal(200);

      await waitForConfigRebuild();
    });

    it('should send object for wss', async function () {
      wss = await WebSocket.create(wssProxyUrl, {
        rejectUnauthorized: false,
      });
      wss.send(
        JSON.stringify({
          id: 'client1',
        })
      );
      await wait(waitTime);

      await wss.on('message', function incoming(data) {
        expect(data).to.equal(
          JSON.stringify({
            id: 'client1',
          })
        );
      });

      await wss.addEventListener('close', function (data) {
        expect(data.code).to.equal(1005);
      });

      await wss.close();
    });

    it('should send object in binary format for wss', async function () {
      wss = await WebSocket.create(wssProxyUrl, {
        rejectUnauthorized: false,
      });
      const bjson_arr = [
        123, 34, 107, 101, 121, 34, 58, 34, 118, 97, 108, 117, 101, 34, 125,
      ];

      wss.send(bjson_arr);
      await wait(waitTime);

      await wss.on('message', (data, isBinary) => {
        const message = isBinary ? data : data.toString();
        expect(message).to.equal('{"key":"value"}');
      });

      await wss.addEventListener('close', function (data) {
        expect(data.code).to.equal(1005);
      });

      await wss.close();
    });

    it('should not send non object data when plugin is configured for object for wss', async function () {
      wss = await WebSocket.create(wssProxyUrl, {
        rejectUnauthorized: false,
      });
      wss.send(1245);
      await wait(waitTime);

      await wss.addEventListener('close', function (data) {
        expect(data.code).to.equal(1007);
        expect(data.reason).to.equal('Invalid Frame Payload Data');
      });

      await wss.close();
    });

    after(async function () {
      await deleteGatewayRoute(wssRouteId);
      await deleteGatewayService(wssServiceId);
    });
  });
});
