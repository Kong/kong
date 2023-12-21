import axios from 'axios';
import {
  expect,
  getNegative,
  getBasePath,
  Environment,
  createConsumer,
  createBasicAuthCredentialForConsumer,
  deleteConsumer,
  logResponse,
  isGateway,
} from '@support';

describe('Gateway Admin API: Keyring', function () {
  const url = `${getBasePath({
    environment: isGateway() ? Environment.gateway.admin : undefined
  })}/keyring`;
  const basicAuthPassword = 'secretPassword';
  const updatedPassword = 'somenewpassword';
  let firstActiveKeyId: string;
  let newGeneratedKeyId: string;
  let exportedFirstKeyring: string;
  let exportedNewGeneratedKeyring: string;
  let consumerData: any;
  let basicAuthCredentialData: any;

  before(async function () {
    const consumer = await createConsumer();
    consumerData = {
      id: consumer.id,
      username: consumer.username,
      username_lower: consumer.username.toLowerCase(),
    };
  });

  it('should see all key ids', async function () {
    const resp = await axios(url);
    logResponse(resp);

    expect(resp.data.active, 'Should have active key').to.be.string;
    firstActiveKeyId = resp.data.active;

    expect(resp.data.ids, 'should have array of keyring ids').to.be.an('array');
    expect(
      resp.data.ids,
      'should have at least one id in the ids array'
    ).not.to.be.ofSize(0);
    expect(resp.data.ids, 'should contain active keyring id').to.be.containing(
      firstActiveKeyId
    );
  });

  it('should see the active key id', async function () {
    const resp = await axios(`${url}/active`);
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.id, 'should have correct active key').to.equal(
      firstActiveKeyId
    );
  });

  it('should export the keyring', async function () {
    const resp = await axios({
      method: 'POST',
      url: `${url}/export`,
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.data, 'Should have a string keyring').to.be.a.string;
    exportedFirstKeyring = resp.data.data;
  });

  it('should encrypt basic-auth password and not return it during creation', async function () {
    const resp = await createBasicAuthCredentialForConsumer(
      consumerData.username,
      basicAuthPassword
    );
    logResponse(resp);

    expect(resp.status, 'Status should be 201').to.equal(201);
    expect(resp.data.password, 'Should have correct password').to.not.equal(
      basicAuthPassword
    );
    expect(
      resp.data.password,
      'Password should not contain the keyring id'
    ).to.not.contain(firstActiveKeyId);
    expect(
      resp.data.username,
      'Should contain the basic-auth credential username in response'
    ).to.exist;

    basicAuthCredentialData = {
      password: resp.data.password,
      username: resp.data.username,
      id: resp.data.id,
    };
  });

  it('should read back the consumer credential by credential id', async function () {
    // removing /keyring path from the main url
    const resp = await axios(
      `${url.split('/keyring')[0]}/consumers/${
        consumerData.username
      }/basic-auth/${basicAuthCredentialData.id}`
    );
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(
      resp.data.username,
      'Should see the basic-auth username in response'
    ).equal(basicAuthCredentialData.username);
    expect(
      resp.data.password,
      'Should have correct password when reading back consumer data'
    ).to.not.equal(basicAuthPassword);
    expect(
      resp.data.password,
      'Password should not contain the keyring id when reading back consumer data'
    ).to.not.contain(firstActiveKeyId);
  });

  it('should not read back the consumer credential by wrong credential id', async function () {
    // removing /keyring path from the main url
    const resp = await getNegative(
      `${url.split('/keyring')[0]}/consumers/${
        consumerData.username
      }/basic-auth/19e936f5-2ee6-4fd7-9461-2dd7097c6091`
    );
    logResponse(resp);

    expect(resp.status, 'Status should be 404').to.equal(404);
    expect(resp.data.message, 'Should have correct error message').to.equal(
      'Not found'
    );
  });

  it('should generate a new key', async function () {
    // removing /keyring path from the main url
    const resp = await axios({
      method: 'post',
      url: `${url}/generate`,
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 201').to.equal(201);
    expect(resp.data.key, 'Should have a key in response').to.be.a.string;
    expect(resp.data.id, 'Should have an id in response').to.be.a.string;

    newGeneratedKeyId = resp.data.id;
  });

  it('should activate the new key', async function () {
    // removing /keyring path from the main url
    const resp = await axios({
      method: 'post',
      url: `${url}/activate`,
      data: {
        key: newGeneratedKeyId,
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 204').to.equal(204);
  });

  it('should see all keys and the new generated key as active', async function () {
    const resp = await axios(url);
    logResponse(resp);

    expect(resp.data.active, 'Should see the new key as active').to.equal(
      newGeneratedKeyId
    );
    expect(resp.data.ids, 'should have array of keyring ids').to.be.an('array');
    expect(
      resp.data.ids,
      'should have at least one id in the ids array'
    ).to.be.containingAllOf([firstActiveKeyId, newGeneratedKeyId]);
  });

  it('should export the new generated keyring', async function () {
    const resp = await axios({
      method: 'POST',
      url: `${url}/export`,
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.data, 'Should have a string keyring').to.be.a.string;
    exportedNewGeneratedKeyring = resp.data.data;
  });

  it('should import the first exported keyring', async function () {
    const resp = await axios({
      method: 'POST',
      url: `${url}/import`,
      data: {
        data: exportedFirstKeyring,
      },
    });

    logResponse(resp);
    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(
      resp.data.active,
      'Should see the new imported key as active'
    ).to.equal(firstActiveKeyId);
    expect(
      resp.data.ids,
      'should have at least one id in the ids array'
    ).to.be.containingAllOf([firstActiveKeyId, newGeneratedKeyId]);
  });

  it('should rotate the basic-auth credentials after keyring import', async function () {
    const resp = await axios({
      method: 'PATCH',
      url: `${url.split('/keyring')[0]}/consumers/${
        consumerData.username
      }/basic-auth/${basicAuthCredentialData.id}`,
      data: {
        password: updatedPassword,
      },
    });

    logResponse(resp);
    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(
      resp.data.username,
      'Should see the basic-auth username in response after password update'
    ).equal(basicAuthCredentialData.username);
    expect(
      resp.data.id,
      'Should see the basic-auth credential id after password update'
    ).equal(basicAuthCredentialData.id);
    expect(
      resp.data.password,
      'Should not contain old password after update'
    ).to.not.equal(basicAuthPassword);
    expect(
      resp.data.password,
      'Should not contain old hashed password after update'
    ).to.not.equal(basicAuthCredentialData.password);
    expect(
      resp.data.password,
      'Should not contain new password after update'
    ).to.not.equal(updatedPassword);
    expect(
      resp.data.password,
      'Updated password should not contain the keyring id'
    ).to.not.contain(firstActiveKeyId);
  });

  it('should import the 2nd exported key', async function () {
    const resp = await axios({
      method: 'POST',
      url: `${url}/import`,
      data: {
        data: exportedNewGeneratedKeyring,
      },
    });

    logResponse(resp);
    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(
      resp.data.active,
      'Should see the new imported key as active'
    ).to.equal(newGeneratedKeyId);
    expect(
      resp.data.ids,
      'should have at least one id in the ids array'
    ).to.be.containingAllOf([firstActiveKeyId, newGeneratedKeyId]);
  });

  it('should read back the consumer credential after updating the password and importing new keyring', async function () {
    const resp = await axios(
      `${url.split('/keyring')[0]}/consumers/${consumerData.id}/basic-auth/${
        basicAuthCredentialData.id
      }`
    );
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(
      resp.data.username,
      'Should see the basic-auth username in response'
    ).equal(basicAuthCredentialData.username);
    expect(
      resp.data.password,
      'Should not contain old password in response'
    ).to.not.equal(basicAuthPassword);
    expect(
      resp.data.password,
      'Should not contain new password in response'
    ).to.not.equal(updatedPassword);
  });

  after(async function () {
    await deleteConsumer(consumerData.id);
  });
});
