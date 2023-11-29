import axios from 'axios';
import {
  expect,
  getNegative,
  postNegative,
  getBasePath,
  Environment,
  createRole,
  deleteRole,
  randomString,
  logResponse,
  waitForConfigRebuild,
  retryRequest,
  eventually,
} from '@support';

describe('@smoke: Gateway RBAC: Role Endpoint Permissions', function () {
  const url = `${getBasePath({
    environment: Environment.gateway.admin,
  })}/rbac/roles`;

  const roleName = randomString();
  const workspaceName = 'default';
  const endpoint1 = '/services';
  const endpoint2 = '/developers/*/applications/*';
  const customEndpoint = '/nonexisting/*/something/*';
  let role: any;

  before(async function () {
    const resp = await createRole(roleName);
    role = {
      name: resp.name,
      id: resp.id,
    };
    await waitForConfigRebuild();
  });

  it('should create a role endpoint permission', async function () {
    const req = () =>
      axios({
        method: 'post',
        url: `${url}/${role.id}/endpoints`,
        data: {
          workspace: workspaceName,
          endpoint: endpoint1,
          negative: false,
          actions: 'read,create',
        },
      });

    const assertions = (resp) => {
      logResponse(resp);

      expect(resp.status, 'Status should be 201').to.equal(201);
      expect(resp.data.role, 'Response should have role id').to.haveOwnProperty(
        'id',
        role.id
      );
      expect(resp.data.workspace, 'Should see correct workspace name').to.eq(
        workspaceName
      );
      expect(resp.data.created_at, 'Should have created_at number').to.be.a(
        'number'
      );
      expect(resp.data.endpoint, 'Should have correct endpoint').to.eq(
        endpoint1
      );
      expect(resp.data.negative, 'Should have negative false').to.be.false;
      expect(resp.data.actions, 'Should have correct actions').to.have.members([
        'create',
        'read',
      ]);
    };

    await waitForConfigRebuild();
    await retryRequest(req, assertions);
  });

  it('should not create an endpoint permission twice', async function () {
    const req = () =>
      postNegative(
        `${url}/${role.id}/endpoints`,
        {
          endpoint: endpoint1,
          actions: 'read,create,update',
        },
        'post'
      );

    const assertions = (resp) => {
      expect(resp.status, 'Status should be 400').to.equal(400);
      expect(resp.data.name, 'Should have correct error name').to.eq(
        'primary key violation'
      );
    };

    await retryRequest(req, assertions);
  });

  it('should not create an endpoint permission without endpoint', async function () {
    const resp = await postNegative(
      `${url}/${role.id}/endpoints`,
      {
        actions: 'read,create',
      },
      'post'
    );
    logResponse(resp);

    expect(resp.status, 'Status should be 400').to.equal(400);
    expect(resp.data.message, 'Should have correct error message').to.eq(
      "'endpoint' is a required field"
    );
  });

  it('should retrieve a role endpoint permission', async function () {
    const resp = await axios(
      `${url}/${role.id}/endpoints/${workspaceName}${endpoint1}`
    );
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.role, 'Response should have role id').to.haveOwnProperty(
      'id',
      role.id
    );
    expect(resp.data.created_at, 'Should have created_at number').to.be.a(
      'number'
    );
    expect(resp.data.workspace, 'Should see correct workspace name').to.eq(
      workspaceName
    );
    expect(resp.data.endpoint, 'Should have correct endpoint').to.eq(endpoint1);
    expect(resp.data.negative, 'Should have negative false').to.be.false;
    expect(resp.data.actions, 'Should have correct actions').to.have.members([
      'create',
      'read',
    ]);
  });

  it('should not retrieve non-existing endpoint permission', async function () {
    const resp = await getNegative(
      `${url}/${role.id}/endpoints/${workspaceName}/plugins`
    );
    logResponse(resp);

    expect(resp.status, 'Status should be 404').to.equal(404);
  });

  it('should update a role endpoint permission', async function () {
    const resp = await axios({
      method: 'patch',
      url: `${url}/${role.id}/endpoints/${workspaceName}${endpoint1}`,
      data: {
        negative: true,
        actions: 'update,delete',
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.role, 'Response should have role id').to.haveOwnProperty(
      'id',
      role.id
    );
    expect(resp.data.created_at, 'Should have created_at number').to.be.a(
      'number'
    );
    expect(resp.data.workspace, 'Should see correct workspace name').to.eq(
      workspaceName
    );
    expect(resp.data.endpoint, 'Should have correct endpoint').to.eq(endpoint1);
    expect(resp.data.negative, 'Should have negative true').to.be.true;
    expect(resp.data.actions, 'Should have updated actions').to.have.members([
      'delete',
      'update',
    ]);
  });

  it('should not update a role endpoint permission with wrong payload', async function () {
    const resp = await postNegative(
      `${url}/${role.id}/endpoints/${workspaceName}${endpoint1}`,
      {
        endpoint: '/acls',
      },
      'patch'
    );
    logResponse(resp);

    expect(resp.status, 'Status should be 404').to.equal(404);
  });

  it('should create a role endpoint permission with wildcard endpoint and actions', async function () {
    const resp = await axios({
      method: 'post',
      url: `${url}/${role.name}/endpoints`,
      data: {
        workspace: workspaceName,
        endpoint: endpoint2,
        negative: true,
        actions: '*',
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 201').to.equal(201);
    expect(resp.data.endpoint, 'Should have correct endpoint').to.eq(endpoint2);
    expect(resp.data.actions, 'Should have correct actions').to.have.members([
      'delete',
      'update',
      'create',
      'read',
    ]);
  });

  it('should list all role endpoint permissions', async function () {
    const resp = await axios(`${url}/${role.id}/endpoints`);
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.data, 'Should have 1 role permission listed').to.be.ofSize(
      2
    );

    expect(
      resp.data.data.map((permission) => permission.endpoint),
      'Should see all endpoint permissions in the list'
    ).to.have.members([endpoint1, endpoint2]);
  });

  it('should delete role endpoint permission by role id', async function () {
    const resp = await axios({
      method: 'delete',
      url: `${url}/${role.id}/endpoints/${workspaceName}${endpoint1}`,
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 204').to.equal(204);
  });

  it('should not retrieve a role endpoint permission after deletion', async function () {
    await eventually(async () => {
      const resp = await getNegative(
        `${url}/${role.id}/endpoints/${workspaceName}${endpoint1}`
      );
      logResponse(resp);
  
      expect(resp.status, 'Status should be 404').to.equal(404);
    });
  });

  it('should not list deleted role endpoint permission', async function () {
    const resp = await axios(`${url}/${role.id}/endpoints`);
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.data, 'Should have 1 role permission listed').to.be.ofSize(
      1
    );

    expect(
      resp.data.data[0].endpoint,
      'Should see only the existing endpoint permission'
    ).to.equal(endpoint2);
  });

  it('should delete role endpoint permission by role name', async function () {
    const resp = await axios({
      method: 'delete',
      url: `${url}/${role.name}/endpoints/${workspaceName}${endpoint2}`,
    });

    expect(resp.status, 'Status should be 204').to.equal(204);
  });

  it('should create a permission with custom endpoint', async function () {
    const resp = await axios({
      method: 'post',
      url: `${url}/${role.id}/endpoints`,
      data: {
        endpoint: customEndpoint,
        actions: 'create',
        comment: 'custom',
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 201').to.equal(201);
    expect(resp.data.endpoint, 'Should have correct endpoint').to.eq(
      customEndpoint
    );
    expect(resp.data.negative, 'Should have negative false').to.be.false;
    expect(resp.data.comment, 'Should have custom comment').to.eq('custom');
    expect(resp.data.actions, 'Should have correct actions').to.eql(['create']);
  });

  it('should delete role custom endpoint permission', async function () {
    const resp = await axios({
      method: 'delete',
      url: `${url}/${role.name}/endpoints/${workspaceName}${customEndpoint}`,
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 204').to.equal(204);
  });

  it('should not retrieve a role custom endpoint permission after deletion', async function () {
    const resp = await getNegative(
      `${url}/${role.id}/endpoints/${workspaceName}${customEndpoint}`
    );
    logResponse(resp);

    expect(resp.status, 'Status should be 404').to.equal(404);
  });

  after(async function () {
    await deleteRole(role.id);
  });
});
