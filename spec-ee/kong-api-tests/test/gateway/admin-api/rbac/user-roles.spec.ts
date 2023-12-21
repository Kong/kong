import axios from 'axios';
import {
  expect,
  postNegative,
  createRole,
  deleteRole,
  getBasePath,
  Environment,
  randomString,
  createUser,
  deleteUser,
  createRoleEndpointPermission,
  logResponse,
  isGateway,
} from '@support';

describe(`Gateway RBAC: User's Roles`, function () {
  const url = `${getBasePath({
    environment: isGateway() ? Environment.gateway.admin : undefined,
  })}/rbac`;

  const userName = randomString();
  const userToken = randomString();
  const roleName1 = randomString();
  const roleName2 = randomString();
  let role1: any;
  let role2: any;
  let user: any;

  before(async function () {
    //  creating 2 test roles
    const roleResp = await createRole(roleName1);
    role1 = {
      name: roleResp.name,
      id: roleResp.id,
    };

    const roleResp2 = await createRole(roleName2);

    role2 = {
      name: roleResp2.name,
      id: roleResp2.id,
    };

    // creating endpoint permissions for 1st role
    await createRoleEndpointPermission(role1.id, '/services/*');
    await createRoleEndpointPermission(role1.id, '/rbac', 'read', true);

    // creating endpoint permissions for 2nd role
    await createRoleEndpointPermission(role2.id, '/plugins', 'delete');

    // create a test user
    const userResp = await createUser(userName, userToken);

    user = {
      name: userResp.name,
      id: userResp.id,
      token: userResp.user_token,
    };
  });

  it('should list role permissions by role id', async function () {
    const resp = await axios(`${url}/roles/${role1.id}/permissions/`);
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.entities, 'Should not have entity permissions').to.be
      .empty;

    ['create', 'update', 'delete', 'read'].forEach((action) => {
      expect(
        resp.data.endpoints.default['/default/services/*'].actions,
        `Should have correct service permission action for ${action}`
      ).to.deep.include({ [action]: { negative: false } });
    });

    expect(
      resp.data.endpoints.default['/default/rbac'].actions,
      `Should have correct rbac permission actions`
    ).to.deep.include({ read: { negative: true } });
  });

  it('should list role permissions by role name', async function () {
    const resp = await axios(`${url}/roles/${role2.name}/permissions/`);
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.entities, 'Should not have entity permissions').to.be
      .empty;

    expect(
      resp.data.endpoints.default['/default/plugins'].actions,
      `Should have correct rbac permission action metadata`
    ).to.deep.include({ delete: { negative: false } });
  });

  it('should add a role to a user by user id', async function () {
    const resp = await axios({
      method: 'post',
      url: `${url}/users/${user.id}/roles`,
      data: {
        roles: role1.name,
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 201').to.equal(201);
    expect(resp.data.user.name, 'Should see correct user name').to.eq(
      user.name
    );
    expect(resp.data.user.id, 'Should see correct user id').to.eq(user.id);
    expect(resp.data.roles, 'Should see 1 role').to.have.lengthOf(1);
    expect(resp.data.roles[0].name, 'Should see correct role name').to.eq(
      role1.name
    );
    expect(resp.data.roles[0].id, 'Should see correct role id').to.eq(role1.id);
  });

  it('should add a role to a user by user name', async function () {
    const resp = await axios({
      method: 'post',
      url: `${url}/users/${user.name}/roles`,
      data: {
        roles: role2.name,
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 201').to.equal(201);
    expect(resp.data.user.name, 'Should see correct user name').to.eq(
      user.name
    );
    expect(resp.data.roles, 'Should see 2 roles').to.have.lengthOf(2);
    expect(resp.data.roles.map((role) => role.name)).to.include(role2.name);
  });

  it('should not add a role to a user by role id', async function () {
    const resp = await postNegative(
      `${url}/users/${user.name}/roles`,
      {
        roles: role2.id,
      },
      'post'
    );
    logResponse(resp);

    expect(resp.status, 'Status should be 400').to.equal(400);
    expect(resp.data.message, 'Should see correct error message').to.eq(
      `role not found with name '${role2.id}'`
    );
  });

  it('should list user roles', async function () {
    const resp = await axios(`${url}/users/${user.name}/roles`);
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.user.name, 'Should see correct user name').to.eq(
      user.name
    );
    expect(resp.data.user.id, 'Should see correct user id').to.eq(user.id);
    expect(resp.data.roles, 'Should see 2 roles').to.have.lengthOf(2);

    expect(resp.data.roles.map((role) => role.name)).to.have.members([
      role1.name,
      role2.name,
    ]);
  });

  it('should list user permissions', async function () {
    const resp = await axios(`${url}/users/${user.name}/permissions`);
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.endpoints.default).to.include.all.keys(
      '/default/rbac',
      '/default/plugins',
      '/default/services/*'
    );
  });

  it('should delete a role from a user', async function () {
    const resp = await axios({
      method: 'delete',
      url: `${url}/users/${user.name}/roles`,
      data: {
        roles: role1.name,
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 204').to.equal(204);
  });

  it('should list user permissions after deleting a role', async function () {
    const resp = await axios(`${url}/users/${user.name}/permissions`);
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(
      resp.data.endpoints.default['/default/plugins'].actions,
      `Should have correct rbac permission action metadata`
    ).to.deep.include({ delete: { negative: false } });

    expect(resp.data.endpoints.default).to.not.have.all.keys(
      '/default/rbac',
      '/default/services/*'
    );

    // deleting role1 entirely
    await deleteRole(role1.id);
  });

  it('should not add a deleted role to a user', async function () {
    const resp = await postNegative(
      `${url}/users/${user.id}/roles`,
      {
        roles: role1.name,
      },
      'post'
    );
    logResponse(resp);

    expect(resp.status, 'Status should be 400').to.equal(400);
    expect(resp.data.message, 'Should see correct error message').to.eq(
      `role not found with name '${role1.name}'`
    );
  });

  after(async function () {
    await deleteRole(role2.id);
    await deleteUser(user.id);
  });
});
