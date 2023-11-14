import axios from 'axios';
import {
  expect,
  getBasePath,
  Environment,
  postNegative,
  randomString,
  createConsumer,
  logResponse,
  createConsumerGroup,
  deleteConsumerGroup,
  createConsumerGroupScopedPlugin,
  addConsumerToConsumerGroup,
  createConsumerGroupSettings,
  createGatewayService,
  createRouteForService,
  createKeyAuthCredentialsForConsumer,
  wait,
  retryRequest,
  removeConsumerFromConsumerGroup,
  waitForConfigRebuild,
  clearAllKongResources,
} from '@support';

describe('Gateway Consumer Groups with RLA', function () {
  this.timeout(45000);

  const url = `${getBasePath({
    environment: Environment.gateway.admin,
  })}/consumer_groups`;

  const proxyUrl = `${getBasePath({
    environment: Environment.gateway.proxy,
  })}`;

  const adminUrl = `${getBasePath({
    environment: Environment.gateway.admin,
  })}`;

  const path = `/${randomString()}`;
  const key = 'apiKey';
  const waitTime = 5000;
  const rtConsumerGroupHeader = 'cgHeader';

  const nonSupportedPlugins = [
    { name: 'key-auth', config: {} },
    { name: 'key-auth-enc', config: {} },
    { name: 'basic-auth', config: {} },
    { name: 'acl', config: { deny: ['test'] } },
  ];

  let rtPluginId: string;
  let consumerGroup1: any;
  let consumer1: any;
  let consumer2: any;
  let serviceId: string;

  before(async function () {
    await clearAllKongResources();
    //  create service and route
    const service = await createGatewayService(randomString());
    serviceId = service.id;
    await createRouteForService(serviceId, [path]);

    // create key-auth-enc plugin for consumer authentication
    const pluginResp = await axios({
      method: 'post',
      url: `${adminUrl}/plugins`,
      data: {
        name: 'key-auth-enc',
      },
    });
    logResponse(pluginResp);
    expect(pluginResp.status, 'Status should be 201').to.equal(201);

    // create consumer 1 and add key-auth-enc credentials to it
    const consumer1Req = await createConsumer();

    consumer1 = {
      id: consumer1Req.id,
      username: consumer1Req.username,
      username_lower: consumer1Req.username.toLowerCase(),
    };

    const consumer1KeyReq = await createKeyAuthCredentialsForConsumer(
      consumer1.id
    );
    consumer1 = { ...consumer1, key: consumer1KeyReq.key };

    // create consumer 2 and add key-auth-enc credentials to it
    const consumer2Req = await createConsumer();

    consumer2 = {
      id: consumer2Req.id,
      username: consumer2Req.username,
      username_lower: consumer2Req.username.toLowerCase(),
    };

    const consumer2KeyReq = await createKeyAuthCredentialsForConsumer(
      consumer2.id
    );
    consumer2 = { ...consumer2, key: consumer2KeyReq.key };

    // create a consumer group
    const consumerGroup1Req = await createConsumerGroup();
    consumerGroup1 = {
      id: consumerGroup1Req.id,
      name: consumerGroup1Req.name,
    };

    // add consumer 1 to consumer group
    await addConsumerToConsumerGroup(consumer1.username, consumerGroup1.id);
  });

  describe('non support plugins', function () {
    let consumerGroup: any;

    beforeEach(async function () {
      consumerGroup = await createConsumerGroup();
    });

    afterEach(async function () {
      await deleteConsumerGroup(consumerGroup.id);
    });

    nonSupportedPlugins.forEach(({ name, config }) => {
      it(`should not create a consumer_group scoped plugin for non-supported plugin ${name}`, async function () {
        const resp = await postNegative(`${url}/${consumerGroup.id}/plugins`, {
          name,
          config,
        });
        logResponse(resp);

        expect(resp.status, 'Status should be 400').to.equal(400);
      });
    });
  });

  it('should create a consumer group scoped plugin with group name', async function () {
    const pluginPayload = {
      name: 'request-transformer-advanced',
      config: {
        add: {
          headers: ['Plugindefaultconfig:pluginConfig'],
        },
      },
    };

    const resp = await createConsumerGroupScopedPlugin(
      consumerGroup1.name,
      pluginPayload
    );

    logResponse(resp);

    expect(
      resp.consumer_group.id,
      'Should see consumer_group id in the response'
    ).to.equal(consumerGroup1.id);
    expect(
      resp.config.add.headers[0],
      'Should see RT plugin header in the response'
    ).to.equal('Plugindefaultconfig:pluginConfig');

    rtPluginId = resp.id;

    await wait(waitTime); // eslint-disable-line no-restricted-syntax
  });

  it('should trigger RT plugin with the correct plugin config', async function () {
    const req = () =>
      axios({
        url: `${proxyUrl}${path}`,
        headers: { [key]: consumer1.key },
      });

    const assertions = (resp) => {
      expect(resp.status, 'Status should be 200').equal(200);
      expect(
        resp.data.headers.Plugindefaultconfig,
        'Should see the correct RT header'
      ).equal('pluginConfig');
    };

    await retryRequest(req, assertions, 20000);
  });

  it('should override RT plugin settings for a consumer group', async function () {
    const pluginSetting = {
      add: {
        headers: [`cg:${rtConsumerGroupHeader}`],
      },
    };
    const resp = await createConsumerGroupSettings(
      consumerGroup1.id,
      'request-transformer',
      rtPluginId,
      pluginSetting
    );

    expect(resp.config.add.headers[0]).to.equal(`cg:${rtConsumerGroupHeader}`);
  });

  it('should apply overwritten RT plugin consumer group settings to a group consumer', async function () {
    await wait(waitTime); // eslint-disable-line no-restricted-syntax

    const req = () =>
      axios({
        url: `${proxyUrl}${path}`,
        headers: { [key]: consumer1.key },
      });

    const assertions = (resp) => {
      expect(resp.status, 'Status should be 200').equal(200);
      expect(resp.data.headers.Cg, 'Should see the correct RT header').equal(
        rtConsumerGroupHeader
      );
      expect(
        resp.data.headers.Plugindefaultconfig,
        'Should not add RT plugin default header'
      ).to.not.exist;
    };

    await retryRequest(req, assertions);
  });

  it('should not apply overwritten RT plugin consumer group settings to a non-group consumer', async function () {
    await wait(waitTime); // eslint-disable-line no-restricted-syntax

    const resp = await axios({
      url: `${proxyUrl}${path}`,
      headers: { [key]: consumer2.key },
    });

    expect(resp.status, 'Status should be 200').equal(200);
    expect(
      resp.data.headers.Cg,
      'Should not add RT default header for non-group consumer'
    ).to.not.exist;
    expect(
      resp.data.headers.Plugindefaultconfig,
      'Should not add RT plugin overwritten header for non-group consumer'
    ).to.not.exist;
  });

  it('should remove consumer 1 and add consumer 2 to the consumer group', async function () {
    await removeConsumerFromConsumerGroup(
      consumer1.username,
      consumerGroup1.id
    );
    await addConsumerToConsumerGroup(consumer2.username, consumerGroup1.name);
  });

  it('should not apply RT plugin CG settings to a consumer1 who was removed from group', async function () {
    await waitForConfigRebuild({ proxyReqHeader: { [key]: consumer1.key } });

    const resp = await axios({
      url: `${proxyUrl}${path}`,
      headers: { [key]: consumer1.key },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').equal(200);
    expect(
      resp.data.headers.Cg,
      'Should not add RT header to a consumer who was removed from the group'
    ).to.not.exist;
    expect(
      resp.data.headers.Plugindefaultconfig,
      'Should not add RT plugin header for a consumer who was removed from the group'
    ).to.not.exist;
  });

  it('should apply RT plugin CG settings to consumer2 who was moved to group 1', async function () {
    const req = () =>
      axios({
        url: `${proxyUrl}${path}`,
        headers: { [key]: consumer2.key },
      });

    const assertions = (resp) => {
      expect(resp.status, 'Status should be 200').equal(200);
      expect(
        resp.data.headers.Cg,
        'Should see the correct RT header after moving to a group'
      ).equal(rtConsumerGroupHeader);
    };

    await retryRequest(req, assertions);
  });

  after(async function () {
    await clearAllKongResources();
  });
});
