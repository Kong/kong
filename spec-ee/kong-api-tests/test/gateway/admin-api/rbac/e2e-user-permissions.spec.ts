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
  createGatewayService,
  deleteGatewayService,
  createRouteForService,
  deleteGatewayRoute,
  createUser,
  deleteUser,
  addRoleToUser,
  createRoleEndpointPermission,
  createRoleEntityPermission,
  createPlugin,
  deletePlugin,
  deleteRoleEndpointPermission,
  isGwHybrid,
  wait,
  logResponse,
  retryRequest,
} from '@support';

describe('Gateway RBAC: E2E User Permissions', function () {
  const isHybrid = isGwHybrid();
  const url = `${getBasePath({
    environment: Environment.gateway.admin,
  })}`;

  const updateRoleName = 'rbacUpdatedRoleName';
  const workspaceName = 'default';
  const serviceName = randomString();
  const servicesEndpoint = '/services/*';
  const routesEndpoint = '/routes/*';
  const consumersEndpoint = '/consumers';
  const user = { name: randomString(), token: randomString(), id: '' };
  const userHeader = { 'kong-admin-token': user.token };
  const pluginPayload = {
    name: 'basic-auth',
    config: {
      hide_credentials: true,
    },
  };
  const role = { name: randomString(), id: '' };
  const serviceEntity = { id: '', type: 'services' };
  const routeEntity = { id: '', type: 'routes' };
  let pluginId: string;

  before(async function () {
    //  create service
    const serviceReq = await createGatewayService(serviceName);
    serviceEntity.id = serviceReq.id;

    // create route for the service
    const routeReq = await createRouteForService(serviceEntity.id);
    routeEntity.id = routeReq.id;

    // create a basic-auth plugin
    const pluginReq = await createPlugin(pluginPayload);
    pluginId = pluginReq.id;

    // create role
    const roleReq = await createRole(role.name);
    role.id = roleReq.id;

    // create user
    const userReq = await createUser(user.name, user.token);
    user.id = userReq.id;

    // attach role to a user
    await addRoleToUser(user.name, role.name);

    // create role endpoint permission
    await createRoleEndpointPermission(
      role.id,
      servicesEndpoint,
      'update,delete',
      true
    );
    await createRoleEndpointPermission(role.id, routesEndpoint, 'read', true);
    await createRoleEndpointPermission(role.id, consumersEndpoint, '*');

    // create role entity permission
    await createRoleEntityPermission(role.id, pluginId, 'plugins', 'delete');
  });

  it(`should see all role permissions`, async function () {
    const resp = await axios(`${url}/rbac/roles/${role.id}/permissions`);
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(
      resp.data.endpoints.default[`/default${routesEndpoint}`].actions,
      `Should see read action for route endpoint`
    ).to.deep.include({ read: { negative: true } });

    expect(
      resp.data.endpoints.default[`/default${routesEndpoint}`].actions,
      `Should see no other action than 'read'`
    ).to.not.deep.include({ update: { negative: true } });

    ['update', 'delete'].forEach((action) => {
      expect(
        resp.data.endpoints.default[`/default${servicesEndpoint}`].actions,
        `Should see read action for service endpoint`
      ).to.deep.include({ [action]: { negative: true } });
    });

    expect(
      resp.data.endpoints.default[`/default${servicesEndpoint}`].actions,
      `Should see no other action than 'update, delete'`
    ).to.not.deep.include({ read: { negative: true } });

    ['create', 'update', 'delete', 'read'].forEach((action) => {
      expect(
        resp.data.endpoints.default[`/default${consumersEndpoint}`].actions,
        `Should see action ${action} for consumers endpoint`
      ).to.deep.include({ [action]: { negative: false } });
    });

    expect(
      resp.data.entities[`${pluginId}`].actions,
      'Should see delete action for plugin entity'
    )
      .to.be.ofSize(1)
      .and.have.members(['delete']);
  });

  it('should not have permission to delete the plugin entity', async function () {
    const resp = await postNegative(
      `${url}/plugins/${pluginId}`,
      {},
      'delete',
      userHeader
    );
    logResponse(resp);

    expect(resp.status, 'Status should be 403').to.equal(403);
    expect(resp.data.message, 'Should have correct forbidden message').to.eq(
      `${user.name}, you do not have permissions to delete this resource`
    );
  });

  it('should not have permission to read the route endpoint', async function () {
    const resp = await getNegative(
      `${url}/routes/${routeEntity.id}`,
      userHeader
    );
    logResponse(resp);

    expect(resp.status, 'Status should be 403').to.equal(403);
    expect(resp.data.message, 'Should have correct forbidden message').to.eq(
      `${user.name}, you do not have permissions to read this resource`
    );
  });

  it('should not have permission to update the service endpoint', async function () {
    const resp = await postNegative(
      `${url}/services/${serviceEntity.id}`,
      { name: 'newServiceName' },
      'patch',
      userHeader
    );
    logResponse(resp);

    expect(resp.status, 'Status should be 403').to.equal(403);
    expect(resp.data.message, 'Should have correct forbidden message').to.eq(
      `${user.name}, you do not have permissions to update this resource`
    );
  });

  it('should have permission to read consumers endpoint', async function () {
    const resp = await axios({
      url: `${url}${consumersEndpoint}`,
      headers: userHeader,
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
  });

  it('should have no permission to read endpints other than specified', async function () {
    const resp = await getNegative(`${url}/developers`, userHeader);
    logResponse(resp);

    expect(resp.status, 'Status should be 403').to.equal(403);
  });

  // now patching role permissions to check if those take effect after update
  it('should not see deleted consumers endpoint permission in the list', async function () {
    // removing services endpoint permissions entirely
    let resp = await deleteRoleEndpointPermission(role.id, servicesEndpoint);
    logResponse(resp);
    expect(resp.status, 'Status should be 204').to.equal(204);

    // update consumers endpoint to read only
    resp = await axios({
      method: 'patch',
      url: `${url}/rbac/roles/${role.id}/endpoints/${workspaceName}${consumersEndpoint}`,
      data: {
        actions: 'read',
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);

    // allow reading route endpoint
    resp = await axios({
      method: 'patch',
      url: `${url}/rbac/roles/${role.id}/endpoints/${workspaceName}${routesEndpoint}`,
      data: {
        negative: false,
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);

    // adding read permission to plugin entity
    resp = await axios({
      method: 'patch',
      url: `${url}/rbac/roles/${role.id}/entities/${pluginId}`,
      data: {
        actions: 'read,delete',
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);

    // updating role name
    resp = await axios({
      method: 'put',
      url: `${url}/rbac/roles/${role.id}`,
      data: {
        name: updateRoleName,
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
  });

  it('should see all updates in role permissions', async function () {
    const req = () => axios(`${url}/rbac/roles/${role.id}/permissions`);

    const assertions = (resp) => {
      logResponse(resp);

      expect(
        resp.data.entities[`${pluginId}`].actions,
        'Should see correct actions for plugin entity'
      )
        .to.be.ofSize(2)
        .and.have.members(['delete', 'read']);
      expect(
        resp.data.endpoints.default[`/default${servicesEndpoint}`],
        'Should not have services endpoint'
      ).to.not.exist;

      expect(
        resp.data.endpoints.default[`/default${routesEndpoint}`].actions,
        'Should see negative false for routes endpoint'
      ).to.deep.include({ read: { negative: false } });
    };

    await retryRequest(req, assertions, 10000);
  });

  it('should not delete a service after removing the permission entirely', async function () {
    const resp = await postNegative(
      `${url}/services/${serviceEntity.id}`,
      {},
      'delete',
      userHeader
    );
    logResponse(resp);

    expect(resp.status, 'Status should be 403').to.equal(403);
  });

  it('should have read permission on consumers endpoint', async function () {
    const resp = await axios({
      url: `${url}${consumersEndpoint}`,
      headers: userHeader,
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
  });

  it('should not have update permission on consumers endpoint', async function () {
    const resp = await postNegative(
      `${url}${consumersEndpoint}`,
      { username: 'newName' },
      'patch',
      userHeader
    );
    logResponse(resp);

    expect(resp.status, 'Status should be 403').to.equal(403);
  });

  it('should have permission to read the routes endpoint', async function () {
    const resp = await axios({
      url: `${url}/routes/${routeEntity.id}`,
      headers: userHeader,
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
  });

  it('should update user and have no impact on services endpoint permission', async function () {
    const userNewToken = randomString();

    let resp = await axios({
      method: 'patch',
      url: `${url}/rbac/users/${user.id}`,
      data: {
        name: randomString(),
        user_token: userNewToken,
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(
      resp.data.user_token,
      'Token should be encoded in the response'
    ).to.not.equal(userNewToken);

    user.name = resp.data.name;
    user.token = userNewToken;
    userHeader['kong-admin-token'] = user.token;

    resp = await postNegative(
      `${url}/services/${serviceEntity.id}`,
      {},
      'delete',
      userHeader
    );
    logResponse(resp);

    expect(resp.status, 'Status should be 403').to.equal(403);
    await wait(isHybrid ? 4000 : 100); // eslint-disable-line no-restricted-syntax
  });

  it('should have permission to read the routes endpoint after updating the user token', async function () {
    const resp = await axios({
      url: `${url}/routes/${routeEntity.id}`,
      headers: userHeader,
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
  });

  it('should not have permission to read the routes endpoint after deleting the role', async function () {
    await deleteRole(role.id);

    const resp = await getNegative(
      `${url}/routes/${routeEntity.id}`,
      userHeader
    );
    logResponse(resp);

    expect(resp.status, 'Status should be 403').to.equal(403);
  });

  it('should not have update permission on consumers endpoint after deleting the role', async function () {
    const resp = await postNegative(
      `${url}${consumersEndpoint}`,
      { username: 'newName' },
      'patch',
      userHeader
    );
    logResponse(resp);

    expect(resp.status, 'Status should be 403').to.equal(403);
  });

  after(async function () {
    await deleteUser(user.id);
    await deletePlugin(pluginId);
    await deleteGatewayRoute(routeEntity.id);
    await deleteGatewayService(serviceEntity.id);
  });
});
