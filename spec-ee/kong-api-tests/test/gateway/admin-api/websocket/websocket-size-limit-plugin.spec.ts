import {
  createGatewayService,
  createRouteForService,
  deleteGatewayRoute,
  deleteGatewayService,
  expect,
  randomString,
  logResponse,
  getGatewayBasePath,
  waitForConfigRebuild,
} from '@support';
import axios from 'axios';
import WebSocket from 'promise-ws';

describe('Websocket Size Limit Plugin Tests', function () {
  const adminApi = getGatewayBasePath('admin');

  ['ws', 'wss'].forEach(protocol => {
    const echoServer = `${protocol}://websocket-echo-server:${protocol == 'ws' ? 9000 : 9443}/.ws`;

    describe(`Tests with "${protocol}" protocol using ${echoServer}`, function () {
      const proxyUrl = getGatewayBasePath(`${protocol}Proxy`) + `/.${protocol}`;

      const servicePayload = {
        name: randomString(),
        url: echoServer,
      };

      const routePayload = {
        name: randomString(),
        paths: [`/.${protocol}`],
        protocols: [protocol],
      };

      let serviceId: string;
      let routeId: string;
      let pluginBasePayload: any;
      let pluginId: string;
      let server: any;

      before(async function () {
        const service = await createGatewayService(servicePayload.name, servicePayload);
        serviceId = service.id;

        const route = await createRouteForService(serviceId, undefined, routePayload);
        routeId = route.id;

        pluginBasePayload = {
          name: 'websocket-size-limit',
          service: {
            id: serviceId,
          },
          route: {
            id: routeId,
          },
        };

        await waitForConfigRebuild({ interval: 1000, timeout: 120000 });
      });

      it('should be able to add websocket size limit plugin', async function () {
        const resp = await axios({
          method: 'post',
          url: `${adminApi}/plugins`,
          data: {
            ...pluginBasePayload,
            config: {
              client_max_payload: 42,
              upstream_max_payload: 1000,
            },
          },
        });
        logResponse(resp);

        expect(resp.status, 'Status should be 201').to.equal(201);
        pluginId = resp.data.id;
        await waitForConfigRebuild({ interval: 1000 });
      });

      it('should send message when the size is below the limit', async function () {
        const websocket = await WebSocket.create(proxyUrl, {
          rejectUnauthorized: false,
        });

        const received = new Promise(resolve => websocket.on('message', data => resolve(data)));

        await websocket.send('345');
        const data = await received;
        expect(data).to.equal('345');
        await websocket.close();
      });

      it('should be able to patch the plugin with client payload size limited', async function () {
        const client_max_payload = 3;
        const resp = await axios({
          method: 'patch',
          url: `${adminApi}/plugins/${pluginId}`,
          data: {
            ...pluginBasePayload,
            config: {
              client_max_payload,
              upstream_max_payload: 400,
            },
          },
        });
        logResponse(resp);

        expect(resp.status, 'Status should be 200').to.equal(200);

        const checkResponse = await axios({
          url: `${adminApi}/plugins/${pluginId}`,
        });
        expect(checkResponse.data.config.client_max_payload).to.equal(client_max_payload);

        await waitForConfigRebuild({ interval: 1000 });
      });

      it('should not send data when size is limited', async function () {
        const websocket = await WebSocket.create(proxyUrl, {
          rejectUnauthorized: false,
        });

        const closed = new Promise(resolve => websocket.addEventListener('close', data => resolve(data)));

        websocket.on('message', data => console.log('received data', data.length));

        await websocket.send('X'.repeat(11000));
        await websocket.close();
        const data: any = await closed;

        expect(data.code).to.equal(1009);
        expect(data.reason).to.equal('Payload Too Large');
      });

      after(async function () {
        await deleteGatewayRoute(routeId);
        await deleteGatewayService(serviceId);
      });
    });
  });
});
