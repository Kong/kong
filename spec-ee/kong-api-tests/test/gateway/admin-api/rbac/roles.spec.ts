import axios from 'axios';
import {
  expect,
  getNegative,
  getBasePath,
  Environment,
  randomString,
  logResponse,
  isGateway,
} from '@support';

describe('Gateway RBAC: Roles', function () {
  const url = `${getBasePath({
    environment: isGateway() ? Environment.gateway.admin : undefined,
  })}/rbac/roles`;

  const role1Name = 'role1';
  const role1UpdatedName = 'role1updated';
  const role2Name = 'role2';
  const role2UpdatedName = 'role1updated';
  const customId = '43cc6549-f625-4bae-a150-5fc23e0665cb';
  const customName = randomString();
  let role1Id: string;
  let role2Id: string;

  it('should create a role', async function () {
    const resp = await axios({
      method: 'post',
      url,
      data: {
        name: role1Name,
        comment: 'My role',
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 201').to.eq(201);
    expect(resp.data.comment, 'Should have correct comment').to.eq('My role');
    expect(resp.data.created_at, 'Should have created_at number').to.be.a(
      'number'
    );
    expect(resp.data.name, 'Should have correct name').to.eq(role1Name);
    expect(resp.data.id, 'Should have id').to.be.a.string;
    role1Id = resp.data.id;
  });

  it('should retreive a role by id', async function () {
    const resp = await axios(`${url}/${role1Id}`);
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.eq(200);
    expect(resp.data.name, 'Should have correct name').to.eq(role1Name);
    expect(resp.data.id, 'Should have correct id').to.eq(role1Id);
  });

  it('should create a role using put request', async function () {
    const resp = await axios({
      method: 'put',
      url: `${url}/${role2Name}`,
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.eq(200);
    expect(resp.data.comment, 'Should have null as comment').to.be.null;
    expect(resp.data.created_at, 'Should have created_at number').to.be.a(
      'number'
    );
    expect(resp.data.name, 'Should have correct name').to.eq(role2Name);
    expect(resp.data.id, 'Should have id').to.be.a.string;
    role2Id = resp.data.id;
  });

  it('should retreive a role by name', async function () {
    const resp = await axios(`${url}/${role2Name}`);
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.eq(200);
    expect(resp.data.name, 'Should have correct name').to.eq(role2Name);
    expect(resp.data.id, 'Should have correct id').to.eq(role2Id);
  });

  it('should update a role name and comment', async function () {
    const resp = await axios({
      method: 'patch',
      url: `${url}/${role1Name}`,
      data: {
        name: role1UpdatedName,
        comment: 'comment from patch',
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.eq(200);
    expect(resp.data.comment, 'Should have null as comment').to.eq(
      'comment from patch'
    );
    expect(resp.data.name, 'Should have correct name').to.eq(role1UpdatedName);
    expect(resp.data.id, 'Should have id').to.eq(role1Id);
  });

  it('should see all roles', async function () {
    const resp = await axios(url);
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.eq(200);
    //  should see total 5 roles, 3 deafult and 2 created
    expect(resp.data.data, 'Should have 5 roles listed').to.be.ofSize(5);

    expect(
      resp.data.data.map((role) => role.name),
      'Should see role1 name in the list'
    ).to.include(role1UpdatedName);
    expect(
      resp.data.data.map((role) => role.name),
      'Should see role2 name in the list'
    ).to.include(role2Name);
  });

  it('should delete a role by id', async function () {
    const resp = await axios({
      method: 'delete',
      url: `${url}/${role1Id}`,
    });

    expect(resp.status, 'Status should be 204').to.eq(204);
  });

  it('should not retreive a deleted role', async function () {
    const resp = await getNegative(`${url}/${role1Id}`);

    expect(resp.status, 'Status should be 404').to.eq(404);
  });

  it('should update a role using put request', async function () {
    const resp = await axios({
      method: 'put',
      url: `${url}/${role2Id}`,
      data: {
        name: role2UpdatedName,
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.eq(200);
    expect(resp.data.name, 'Should have correct name').to.eq(role2UpdatedName);
    expect(resp.data.id, 'Should have id').to.eq(role2Id);
  });

  it('should not see deleted role in roles list', async function () {
    const resp = await axios(url);
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.eq(200);
    //  should see total 4 roles, 3 deafult and 1 created
    expect(resp.data.data, 'Should have 4 roles listed').to.be.ofSize(4);

    expect(
      resp.data.data.map((role) => role.name),
      'Should see updated role2 name in the list'
    ).to.include(role2UpdatedName);
    expect(
      resp.data.data.map((role) => role.id),
      'Should see role2 id in the list'
    ).to.include(role2Id);
  });

  it('should delete a role by name', async function () {
    const resp = await axios({
      method: 'delete',
      url: `${url}/${role1UpdatedName}`,
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 204').to.eq(204);
  });

  it(`should create a role using put request if given primary key doesn't exist`, async function () {
    const resp = await axios({
      method: 'put',
      url: `${url}/${customId}`,
      data: {
        name: customName,
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.eq(200);
    expect(resp.data.id, 'Should have correct id').to.eq(customId);
    expect(resp.data.name, 'Should have correct name').to.eq(customName);

    const delResp = await axios({
      method: 'delete',
      url: `${url}/${customId}`,
    });
    logResponse(delResp);

    expect(delResp.status, 'Status should be 204').to.eq(204);
  });
});
