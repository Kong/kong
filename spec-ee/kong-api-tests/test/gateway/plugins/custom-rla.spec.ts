import {
  createGatewayService,
  createRouteForService,
  deleteGatewayRoute,
  deleteGatewayService,
  Environment,
  expect,
  getBasePath,
  getNegative,
  isGwHybrid,
  logResponse,
  postNegative,
  isGateway,
  waitForConfigRebuild,
  randomString,
  getControlPlaneDockerImage,
  getKongContainerName
} from '@support';
import axios from 'axios';

const kongPackage = getKongContainerName();
const currentDockerImage = getControlPlaneDockerImage();

// skip tests for amazonlinux-2 distribution
((currentDockerImage?.endsWith('amazonlinux-2') || kongPackage.endsWith('amazonlinux-2')) ? describe.skip : describe)('@smoke: Gateway Custom RLA Plugin Tests', function () {
  let basePayload: any;
  let pluginId: string;
  let serviceId: string;
  let routeId: string;

  const path = `/${randomString()}`;
  const isHybrid = isGwHybrid();

  const url = `${getBasePath({
    environment: isGateway() ? Environment.gateway.admin : undefined,
  })}/plugins`;
  const proxyUrl = `${getBasePath({ environment: isGateway() ? Environment.gateway.proxy : undefined })}/${path}`;


  before(async function () {
    const service = await createGatewayService('custom-rla-service');
    serviceId = service.id;
    const route = await createRouteForService(serviceId, [path]);
    routeId = route.id;

    basePayload = {
      name: 'zendesk-rate-limiting-advanced',
      service: {
        id: serviceId,
      },
      route: {
        id: routeId,
      }
    };
  });

  it('should not create custom RLA plugin with missing limit and window size', async function () {
    const resp = await postNegative(url, basePayload);
    logResponse(resp);

    expect(resp.status, 'Status should be 400').to.equal(400);
    expect(resp.data.message, 'Should have correct error message').to.contain(
      '2 schema violations'
    );
  });

  if (isHybrid) {
    it('should not create custom RLA plugin with strategy cluster in hybrid mode', async function () {
      const pluginPayload = {
        ...basePayload,
        config: {
          strategy: 'cluster',
          limit: [52],
          window_size: [52],
          sync_rate: 0,
        },
      };

      const resp = await postNegative(url, pluginPayload);
      logResponse(resp);

      expect(resp.status, 'Status should be 400').to.equal(400);
      expect(resp.data.message, 'Should have correct error message').to.contain(
        "strategy 'cluster' is not supported with Hybrid deployments"
      );
    });
  }

  it('should create custom RLA plugin with correct config', async function () {
    const pluginPayload = {
      ...basePayload,
      config: {
        limit: [1],
        window_size: [3600],
        window_type: 'fixed',
        strategy: 'local',
        disable_soft_limit: true,
      },
    };

    const resp: any = await axios({
      method: 'post',
      url,
      data: pluginPayload,
    });
    logResponse(resp);


    expect(resp.status, 'Status should be 201').to.equal(201);
    expect(resp.data.name, 'Should have correct plugin name').to.equal(
      basePayload.name
    );
    pluginId = resp.data.id;

    expect(pluginId, 'Plugin Id should be a string').to.be.string;
    expect(resp.data.created_at, 'created_at should be a number').to.be.a(
      'number'
    );
    expect(resp.data.enabled, 'Should have enabled=true').to.be.true;
    expect(resp.data.config.sync_rate, 'sync_rate should be -1').to.eq(-1);
    expect(resp.data.config.strategy, 'Should have strategy cluster').to.eq(
      'local'
    );
    expect(
      resp.data.config.window_size,
      'window_size should be 3600'
    ).to.be.equalTo([3600]);
    expect(resp.data.config.limit, 'Should have correct limit').to.be.equalTo([
      1,
    ]);
    expect(resp.data.config.disable_soft_limit, 'Should have disable_soft_limit=true').to.be.true;

    if (resp.data.config.enforce_consumer_groups) {
      console.log('Checking also consumer groups');
      expect(
        resp.data.config.enforce_consumer_groups,
        'Should have consumer groups disabled'
      ).to.be.false;
    }

    await waitForConfigRebuild()
  });

  it('should rate limit on 2nd request when disable_soft_limit is true', async function () {
    for (let i = 0; i < 2; i++) {
      const resp: any = await getNegative(proxyUrl);
      logResponse(resp);

      if (i === 1) {
        expect(resp.status, 'Status should be 429').to.equal(429);
      } else {
        expect(resp.status, 'Status should be 200').to.equal(200);
      }
    }
  });

  it('should patch the custom RLA plugin', async function () {
    const pluginPayload = {
      ...basePayload,
      config: {
        disable_soft_limit: false
      },
    };

    const resp = await postNegative(`${url}/${pluginId}`, pluginPayload, 'patch');
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.config.disable_soft_limit, 'Should have disable_soft_limit=false').to.be.false;

    await waitForConfigRebuild()
  });

  it('should not rate limit when disable_soft_limit is false', async function () {
    for (let i = 0; i < 2; i++) {
      const resp: any = await getNegative(proxyUrl);
      logResponse(resp);

      expect(resp.status, 'Status should be 200').to.equal(200);
    }
  });

  it('should delete the custom RLA plugin', async function () {
    const resp = await axios({
      method: 'delete',
      url: `${url}/${pluginId}`,
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 204').to.equal(204);
  });

  after(async function () {
    await deleteGatewayRoute(routeId);
    await deleteGatewayService(serviceId);
  });
});
