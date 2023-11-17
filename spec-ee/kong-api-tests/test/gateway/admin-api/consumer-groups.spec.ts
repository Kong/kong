import axios from 'axios';
import {
  expect,
  getBasePath,
  Environment,
  getNegative,
  postNegative,
  randomString,
  createConsumer,
  deleteConsumer,
  logResponse,
} from '@support';

describe('Gateway Consumer Groups with RLA', function () {
  const url = `${getBasePath({
    environment: Environment.gateway.admin,
  })}/consumer_groups`;
  const consumerGroup1Name = randomString();
  const consumerGroup2Name = randomString();
  let consumerGroup1: any;
  let consumerGroup2: any;
  let consumer1: any;
  let consumer2: any;

  const assertConsumergroupResponse = (response: any, name: string) => {
    expect(response.id, 'Should have id').to.be.a('string');
    expect(response.name, 'Should have correct name').to.equal(name);
    expect(response.created_at, 'Should have created_at').to.be.a('number');
  };

  before(async function () {
    const consumer1Req = await createConsumer();
    consumer1 = {
      id: consumer1Req.id,
      username: consumer1Req.username,
      username_lower: consumer1Req.username.toLowerCase(),
    };
    const consumer2Req = await createConsumer();
    consumer2 = {
      id: consumer2Req.id,
      username: consumer2Req.username,
      username_lower: consumer2Req.username.toLowerCase(),
    };
  });

  it('should not create a consumer group with empty name', async function () {
    const resp = await postNegative(url, { name: '' });
    logResponse(resp);

    expect(resp.status, 'Status should be 400').to.equal(400);
    expect(resp.data.message, 'Should have correct error message').to.equal(
      'schema violation (name: length must be at least 1)'
    );
    expect(
      resp.data.fields.name,
      'Should have correct error field name'
    ).to.equal('length must be at least 1');
  });

  it('should not create a consumer group without name', async function () {
    const resp = await postNegative(url);
    logResponse(resp);

    expect(resp.status, 'Status should be 400').to.equal(400);
    expect(resp.data.message, 'Should have correct error message').to.equal(
      'schema violation (name: required field missing)'
    );
    expect(
      resp.data.fields.name,
      'Should have correct error field name'
    ).to.equal('required field missing');
  });

  it('should create a consumer group 1', async function () {
    const resp = await axios({
      method: 'post',
      url,
      data: {
        name: consumerGroup1Name,
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 201').to.equal(201);
    assertConsumergroupResponse(resp.data, consumerGroup1Name);

    consumerGroup1 = { id: resp.data.id, name: consumerGroup1Name };
  });

  it('should see the consumer group 1 in groups list', async function () {
    const resp = await axios(url);
    logResponse(resp);
    let found = false;

    expect(
      resp.data,
      'Should not have empty consumer group list'
    ).not.to.be.ofSize(0);

    for (const group of resp.data.data) {
      if (group.id === consumerGroup1.id) {
        expect(
          group.name,
          'Should see the 1st group name in the list'
        ).to.equal(consumerGroup1.name);
        found = true;
      }
    }

    if (!found) {
      throw new Error(
        'The consumer group 1 was not found in consumer groups list'
      );
    }
  });

  it('should not add non-existing consumer to a consumer group', async function () {
    const resp = await postNegative(`${url}/${consumerGroup1.name}/consumers`, {
      consumer: 'nonExisting',
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 404').to.equal(404);
    expect(resp.data.message, 'Should have correct error message').to.eq(
      `Consumer 'nonExisting' not found`
    );
  });

  it('should not add consumer to a non-existing consumer group', async function () {
    const resp = await postNegative(`${url}/wrongGroup/consumers`, {
      consumer: consumer1.username,
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 404').to.equal(404);
    expect(resp.data.message, 'Should have correct error message').to.eq(
      `Group 'wrongGroup' not found`
    );
  });

  it('should not add consumer to a consumer group with empty body', async function () {
    const resp = await postNegative(`${url}/${consumerGroup1.name}/consumers`);
    logResponse(resp);

    expect(resp.status, 'Status should be 404').to.equal(400);
    expect(resp.data.message, 'Should have correct error message').to.eq(
      'must provide consumer'
    );
  });

  it('should add consumer 1 to consumer group 1 using consumer_groups endpoint', async function () {
    const resp = await axios({
      method: 'post',
      url: `${url}/${consumerGroup1.name}/consumers`,
      data: {
        consumer: consumer1.username,
      },
    });
    logResponse(resp);

    assertConsumergroupResponse(resp.data.consumer_group, consumerGroup1.name);
    expect(resp.status, 'Status should be 201').to.equal(201);
    expect(
      resp.data.consumers[0].username,
      'Should have correct username'
    ).to.eq(consumer1.username);
    expect(
      resp.data.consumers[0].username_lower,
      'Should have correct username_lower'
    ).to.eq(consumer1.username_lower);
    expect(resp.data.consumers[0].id, 'Should have correct consumer id').to.eq(
      consumer1.id
    );
    expect(resp.data.consumers[0].created_at, 'Should have created_at').to.be.a(
      'number'
    );
  });

  it('should not add consumer 1 to consumer group 1 2nd time', async function () {
    const resp = await postNegative(`${url}/${consumerGroup1.name}/consumers`, {
      consumer: consumer1.username,
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 409').to.equal(409);
    expect(resp.data.message, 'Should have correct error message').to.eq(
      `Consumer '${consumer1.username}' already in group '${consumerGroup1.id}'`
    );
  });

  it('should define settings for consumer group 1', async function () {
    const resp = await axios({
      method: 'put',
      url: `${url}/${consumerGroup1.name}/overrides/plugins/rate-limiting-advanced`,
      data: {
        config: {
          limit: [2],
          window_size: [5],
        },
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 201').to.equal(201);
    expect(resp.data.plugin, 'Should have correct plugin name').to.eq(
      'rate-limiting-advanced'
    );
    expect(
      resp.data.consumer_group,
      'Should have correct consumer group name'
    ).to.eq(consumerGroup1.name);
    expect(resp.data.config.limit, 'Should have correct limit').to.be.equalTo([
      2,
    ]);
    expect(
      resp.data.config.window_size,
      'Should have correct window_size'
    ).to.be.equalTo([5]);
  });

  it('should not define settings for a group without limit', async function () {
    const data = {
      config: {
        limit: [2],
      },
    };
    const resp = await postNegative(
      `${url}/${consumerGroup1.name}/overrides/plugins/rate-limiting-advanced`,
      data,
      'put'
    );
    logResponse(resp);

    expect(resp.status, 'Status should be 400').to.equal(400);
    expect(resp.data.message, 'Should have correct error message').to.eq(
      'schema violation (config.window_size: required field missing)'
    );
    expect(
      resp.data.fields.config.window_size,
      'Should have window_size in error'
    ).to.equal('required field missing');
  });

  it('should not define settings for a group without window_size', async function () {
    const data = {
      config: {
        window_size: [2],
      },
    };
    const resp = await postNegative(
      `${url}/${consumerGroup1.name}/overrides/plugins/rate-limiting-advanced`,
      data,
      'put'
    );
    logResponse(resp);

    expect(resp.status, 'Status should be 400').to.equal(400);
    expect(resp.data.message, 'Should have correct error message').to.eq(
      'schema violation (config.limit: required field missing)'
    );
    expect(
      resp.data.fields.config.limit,
      'Should have limit in error'
    ).to.equal('required field missing');
  });

  it('should not define settings for a group with unequal window_size and limit', async function () {
    const data = {
      config: {
        limit: [52, 40],
        window_size: [2],
      },
    };

    const resp = await postNegative(
      `${url}/${consumerGroup1.name}/overrides/plugins/rate-limiting-advanced`,
      data,
      'put'
    );
    logResponse(resp);

    expect(resp.status, 'Status should be 400').to.equal(400);
    expect(resp.data.message, 'Should have correct error message').to.contain(
      'You must provide the same number of windows and limits'
    );
    expect(
      resp.data.fields['@entity'][0],
      'Should have limit in error'
    ).to.equal('You must provide the same number of windows and limits');
  });

  it('should not define settings for a group with unequal limit and window_size', async function () {
    const data = {
      config: {
        limit: [52, 59],
        window_size: [10, 20, 30],
      },
    };

    const resp = await postNegative(
      `${url}/${consumerGroup1.name}/overrides/plugins/rate-limiting-advanced`,
      data,
      'put'
    );
    logResponse(resp);

    expect(resp.status, 'Status should be 400').to.equal(400);
    expect(resp.data.message, 'Should have correct error message').to.contain(
      'You must provide the same number of windows and limits'
    );
    expect(
      resp.data.fields['@entity'][0],
      'Should have limit in error'
    ).to.equal('You must provide the same number of windows and limits');
  });

  it('should not define settings for a group with non-array limit', async function () {
    const data = {
      config: {
        limit: 52,
        window_size: [10],
      },
    };

    const resp = await postNegative(
      `${url}/${consumerGroup1.name}/overrides/plugins/rate-limiting-advanced`,
      data,
      'put'
    );
    logResponse(resp);

    expect(resp.status, 'Status should be 400').to.equal(400);
    expect(resp.data.message, 'Should have correct error message').to.contain(
      'config.limit: expected an array'
    );
    expect(resp.data.fields.config.limit, 'Should have limit error').to.equal(
      'expected an array'
    );
  });

  it('should not define settings for a group with non-array window_size', async function () {
    const data = {
      config: {
        limit: [52],
        window_size: 10,
      },
    };

    const resp = await postNegative(
      `${url}/${consumerGroup1.name}/overrides/plugins/rate-limiting-advanced`,
      data,
      'put'
    );
    logResponse(resp);

    expect(resp.status, 'Status should be 400').to.equal(400);
    expect(resp.data.message, 'Should have correct error message').to.contain(
      'config.window_size: expected an array'
    );
    expect(
      resp.data.fields.config.window_size,
      'Should have window_size error'
    ).to.equal('expected an array');
  });

  it('should get consumer group 1 specific details', async function () {
    const resp = await axios({
      url: `${url}/${consumerGroup1.name}`,
    });
    logResponse(resp);

    let isConsumer = false;
    let isPlugin = false;

    assertConsumergroupResponse(resp.data.consumer_group, consumerGroup1.name);

    expect(
      resp.data.consumers,
      'Should not have empty consumer group list'
    ).not.to.be.ofSize(0);

    for (const consumer of resp.data.consumers) {
      if (consumer.id === consumer1.id) {
        expect(
          consumer.username,
          'Should see the 1st consumer name in the group details'
        ).to.equal(consumer1.username);
        expect(
          consumer.username_lower,
          'Should have correct username_lower'
        ).to.equal(consumer1.username_lower);
        isConsumer = true;
      }
    }

    if (!isConsumer) {
      throw new Error('The consumer was not found in consumer group 1 details');
    }

    expect(
      resp.data.plugins,
      'Should not have empty consumer group list'
    ).not.to.be.ofSize(0);

    for (const plugin of resp.data.plugins) {
      if (plugin.consumer_group.id === consumerGroup1.id) {
        expect(
          plugin.config.limit,
          'Should have correct limit for the consumer group'
        ).to.be.equalTo([2]);
        expect(
          plugin.config.window_size,
          'Should have correct window_size for the consumer group'
        ).to.be.equalTo([5]);
        expect(
          plugin.config.retry_after_jitter_max,
          'Should have default jitter number'
        ).to.eq(0);
        expect(
          plugin.config.window_type,
          'Should have deafult sliding window_type'
        ).eq('sliding');
        expect(plugin.name, 'Should have correct plugin name').eq(
          'rate-limiting-advanced'
        );
        expect(plugin.id, 'Should have plugin id').to.be.a('string');
        expect(plugin.created_at, 'Should have created_at number').to.be.a(
          'number'
        );
        isPlugin = true;
      }
    }

    if (!isPlugin) {
      throw new Error(
        'The plugin was not found in plugins list of the consumer group 1'
      );
    }
  });

  it('should not get non-existing consumer group specific details', async function () {
    const resp = await getNegative(`${url}/wrong`);
    logResponse(resp);

    expect(resp.status, 'Status should be 404').to.equal(404);
    expect(resp.data.message, 'Should have correct error message').to.equal(
      `Group 'wrong' not found`
    );
  });

  it('should define settings for consumer group 1 with jitter_max', async function () {
    const resp = await axios({
      method: 'put',
      url: `${url}/${consumerGroup1.name}/overrides/plugins/rate-limiting-advanced`,
      data: {
        config: {
          limit: [25, 15],
          window_size: [55, 25],
          retry_after_jitter_max: 10,
        },
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 201').to.equal(201);
    expect(resp.data.plugin, 'Should have correct plugin name').to.eq(
      'rate-limiting-advanced'
    );
    expect(
      resp.data.consumer_group,
      'Should have correct consumer group name'
    ).to.eq(consumerGroup1.name);
    expect(resp.data.config.limit, 'Should have correct limit').to.be.equalTo([
      25, 15,
    ]);
    expect(
      resp.data.config.window_size,
      'Should have correct window_size'
    ).to.be.equalTo([55, 25]);
    expect(
      resp.data.config.retry_after_jitter_max,
      'Should have correct jitter_max'
    ).to.eq(10);
  });

  it('should create a consumer group 2', async function () {
    const resp = await axios({
      method: 'post',
      url,
      data: {
        name: consumerGroup2Name,
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 201').to.equal(201);
    assertConsumergroupResponse(resp.data, consumerGroup2Name);

    consumerGroup2 = { id: resp.data.id, name: consumerGroup2Name };
  });

  it('should add consumer 2 to consumer group 2 using consumers endpoint', async function () {
    const consumerUrl = url.replace(
      '/consumer_groups',
      `/consumers/${consumer2.username}/consumer_groups`
    );

    const resp = await axios({
      method: 'post',
      url: consumerUrl,
      data: {
        group: consumerGroup2.name,
      },
    });
    logResponse(resp);

    expect(
      resp.data.consumer_groups,
      'Should have 1 consumer group in the list'
    ).to.be.ofSize(1);

    assertConsumergroupResponse(
      resp.data.consumer_groups[0],
      consumerGroup2.name
    );

    expect(resp.status, 'Status should be 201').to.equal(201);
    expect(resp.data.consumer.username, 'Should have correct username').to.eq(
      consumer2.username
    );
    expect(
      resp.data.consumer.username_lower,
      'Should have correct username_lower'
    ).to.eq(consumer2.username_lower);
    expect(resp.data.consumer.id, 'Should have correct consumer id').to.eq(
      consumer2.id
    );
    expect(resp.data.consumer.created_at, 'Should have created_at').to.be.a(
      'number'
    );
    expect(resp.data.consumer.custom_id, 'Should have custom_id null').to.be
      .null;
  });

  it('should get all consumer groups of the consumer 1', async function () {
    const consumerUrl = url.replace(
      '/consumer_groups',
      `/consumers/${consumer1.username}/consumer_groups`
    );
    const resp = await axios(consumerUrl);
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(
      resp.data.data,
      'Should belong to only 1 consumer_group'
    ).to.be.ofSize(1);
    expect(
      resp.data.data[0].name,
      'Should have consumer_group 1 name'
    ).to.equal(consumerGroup1.name);
    expect(
      resp.data.data[0].id,
      'Should have consumer_group 1 id'
    ).to.equal(consumerGroup1.id);
  });

  it('should add consumer 1 to consumer group 2 using consumers endpoint', async function () {
    const consumerUrl = url.replace(
      '/consumer_groups',
      `/consumers/${consumer1.username}/consumer_groups`
    );

    const resp = await axios({
      method: 'post',
      url: consumerUrl,
      data: {
        group: consumerGroup2.name,
      },
    });
    logResponse(resp);

    expect(
      resp.data.consumer_groups,
      'Should see 1 consumer group in the list'
    ).to.be.ofSize(1);

    assertConsumergroupResponse(
      resp.data.consumer_groups[0],
      consumerGroup2.name
    );

    expect(resp.status, 'Status should be 201').to.equal(201);
    expect(resp.data.consumer.username, 'Should have correct username').to.eq(
      consumer1.username
    );
    expect(
      resp.data.consumer.username_lower,
      'Should have correct username_lower'
    ).to.eq(consumer1.username_lower);
    expect(resp.data.consumer.id, 'Should have correct consumer id').to.eq(
      consumer1.id
    );
    expect(resp.data.consumer.created_at, 'Should have created_at').to.be.a(
      'number'
    );
    expect(resp.data.consumer.custom_id, 'Should have custom_id null').to.be
      .null;
  });

  it('should delete consumer 1 from all consumer groups', async function () {
    // At this point consumer 2 belongs to consumer group 2
    // consumer 1 belongs to consumer group 1 and 2

    const consumerUrl = url.replace(
      '/consumer_groups',
      `/consumers/${consumer1.username}/consumer_groups`
    );
    const resp = await axios({
      method: 'delete',
      url: consumerUrl,
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 204').to.equal(204);
  });

  it('should not see consumer 1 in none of consumer groups', async function () {
    const consumerUrl = url.replace(
      '/consumer_groups',
      `/consumers/${consumer1.username}/consumer_groups`
    );
    const resp = await axios(consumerUrl);
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.data, 'Should have empty response').to.be.empty;
  });

  it('should not get all consumer groups of a wrong consumer', async function () {
    const consumerUrl = url.replace(
      '/consumer_groups',
      `/consumers/wrong/consumer_groups`
    );
    const resp = await postNegative(consumerUrl);
    logResponse(resp);

    expect(resp.status, 'Status should be 404').to.equal(404);
    expect(resp.data.message, 'Should have correct error message').to.equal(
      `Consumer 'wrong' not found`
    );
  });

  it('should see consumer 2 in consumers list of consumer group 2', async function () {
    const resp = await axios(`${url}/${consumerGroup2.name}/consumers`);
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(
      resp.data.data,
      'Should have 1 consumer in consumers list'
    ).to.be.ofSize(1);
    expect(
      resp.data.data[0].username,
      'Should have correct username'
    ).to.equal(consumer2.username);
    expect(
      resp.data.data[0].username_lower,
      'Should have correct username_lower'
    ).to.equal(consumer2.username_lower);
    expect(resp.data.data[0].id, 'Should have correct id').to.equal(
      consumer2.id
    );
  });

  it('should delete consumer 2 by id from consumer group 2', async function () {
    // At this point only consumer 2 belongs to consumer_group 2

    const consumerUrl = url.replace(
      '/consumer_groups',
      `/consumers/${consumer2.id}/consumer_groups/${consumerGroup2.id}`
    );
    const resp = await axios({
      method: 'delete',
      url: consumerUrl,
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 204').to.equal(204);
  });

  it('should not see consumer 1 in consumers list of consumer group 1', async function () {
    const resp = await axios(`${url}/${consumerGroup1.id}/consumers`);
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.data, 'Should have empty body for consumers').to.be.empty;
  });

  it('should not delete wrong consumer from a target consumer group', async function () {
    const consumerUrl = url.replace(
      '/consumer_groups',
      `/consumers/wrong/consumer_groups/${consumerGroup2.id}`
    );
    const resp = await postNegative(consumerUrl, {}, 'delete');
    logResponse(resp);

    expect(resp.status, 'Status should be 404').to.equal(404);
  });

  it('should not delete a consumer from a non existing consumer group', async function () {
    // At this point only consumer 2 belongs to consumer_group 2

    const consumerUrl = url.replace(
      '/consumer_groups',
      `/consumers/${consumer2.id}/consumer_groups/1c8feded-b71c-4b2e-82d0-60110d4846c4`
    );
    const resp = await postNegative(consumerUrl, {}, 'delete');
    logResponse(resp);

    expect(resp.status, 'Status should be 404').to.equal(404);
  });

  it('should add multiple consumers to consumer group 2', async function () {
    const resp = await axios({
      method: 'post',
      url: `${url}/${consumerGroup2.name}/consumers`,
      data: {
        consumer: [consumer1.username, consumer2.id],
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 201').to.equal(201);
    expect(
      resp.data.consumers,
      'Should have 2 consumers in the group'
    ).to.be.ofSize(2);
    expect(
      resp.data.consumer_group.name,
      'Should have name of consumer group 2'
    ).to.eq(consumerGroup2Name);

    for (const consumer of resp.data.consumers) {
      if (consumer.username === consumer1.username) {
        expect(consumer.username_lower).to.eq(consumer1.username_lower);
      } else if (consumer.username === consumer2.username) {
        expect(consumer.username_lower).to.eq(consumer2.username_lower);
      } else {
        throw new Error(
          `Consumer username for ${JSON.stringify(
            consumer
          )} was not found in the response`
        );
      }
    }
  });

  it('should delete consumer 1 by id from consumer group 2 using groups endpoint', async function () {
    // At this point consumer 1 and 2 belong to consumer group 2
    const resp = await axios({
      method: 'delete',
      url: `${url}/${consumerGroup2.name}/consumers/${consumer1.id}`,
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 204').to.equal(204);
    expect(resp.data, 'Should have empty data in response').to.be.empty;
  });

  it('should delete consumer 2 by name from consumer group 2 using groups endpoint', async function () {
    const resp = await axios({
      method: 'delete',
      url: `${url}/${consumerGroup2.name}/consumers/${consumer2.username}`,
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 204').to.equal(204);
    expect(resp.data, 'Should have empty data in response').to.be.empty;
  });

  it('should see no consumers in consumers list of consumer group 2', async function () {
    const resp = await axios(`${url}/${consumerGroup2.id}/consumers`);
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.data, 'Should have empty data in response').to.be.empty;
  });

  it('should not delete non existing consumer from consumer group 2 using groups endpoint', async function () {
    const resp = await postNegative(
      `${url}/${consumerGroup2.name}/consumers/wrong`,
      {},
      'delete'
    );
    logResponse(resp);

    expect(resp.status, 'Status should be 404').to.equal(404);
    expect(resp.data.message, 'Should have correct error message').to.equal(
      "Consumer 'wrong' not found"
    );
  });

  it('should add the same consumer 1 to 2 groups', async function () {
    const consumerUrl = url.replace(
      '/consumer_groups',
      `/consumers/${consumer1.username}/consumer_groups`
    );

    const resp = await axios({
      method: 'post',
      url: consumerUrl,
      data: {
        group: [consumerGroup1.name, consumerGroup2.id],
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 201').to.equal(201);
    expect(
      resp.data.consumer_groups,
      'Should see 1 consumer group in the list'
    ).to.be.ofSize(2);

    for (const consumerGroup of resp.data.consumer_groups) {
      if (consumerGroup.id === consumerGroup1.id) {
        expect(consumerGroup.name).to.eq(consumerGroup1.name);
      } else if (consumerGroup.id === consumerGroup2.id) {
        expect(consumerGroup.name).to.eq(consumerGroup2.name);
      } else {
        throw new Error(
          `Consumer group name for ${JSON.stringify(
            consumerGroup
          )} was not found in the response`
        );
      }
    }

    expect(resp.data.consumer.username, 'Should have correct username').to.eq(
      consumer1.username
    );
    expect(
      resp.data.consumer.username_lower,
      'Should have correct username_lower'
    ).to.eq(consumer1.username_lower);
    expect(resp.data.consumer.id, 'Should have correct consumer id').to.eq(
      consumer1.id
    );
    expect(resp.data.consumer.created_at, 'Should have created_at').to.be.a(
      'number'
    );
    expect(resp.data.consumer.custom_id, 'Should have custom_id null').to.be
      .null;
  });

  it('should not add the consumer 1 to non-existing group', async function () {
    const consumerUrl = url.replace(
      '/consumer_groups',
      `/consumers/${consumer1.username}/consumer_groups`
    );

    const resp = await postNegative(consumerUrl, {
      group: ['non-existing-group'],
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 404').to.equal(404);
    expect(resp.data.message, 'Should have correct error message').to.equal(
      "Group 'non-existing-group' not found"
    );
  });

  it('should delete the consumer group 1 by id', async function () {
    const resp = await axios({
      method: 'delete',
      url: `${url}/${consumerGroup1.id}`,
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 204').to.equal(204);
  });

  it('should not delete a consumer from non existing consumer group using groups endpoint', async function () {
    const resp = await postNegative(
      `${url}/wrong/consumers/${consumer1.username}`,
      {},
      'delete'
    );
    logResponse(resp);

    expect(resp.status, 'Status should be 404').to.equal(404);
    expect(resp.data.message, 'Should have correct error message').to.equal(
      "Group 'wrong' not found"
    );
  });

  it('should delete the consumer group 2 by name', async function () {
    const resp = await axios({
      method: 'delete',
      url: `${url}/${consumerGroup2.name}`,
    });
    logResponse(resp);
    expect(resp.status, 'Status should be 204').to.equal(204);
  });

  it('should get 204 for deleting non existing consumer group', async function () {
    const resp = await axios({
      method: 'delete',
      url: `${url}/wrong`,
    });
    logResponse(resp);
    expect(resp.status, 'Status should be 204').to.equal(204);
  });

  after(async function () {
    await deleteConsumer(consumer1.id);
    await deleteConsumer(consumer2.id);
  });
});
