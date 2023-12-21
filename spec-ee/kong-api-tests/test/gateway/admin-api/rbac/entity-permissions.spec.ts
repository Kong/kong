import {
  createGatewayService,
  createRole,
  createRouteForService,
  deleteGatewayRoute,
  deleteGatewayService,
  deleteRole,
  Environment,
  expect,
  getBasePath,
  getNegative,
  postNegative,
  randomString,
  logResponse,
  isGateway,
} from '@support';
import axios from 'axios';

describe('Gateway RBAC: Role Entity Permissions', function () {
  const url = `${getBasePath({
    environment: isGateway() ? Environment.gateway.admin : undefined,
  })}/rbac/roles`;

  const roleName = randomString();
  const serviceName = randomString();
  let role: { name: string; id: string };
  let serviceEntity: { id: string; type: string };
  let routeEntity: { id: string; type: string };

  before(async function () {
    const roleReq = await createRole(roleName);
    role = {
      name: roleReq.name,
      id: roleReq.id,
    };

    const serviceReq = await createGatewayService(serviceName);
    serviceEntity = {
      id: serviceReq.id,
      type: 'services',
    };

    const routeReq = await createRouteForService(serviceEntity.id);
    routeEntity = {
      id: routeReq.id,
      type: 'routes',
    };
  });

  it('should create role service entity permission', async function () {
    const resp = await axios({
      method: 'post',
      url: `${url}/${role.id}/entities`,
      data: {
        entity_id: serviceEntity.id,
        entity_type: serviceEntity.type,
        negative: false,
        actions: 'read,create',
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 201').to.equal(201);
    expect(resp.data.role, 'Response should have role id').to.haveOwnProperty(
      'id',
      role.id
    );
    expect(resp.data.comment, 'Should not see comment').to.not.exist;
    expect(resp.data.entity_type, 'Should see correct entity_type').to.eq(
      serviceEntity.type
    );
    expect(resp.data.entity_id, 'Should see correct entity_id').to.eq(
      serviceEntity.id
    );
    expect(resp.data.negative, 'Should have negative false').to.be.false;
    expect(resp.data.actions, 'Should have correct actions').to.have.members([
      'create',
      'read',
    ]);
  });

  it('should not create role service entity permission twice', async function () {
    const resp = await postNegative(
      `${url}/${role.id}/entities`,
      {
        entity_id: serviceEntity.id,
        entity_type: serviceEntity.type,
        negative: true,
        actions: 'delete',
      },
      'post'
    );
    logResponse(resp);

    expect(resp.status, 'Status should be 400').to.equal(400);
    expect(resp.data.name, 'Error should mention repeated add').to.equal(
      'primary key violation'
    );
  });

  it('should not create role entity permission without entity_id', async function () {
    const resp = await postNegative(
      `${url}/${role.id}/entities`,
      {
        entity_id: serviceEntity.id,
        negative: false,
        actions: 'read,create',
      },
      'post'
    );
    logResponse(resp);

    expect(resp.status, 'Status should be 400').to.equal(400);
    expect(resp.data.message, 'Should have correct error message').to.eq(
      "Missing required parameter: 'entity_type'"
    );
  });

  it('should not create role entity permission without entity_type', async function () {
    const resp = await postNegative(
      `${url}/${role.id}/entities`,
      {
        entity_type: serviceEntity.type,
        negative: false,
        actions: 'read,create',
      },
      'post'
    );
    logResponse(resp);

    expect(resp.status, 'Status should be 400').to.equal(400);
    expect(resp.data.message, 'Should have correct error message').to.eq(
      "Missing required parameter: 'entity_id'"
    );
  });

  it('should retrieve role entity permission', async function () {
    const resp = await axios(`${url}/${role.id}/entities/${serviceEntity.id}`);
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.entity_type, 'Should see correct entity_type').to.eq(
      serviceEntity.type
    );
    expect(resp.data.entity_id, 'Should see correct entity_id').to.eq(
      serviceEntity.id
    );
    expect(resp.data.negative, 'Should have negative false').to.be.false;
    expect(resp.data.actions, 'Should have correct actions').to.have.members([
      'create',
      'read',
    ]);
  });

  it('should update role entity permission', async function () {
    const resp = await axios({
      method: 'patch',
      url: `${url}/${role.id}/entities/${serviceEntity.id}`,
      data: {
        negative: true,
        actions: '*',
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.negative, 'Should have negative false').to.be.true;
    expect(resp.data.actions, 'Should have correct actions').to.have.members([
      'create',
      'read',
      'update',
      'delete',
    ]);
  });

  it('should not update role entity permission type and id', async function () {
    const resp = await postNegative(
      `${url}/${role.id}/entities/${serviceEntity.id}`,
      {
        entity_id: routeEntity.id,
        entity_type: routeEntity.type,
        negative: true,
        actions: '*',
      },
      'patch'
    );
    logResponse(resp);

    expect(resp.status, 'Status should be 404').to.equal(404);
  });

  it('should create role route entity permission with wildcard actions', async function () {
    const resp = await axios({
      method: 'post',
      url: `${url}/${role.id}/entities`,
      data: {
        entity_id: routeEntity.id,
        entity_type: routeEntity.type,
        negative: true,
        actions: '*',
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 201').to.equal(201);
    expect(resp.data.role, 'Response should have role id').to.haveOwnProperty(
      'id',
      role.id
    );
    expect(resp.data.entity_type, 'Should see correct entity_type').to.eq(
      routeEntity.type
    );
    expect(resp.data.entity_id, 'Should see correct entity_id').to.eq(
      routeEntity.id
    );
    expect(resp.data.negative, 'Should have negative true').to.be.true;
    expect(resp.data.actions, 'Should have correct actions').to.have.members([
      'create',
      'read',
      'update',
      'delete',
    ]);
  });

  it('should list all role entity permissions', async function () {
    const resp = await axios(`${url}/${role.name}/entities`);
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.data, 'Should have 2 role permission listed').to.be.ofSize(
      2
    );

    expect(
      resp.data.data.map((permission) => permission.entity_type),
      'Should see route and service permissions in the list'
    ).to.have.members([serviceEntity.type, routeEntity.type]);
  });

  it('should delete role entity permission by role id', async function () {
    const resp = await axios({
      method: 'delete',
      url: `${url}/${role.id}/entities/${serviceEntity.id}`,
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 204').to.equal(204);
  });

  it('should not retrieve role entity permission after deletion', async function () {
    const resp = await getNegative(
      `${url}/${role.id}/entities/${serviceEntity.id}`
    );
    logResponse(resp);

    expect(resp.status, 'Status should be 404').to.equal(404);
  });

  it('should not see deleted entity permission in the list', async function () {
    const resp = await axios(`${url}/${role.name}/entities`);
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.data, 'Should have 1 role permission listed').to.be.ofSize(
      1
    );

    expect(
      resp.data.data.map((permission) => permission.entity_id),
      'Should see only route permission in the list'
    ).to.have.members([routeEntity.id]);
  });

  it('should delete role entity permission by role name', async function () {
    const resp = await axios({
      method: 'delete',
      url: `${url}/${role.name}/entities/${routeEntity.id}`,
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 204').to.equal(204);
  });

  it('should create role wildcard entity permission', async function () {
    const resp = await axios({
      method: 'post',
      url: `${url}/${role.id}/entities`,
      data: {
        entity_id: '*',
        entity_type: '*',
        negative: false,
        actions: 'read,create',
        comment: 'my comment',
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 201').to.equal(201);
    expect(resp.data.entity_type, 'Should see correct entity_type').to.eq(
      'wildcard'
    );
    expect(resp.data.entity_id, 'Should see correct entity_id').to.eq('*');
    expect(resp.data.comment, 'Should see comment').to.eq('my comment');
    expect(resp.data.actions, 'Should have correct actions').to.have.members([
      'create',
      'read',
    ]);
  });

  after(async function () {
    await deleteRole(role.id);
    await deleteGatewayRoute(routeEntity.id);
    await deleteGatewayService(serviceEntity.id);
  });
});
