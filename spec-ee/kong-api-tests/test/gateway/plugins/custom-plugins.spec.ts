import axios from 'axios';
import {
  expect,
  Environment,
  getBasePath,
  createGatewayService,
  deleteGatewayService,
  randomString,
  deleteGatewayRoute,
  createRouteForService,
  logResponse,
  waitForConfigRebuild,
  postNegative,
  isGateway,
  getGatewayHost,
  getControlPlaneDockerImage,
  getKongContainerName
} from '@support';

const kongPackage = getKongContainerName();
const currentDockerImage = getControlPlaneDockerImage();

// skip custom plugin tests for amazonlinux-2 distro
((currentDockerImage?.endsWith('amazonlinux-2') || kongPackage.endsWith('amazonlinux-2')) ? describe.skip : describe)('@smoke @oss: Gateway Custom Plugins: js-hello, go-hello', function () {
  const url = `${getBasePath({
    environment: isGateway() ? Environment.gateway.admin : undefined,
  })}/plugins`;

  const proxyUrl = `${getBasePath({
    app: 'gateway',
    environment: Environment.gateway.proxy,
  })}`;

  const pluginsData = {
    'js-hello': {
      shortName: 'js',
      fullName: 'Javascript',
      path: '/js-path',
      serviceId: '',
      routeId: ''
    },
    'go-hello': {
      shortName: 'go',
      fullName: 'Go',
      path: '/go-path',
      serviceId: '',
      routeID: ''
    }
  }

  const host = getGatewayHost()

  let message: string;

  ['js-hello', 'go-hello'].forEach(customPlugin => {

    before(async function () {
      const service = await createGatewayService(randomString());
      pluginsData[customPlugin].serviceId = service.id;
      const route = await createRouteForService(pluginsData[customPlugin].serviceId, [pluginsData[customPlugin].path]);
      pluginsData[customPlugin].routeId = route.id;
    });

    if(customPlugin === 'js-hello') {
      // I couldn't figure out how to make the message field mandatory for go plugin
      it(`should not create ${customPlugin} custom plugin with incorrect config`, async function () {
        const payload = {
          name: customPlugin,
          service: {
            id: pluginsData[customPlugin].serviceId,
          },
          route: {
            id: pluginsData[customPlugin].routeId,
          },
        };

        const resp = await postNegative(url, payload );
        logResponse(resp);
        expect(resp.status, 'should see 400 status').to.equal(400);
        expect(resp.data.message, 'should see correct error message').to.contain(
          'schema violation (config.message: required field missing)'
        );
      });
    }

    it(`should not create ${customPlugin} custom plugin for a service without mandatory protocols list`, async function () {
      message = `hey ${customPlugin}`;
      const payload = {
        name: customPlugin,
        service: {
          id: pluginsData[customPlugin].serviceId,
        },
        config: {
          message
        },
        protocols: []
      };

      const resp = await postNegative(url, payload);
      logResponse(resp);
      expect(resp.status, 'should see 400 status').to.equal(400);
    });

    // unskip after https://konghq.atlassian.net/browse/KAG-3948 is fixed
    it.skip(`should not create ${customPlugin} custom plugin globally without mandatory protocols list`, async function () {
      message = `hey ${customPlugin}`;
      const payload = {
        name: customPlugin,
        config: {
          message
        },
        protocols: []
      };

      const resp = await postNegative(url, payload);
      logResponse(resp);
      expect(resp.status, 'should see 400 status').to.equal(400);
    });

    it(`should create ${customPlugin} custom plugin with valid config`, async function () {
      message = `hey ${customPlugin}`;

      const payload = {
        service: {
          id: pluginsData[customPlugin].serviceId,
        },
        route: {
          id: pluginsData[customPlugin].routeId,
        },
        name: customPlugin,
        config: {
          message
        },
      };

      const resp = await axios.post(url, payload);
      expect(resp.status, 'should see 201 status').to.equal(201);
      expect(resp.data.config.message, 'should see correct plugin configuration').to.equal(message);
      expect(resp.data.name, 'should see correct plugin name').to.equal(customPlugin);
      pluginsData[customPlugin].id = resp.data.id;

      await waitForConfigRebuild()
    });

    it(`should see the ${customPlugin} custom plugin in /plugins list`, async function () {
      const resp = await axios(url);
      logResponse(resp);

      expect(resp.status, 'Status should be 200').to.equal(200);
      for (const plugin of resp.data.data) {
        if (plugin.name === customPlugin) {
          expect(plugin.name, 'should see correct plugin name in the plugins list').to.equal(customPlugin);
          expect(plugin.config.message, 'should see correct message in the plugins list').to.equal(message)
          expect(plugin.protocols, 'should see correct protocols list for the plugin').to.have.lengthOf(4)
        }
      }
    });

    it('should send request to upstream and see the custom plugin header', async function () {
      const headerName = `x-hello-from-${pluginsData[customPlugin].fullName.toLowerCase()}`;

      const resp = await axios({
        url: `${proxyUrl}${[pluginsData[customPlugin].path]}`,
      });
      logResponse(resp);

      expect(resp.status, 'Status should be 200').to.equal(200);

      if(customPlugin === 'js-hello') {
        expect(resp.headers['x-javascript-pid']).to.be.a('string');
        expect(resp.headers[headerName], `should see correct header for ${customPlugin}`).to.equal(
          `${pluginsData[customPlugin].fullName} says ${message}`
        );
      } else {
        expect(resp.headers[headerName], `should see correct header for ${customPlugin}`).to.contain(
          `${pluginsData[customPlugin].fullName} says ${message} to ${host}`
        );
      }
    });

    it(`should not patch the ${customPlugin} custom plugin with empty protocols configuration`, async function () {
      const resp = await postNegative(`${url}/${pluginsData[customPlugin].id}`, { protocols: []}, 'patch')

      expect(resp.status, 'Status should be 400').to.equal(400);
      expect(resp.data.message, 'Should see correct error mesasge for protocol schema error').to.contain(`protocols: must match the associated route's protocols`)
    });

    it(`should patch the ${customPlugin} custom plugin message field`, async function () {
      message = `new updated message for ${customPlugin}`;
      const resp = await axios({
        method: 'patch',
        url: `${url}/${pluginsData[customPlugin].id}`,
        data: {
          config: {
            message
          }
        }
      });

      expect(resp.status, 'Status should be 200').to.equal(200);
      expect(resp.data.config.message, 'Should see the updated mesasge configuration field').to.equal(message)

      await waitForConfigRebuild()
    });

    it('should send request to upstream and see the custom plugin header with updated message', async function () {
      const headerName = `x-hello-from-${pluginsData[customPlugin].fullName.toLowerCase()}`;

      const resp = await axios({
        url: `${proxyUrl}${[pluginsData[customPlugin].path]}`,
      });
      logResponse(resp);

      expect(resp.status, 'Status should be 200').to.equal(200);

      if(customPlugin === 'js-hello') {
        expect(resp.headers['x-javascript-pid']).to.be.a('string');
        expect(resp.headers[headerName], `should see correct header for ${customPlugin}`).to.equal(
          `${pluginsData[customPlugin].fullName} says ${message}`
        );
      } else {
        expect(resp.headers[headerName], `should see correct header for ${customPlugin}`).to.contain(
          `${pluginsData[customPlugin].fullName} says ${message} to ${host}`
        );
      }
    });

    it(`should delete the ${customPlugin} custom plugin`, async function () {
      const resp = await axios({
        method: 'delete',
        url: `${url}/${pluginsData[customPlugin].id}`,
      });
      logResponse(resp);

      expect(resp.status, 'Status should be 204').to.equal(204);
    });

    after(async function () {
      await deleteGatewayRoute(pluginsData[customPlugin].routeId);
      await deleteGatewayService(pluginsData[customPlugin].serviceId);
    });
  })
});
