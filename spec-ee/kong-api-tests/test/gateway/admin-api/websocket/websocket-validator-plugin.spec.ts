import {
  createGatewayService,
  createRouteForService,
  expect,
  logResponse,
  waitForConfigRebuild,
  getGatewayBasePath,
  clearAllKongResources,
} from '@support';
import axios from 'axios';
import WebSocket from 'promise-ws';

describe('Websocket Validator Plugin Tests', function () {
  ['ws', 'wss'].forEach(protocol => {
    let pluginId: string;

    describe(`Tests with "${protocol}" protocol`, function () {
      const echoServer = `${protocol}://websocket-echo-server:${protocol == 'ws' ? 9000 : 9443}/.${protocol}`;
      const adminApi = getGatewayBasePath('admin');
      const proxyUrl = getGatewayBasePath(`${protocol}Proxy`) + '/.' + protocol;

      const basePluginPayload = {
        name: 'websocket-validator',
        service: {
          name: 'test-service',
        },
        route: {
          name: 'test-route',
        },
      };

      const closeWebsocket = async (ws: any, code, reason: string | null = null) => {
        const closed: Promise<any> = new Promise(resolve => ws.addEventListener('close', data => resolve(data)));
        await ws.close();
        const data = await closed;
        expect(data.code).to.equal(code);
        if (reason) {
          expect(data.reason).to.equal(reason);
        }
      };

      before(async function () {
        await clearAllKongResources();

        await createGatewayService('test-service', {
          url: echoServer,
        });

        await createRouteForService('test-service', undefined, {
          name: 'test-route',
          paths: [`/.${protocol}`],
          protocols: [protocol],
        });

        await waitForConfigRebuild();
      });

      it('should send message via ws websocket connection before adding plugin', async function () {
        const ws = await WebSocket.create(proxyUrl, { rejectUnauthorized: false });
        const received = new Promise(resolve => ws.on('message', data => resolve(data)));
        ws.send('345');
        expect(await received).to.equal('345');
        await ws.close();
      });

      it('should be able add websocket validator plugin', async function () {
        const resp = await axios({
          method: 'post',
          url: `${adminApi}/plugins`,
          data: {
            ...basePluginPayload,
            config: {
              client: {
                text: {
                  schema: '{"type":"string"}',
                  type: 'draft4',
                },
                binary: {
                  schema: '{"type":"string"}',
                  type: 'draft4',
                },
              },
            },
          },
        });
        logResponse(resp);

        expect(resp.status, 'Status should be 201').to.equal(201);
        await waitForConfigRebuild();

        pluginId = resp.data.id;
      });

      it('should send string', async function () {
        const ws = await WebSocket.create(proxyUrl, { rejectUnauthorized: false });
        const received = new Promise(resolve => ws.on('message', data => resolve(data)));
        ws.send('"something-ws"');
        expect(await received).to.equal('"something-ws"');
        await ws.close();
      });

      it('should send string in binary format', async function () {
        const ws = await WebSocket.create(proxyUrl, { rejectUnauthorized: false });
        const encoder = new TextEncoder();
        const payloadString = '"something-ws-binary"';
        const buffer = encoder.encode(payloadString);
        const received: Promise<any> = new Promise(resolve => ws.on('message', data => resolve(data)));
        ws.send(buffer);
        const decoder = new TextDecoder();
        const data = decoder.decode(await received);
        expect(data).to.equal(payloadString);
        await ws.close();
      });

      it('should not send non string data', async function () {
        const ws = await WebSocket.create(proxyUrl, { rejectUnauthorized: false });
        await ws.send(5);
        await closeWebsocket(ws, 1007, 'Invalid Frame Payload Data');
      });

      it('should not patch the plugin when schema is not correct ', async function () {
        const resp = await axios({
          validateStatus: null,
          method: 'patch',
          url: `${adminApi}/plugins/${pluginId}`,
          data: {
            config: {
              client: {
                text: {
                  schema: '{"type":"strin**"}',
                  type: 'draft4',
                },
                binary: {
                  schema: '{"type":"strin**"}',
                  type: 'defat4',
                },
              },
            },
          },
        });
        expect(resp.status, 'Status should be 400').to.equal(400);
        expect(resp.data.message, 'should have correct error message').to.contain(`schema violation`);
      });

      it('should be able to patch the plugin with number ', async function () {
        const resp = await axios({
          method: 'patch',
          url: `${adminApi}/plugins/${pluginId}`,
          data: {
            config: {
              client: {
                text: {
                  schema: '{"type":"number"}',
                  type: 'draft4',
                },
                binary: {
                  schema: '{"type":"number"}',
                  type: 'draft4',
                },
              },
            },
          },
          validateStatus: null,
        });
        logResponse(resp);

        expect(resp.status, 'Status should be 200').to.equal(200);
        await waitForConfigRebuild();
      });

      it('should be able to send number', async function () {
        const ws = await WebSocket.create(proxyUrl, { rejectUnauthorized: false });
        const received = new Promise(resolve => ws.on('message', data => resolve(data)));
        ws.send(5);
        expect(await received).to.equal('5');
        await closeWebsocket(ws, 1005);
      });

      it('should send number in binary format ', async function () {
        const ws = await WebSocket.create(proxyUrl, { rejectUnauthorized: false });
        const b_number = Number(235).toString(2);
        const received = new Promise(resolve => ws.on('message', data => resolve(data)));
        ws.send(b_number);
        expect(await received).to.equal('11101011');
        await closeWebsocket(ws, 1005);
      });

      it('should not send non number data when plugin is configured for number', async function () {
        const ws = await WebSocket.create(proxyUrl, { rejectUnauthorized: false });
        ws.send('test');
        await closeWebsocket(ws, 1007, 'Invalid Frame Payload Data');
      });

      it('should be able to patch the plugin with boolean ', async function () {
        const resp = await axios({
          method: 'patch',
          url: `${adminApi}/plugins/${pluginId}`,
          data: {
            config: {
              client: {
                text: {
                  schema: `{"type":"boolean"}`,
                  type: 'draft4',
                },
                binary: {
                  schema: `{"type":"boolean"}`,
                  type: 'draft4',
                },
              },
            },
          },
        });
        logResponse(resp);

        expect(resp.status, 'Status should be 200').to.equal(200);
        await waitForConfigRebuild();
      });

      it('should send boolean', async function () {
        const ws = await WebSocket.create(proxyUrl, { rejectUnauthorized: false });
        const received = new Promise(resolve => ws.on('message', data => resolve(data)));
        ws.send('true');
        expect(await received).to.equal('true');
        await closeWebsocket(ws, 1005);
      });

      it('should send boolean in binary format ', async function () {
        const ws = await WebSocket.create(proxyUrl, { rejectUnauthorized: false });
        const received = new Promise(resolve => ws.on('message', data => resolve(data)));
        ws.send('true', { binary: true });
        expect(await received).to.equalBytes(Buffer.from('true'));
        await closeWebsocket(ws, 1005);
      });

      it('should not send non boolean data when plugin is configured for boolean', async function () {
        const ws = await WebSocket.create(proxyUrl, { rejectUnauthorized: false });
        ws.send('test_boolean');
        await closeWebsocket(ws, 1007, 'Invalid Frame Payload Data');
      });

      it('should be able to patch the plugin with object', async function () {
        const resp = await axios({
          method: 'patch',
          url: `${adminApi}/plugins/${pluginId}`,
          data: {
            config: {
              client: {
                text: {
                  schema: `{"type":"object"}`,
                  type: 'draft4',
                },
                binary: {
                  schema: `{"type":"object"}`,
                  type: 'draft4',
                },
              },
            },
          },
        });
        logResponse(resp);

        expect(resp.status, 'Status should be 200').to.equal(200);
        await waitForConfigRebuild();
      });

      it('should send object', async function () {
        const ws = await WebSocket.create(proxyUrl, { rejectUnauthorized: false });
        const received = new Promise(resolve => ws.on('message', data => resolve(data)));
        const json = JSON.stringify({
          id: 'client1',
        });
        ws.send(json);
        expect(await received).to.equal(json);
        await closeWebsocket(ws, 1005);
      });

      it('should send object in binary format', async function () {
        const ws = await WebSocket.create(proxyUrl, { rejectUnauthorized: false });
        const bjson_arr = [123, 34, 107, 101, 121, 34, 58, 34, 118, 97, 108, 117, 101, 34, 125];
        const received = new Promise(resolve => ws.on('message', data => resolve(data)));
        ws.send(bjson_arr);
        expect(await received).to.equalBytes(Buffer.from('{"key":"value"}'));
        await closeWebsocket(ws, 1005);
      });

      it('should not send non object data when plugin is configured for object', async function () {
        const ws = await WebSocket.create(proxyUrl, { rejectUnauthorized: false });
        ws.send(1245);
        await closeWebsocket(ws, 1007, 'Invalid Frame Payload Data');
      });

      after(clearAllKongResources);
    });
  });
});
