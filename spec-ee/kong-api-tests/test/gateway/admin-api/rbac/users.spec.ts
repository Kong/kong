import axios from 'axios';
import {
  expect,
  getNegative,
  postNegative,
  getBasePath,
  Environment,
  logResponse,
  isGateway,
} from '@support';

describe('@smoke: Gateway RBAC: Users', function () {
  const url = `${getBasePath({
    environment: isGateway() ? Environment.gateway.admin : undefined,
  })}/rbac/users`;

  const user1Name = 'user1';
  const user1UpdatedName = 'user1updated';
  const user1Token = 'rbac1';
  const user2Name = 'user2';
  const user2Token = 'rbac2';
  let user1Id: string;
  let user2Id: string;

  it('should create a user', async function () {
    const resp = await axios({
      method: 'post',
      url,
      data: {
        name: user1Name,
        user_token: user1Token,
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 201').to.equal(201);
    expect(resp.data.comment, 'Comment should be null').to.be.null;
    expect(resp.data.user_token, 'Should have user_token').to.be.string;
    expect(
      resp.data.user_token,
      'Should have encrypted user_token'
    ).to.not.contain(user1Token);
    expect(resp.data.user_token_ident, 'Should have user_token_ident').to.be.a
      .string;
    expect(resp.data.enabled, 'Should be enabled by default').to.be.true;
    expect(resp.data.name, 'Should have correct user name').to.eq(user1Name);
    expect(resp.data.created_at).to.be.a('number');

    user1Id = resp.data.id;
  });

  it('should not create a user without token', async function () {
    const resp = await postNegative(
      url,
      {
        name: 'someUsername',
      },
      'post'
    );
    logResponse(resp);

    expect(resp.status, 'Status should be 400').to.equal(400);
    expect(resp.data.name, 'Should have correct error name').to.equal(
      'schema violation'
    );
    expect(resp.data.message, 'Should have correct message').to.contain(
      'schema violation (user_token:'
    );
    expect(
      resp.data.fields,
      'Should have correct violated fields'
    ).to.haveOwnProperty('user_token', 'required field missing');
  });

  it('should not create a user without name', async function () {
    const resp = await postNegative(
      url,
      {
        user_token: 'mytoken',
      },
      'post'
    );
    logResponse(resp);

    expect(resp.status, 'Status should be 400').to.equal(400);
    expect(resp.data.name, 'Should have correct error name').to.equal(
      'schema violation'
    );
    expect(resp.data.message, 'Should have correct message').to.contain(
      'schema violation (name:'
    );
    expect(
      resp.data.fields,
      'Should have correct violated fields'
    ).to.haveOwnProperty('name', 'required field missing');
  });

  it('should geta a user by id', async function () {
    const resp = await axios(`${url}/${user1Id}`);
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.enabled, 'Should be enabled by default').to.be.true;
    expect(resp.data.name, 'Should have correct user name').to.eq(user1Name);
    expect(resp.data.id, 'Should have correct user id').to.equal(user1Id);
  });

  it('should not get a user by wrong id', async function () {
    const resp = await getNegative(
      `${url}/0cb764cd-0b2f-4956-b7f2-c3cb60c55907`
    );
    logResponse(resp);

    expect(resp.status, 'Status should be 404').to.equal(404);
  });

  it('should update the user', async function () {
    const resp = await axios({
      method: 'patch',
      url: `${url}/${user1Id}`,
      data: {
        name: user1UpdatedName,
        user_token: 'updatedToken',
        comment: 'A new comment',
        enabled: false,
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.name, 'Should update user name').to.eq(user1UpdatedName);
    expect(resp.data.enabled, 'User should be disabled').to.be.false;
    expect(resp.data.id, 'Should have correct user id').to.equal(user1Id);
    expect(resp.data.comment, 'Should have updated comment').to.equal(
      'A new comment'
    );
    expect(resp.data.id, 'Should have updated user token').to.not.eq(
      user1Token
    );
  });

  it('should not update a wrong user with wrong name', async function () {
    const resp = await postNegative(
      `${url}/wrongName`,
      {
        user_token: 'newToken',
        comment: 'A new comment for wrong user',
      },
      'patch'
    );
    logResponse(resp);

    expect(resp.status, 'Status should be 404').to.equal(404);
  });

  it('should create a user with enabled false', async function () {
    const resp = await axios({
      method: 'post',
      url,
      data: {
        name: user2Name,
        user_token: user2Token,
        enabled: false,
        comment: 'comment',
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 201').to.equal(201);
    expect(resp.data.comment, 'Comment should be null').to.eq('comment');
    expect(resp.data.enabled, 'Should not be enabled').to.be.false;
    expect(resp.data.name, 'Should have correct user name').to.eq(user2Name);
    expect(
      resp.data.user_token,
      'Should have encrypted user_token'
    ).to.not.contain(user2Token);

    user2Id = resp.data.id;
  });

  it('should get a user by name', async function () {
    const resp = await axios(`${url}/${user2Name}`);
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.enabled, 'User should be disabled').to.be.false;
    expect(resp.data.name, 'Should have correct user name').to.eq(user2Name);
    expect(resp.data.id, 'Should have correct user id').to.equal(user2Id);
  });

  it('should not get a user by wrong name', async function () {
    const resp = await getNegative(`${url}/wrongName`);
    logResponse(resp);

    expect(resp.status, 'Status should be 404').to.equal(404);
  });

  it('should get all users', async function () {
    const resp = await axios(url);
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.data, 'Should see total 2 users').to.have.lengthOf(2);

    resp.data.data.forEach((user) => {
      expect(user.name, 'Should see all user names').to.equal(
        user.id === user1Id ? user1UpdatedName : user2Name
      );
    });
  });

  it('should delete a user by name', async function () {
    const resp = await axios({
      method: 'delete',
      url: `${url}/${user1UpdatedName}`,
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 204').to.equal(204);
  });

  it('should see correct number of users after deleting one', async function () {
    const resp = await axios(url);
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.data, 'Should see total 2 users').to.have.lengthOf(1);
  });

  it('should delete a user by id', async function () {
    const resp = await axios({
      method: 'delete',
      url: `${url}/${user2Id}`,
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 204').to.equal(204);
  });
});
