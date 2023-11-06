import { authDetails } from '@fixtures';
import {
  createKeySetsForJweDecryptPlugin,
  Environment,
  expect,
  getBasePath,
  getNegative,
  isGateway,
  logResponse,
  postNegative,
} from '@support';
import axios, { AxiosResponse } from 'axios';

describe('Gateway Admin API: Keys For jwe-decrypt plugin', function () {
  const url = `${getBasePath({
    environment: isGateway() ? Environment.gateway.admin : undefined,
  })}/keys`;
  const keySets = `${getBasePath({
    environment: isGateway() ? Environment.gateway.admin : undefined,
  })}/key-sets`;

  const pemKeySetsName = 'pem-jwe-key-sets';
  const jwkKeySetsName = 'jwk-jwe-key-sets';
  const keysJwkName = 'jwe-key-sets-jwk';
  const keysName = 'jwe-keys';
  const tag1 = 'jwe-tag';
  const jwkRaw = JSON.parse(authDetails.jwe.jwk);

  let pemKeySetsId = String;
  let jwkKeySetsId = String;
  let keysPemId = String;
  let nullKeysPemId = String;
  let keysJwkId = String;
  let keysPayload: any;

  const assertRespDetails = (response: AxiosResponse) => {
    const resp = response.data;
    expect(resp.tags, 'Should not have tags').to.be.null;
    expect(resp.id, 'Should have id of type string').to.be.a('string');
    expect(resp.created_at, 'created_at should be a number').to.be.a('number');
    expect(resp.updated_at, 'updated_at should be a number').to.be.a('number');
  };

  before(async function () {
    const pemKeySets = await createKeySetsForJweDecryptPlugin(pemKeySetsName);
    pemKeySetsId = pemKeySets.id;
    const jwkKeySets = await createKeySetsForJweDecryptPlugin(jwkKeySetsName);
    jwkKeySetsId = jwkKeySets.id;
  });

  it('should not create keys if public key field violates schema', async function () {
    keysPayload = {
      name: keysName,
      set: {
        id: pemKeySetsId,
      },
      pem: {
        private_key: authDetails.jwe.private,
        public_key: authDetails.cert.certificate,
      },
      kid: '42',
    };
    const resp = await postNegative(url, keysPayload);
    logResponse(resp);

    expect(resp.status, 'Status should be 400').equal(400);
    expect(resp.data.name, 'Should be schema violation').to.equal(
      'schema violation'
    );
    expect(
      resp.data.fields.pem,
      'Should indicate public key field is missing'
    ).to.match(/could not load public key.+/);
  });

  it('should not create keys if private key field violates schema', async function () {
    keysPayload = {
      name: keysName,
      set: {
        id: pemKeySetsId,
      },
      pem: {
        public_key: authDetails.jwe.public,
        private_key: authDetails.cert.certificate,
      },
      kid: '42',
    };
    const resp = await postNegative(url, keysPayload);
    logResponse(resp);

    expect(resp.status, 'Status should be 400').equal(400);
    expect(resp.data.name, 'Should be schema violation').to.equal(
      'schema violation'
    );
    expect(
      resp.data.fields.pem,
      'Should indicate private key field is missing'
    ).to.match(/could not load private key.+/);
  });

  it('should not create keys if kid field missing', async function () {
    keysPayload = {
      name: keysName,
      set: {
        id: pemKeySetsId,
      },
      pem: {
        public_key: authDetails.jwe.public,
        private_key: authDetails.jwe.private,
      },
    };
    const resp = await postNegative(url, keysPayload);
    logResponse(resp);

    expect(resp.status, 'Status should be 400').equal(400);
    expect(resp.data.name, 'Should be schema violation').to.equal(
      'schema violation'
    );
    expect(
      resp.data.fields.kid,
      'Should indicate kid field is missing'
    ).to.equal('required field missing');
  });

  it('should not create keys if kid field violates schema', async function () {
    keysPayload = {
      name: keysName,
      set: {
        id: pemKeySetsId,
      },
      pem: {
        public_key: authDetails.jwe.public,
        private_key: authDetails.jwe.private,
      },
      kid: 42,
    };
    const resp = await postNegative(url, keysPayload);
    logResponse(resp);

    expect(resp.status, 'Status should be 400').equal(400);
    expect(resp.data.name, 'Should be schema violation').to.equal(
      'schema violation'
    );
    expect(
      resp.data.fields.kid,
      'Should indicate kid field is missing'
    ).to.equal('expected a string');
  });

  it('should not create keys if jwk field missing', async function () {
    keysPayload = {
      name: keysJwkName,
      set: {
        id: jwkKeySetsId,
      },
      kid: '42',
    };
    const resp = await postNegative(url, keysPayload);
    logResponse(resp);

    expect(resp.status, 'Status should be 400').equal(400);
    expect(resp.data.name, 'Should be schema violation').to.equal(
      'schema violation'
    );
    expect(resp.data.message, 'Should contain "pem" or "jwk"').to.match(
      /pem|jwk/
    );
  });

  it('should not create keys if jwk field violates schema', async function () {
    keysPayload = {
      name: keysJwkName,
      set: {
        id: jwkKeySetsId,
      },
      jwk: jwkRaw,
      kid: '42',
    };
    const resp = await postNegative(url, keysPayload);
    logResponse(resp);

    expect(resp.status, 'Status should be 400').equal(400);
    expect(resp.data.name, 'Should be schema violation').to.equal(
      'schema violation'
    );
    expect(
      resp.data.fields.jwk,
      'Should indicate jwk field requires a string'
    ).to.equal('expected a string');
  });

  it('should not create keys using jwk if jwk and kid values do not match', async function () {
    keysPayload = {
      name: keysJwkName,
      set: {
        id: jwkKeySetsId,
      },
      jwk: authDetails.jwe.jwk,
      kid: '24',
    };
    const resp = await postNegative(url, keysPayload);

    logResponse(resp);
    expect(resp.status, 'Status should be 400').equal(400);
    expect(resp.data.name, 'Should be schema violation').to.equal(
      'schema violation'
    );
    expect(
      resp.data.message,
      'Should indicate kid values must be equal'
    ).to.equal('schema violation (kid in jwk.kid must be equal to keys.kid)');
  });

  it('should create keys if key set field missing', async function () {
    keysPayload = {
      name: 'no-key-set',
      pem: {
        public_key: authDetails.jwe.public,
        private_key: authDetails.jwe.private,
      },
      kid: '47',
    };
    const resp = await axios({
      method: 'post',
      url,
      data: keysPayload,
    });

    logResponse(resp);

    expect(resp.status, 'Status should be 201').equal(201);
    expect(
      resp.data.pem.public_key,
      'Should have public key in the response'
    ).equal(authDetails.jwe.public);
    expect(
      resp.data.pem.private_key,
      'Should have private key in the response'
    ).equal(authDetails.jwe.private);
    expect(resp.data.name, 'Should have correct entity name').equal(
      'no-key-set'
    );
    expect(resp.data.set, 'Should have null value for set value').to.be.null;
    assertRespDetails(resp);
    nullKeysPemId = resp.data.id;
  });

  it('should create keys using pem files', async function () {
    keysPayload = {
      name: keysName,
      set: {
        id: pemKeySetsId,
      },
      pem: {
        public_key: authDetails.jwe.public,
        private_key: authDetails.jwe.private,
      },
      kid: '42',
    };

    const resp = await axios({
      method: 'post',
      url,
      data: keysPayload,
    });

    logResponse(resp);
    expect(resp.status, 'Status should be 201').equal(201);
    expect(
      resp.data.pem.public_key,
      'Should have public key in the response'
    ).equal(authDetails.jwe.public);
    expect(
      resp.data.pem.private_key,
      'Should have private key in the response'
    ).equal(authDetails.jwe.private);
    expect(resp.data.name, 'Should have correct entity name').equal(
      keysPayload.name
    );
    assertRespDetails(resp);
    keysPemId = resp.data.id;
  });

  it('should create keys using jwk', async function () {
    keysPayload = {
      name: keysJwkName,
      set: {
        id: jwkKeySetsId,
      },
      jwk: authDetails.jwe.jwk,
      kid: jwkRaw.kid,
    };

    const resp = await axios({
      method: 'post',
      url,
      data: keysPayload,
    });

    logResponse(resp);
    expect(resp.status, 'Status should be 201').equal(201);
    expect(resp.data.jwk, 'Should have jwk in the response').equal(
      authDetails.jwe.jwk
    );
    expect(resp.data.name, 'Should have correct entity name').equal(
      keysPayload.name
    );
    assertRespDetails(resp);
    keysJwkId = resp.data.id;
  });

  it('should not create pem keys with same name', async function () {
    const resp = await postNegative(url, keysPayload);
    logResponse(resp);

    expect(resp.status, 'Status should be 409').equal(409);
    expect(resp.data.name, 'Should have correct error name').equal(
      'unique constraint violation'
    );
    expect(resp.data.message, 'Should have correct error name').equal(
      `UNIQUE violation detected on '{name="${keysPayload.name}"}'`
    );
  });

  it('should get the pem keys by name', async function () {
    const resp = await axios(`${url}/${keysPayload.name}`);
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.name, 'Should have correct name').equal(keysPayload.name);
    assertRespDetails(resp);
  });

  it('should get the jwk keys by name', async function () {
    const resp = await axios(`${url}/${keysJwkName}`);
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.name, 'Should have correct name').equal(keysJwkName);
    assertRespDetails(resp);
  });

  it('should get the pem keys by id', async function () {
    const resp = await axios(`${url}/${keysPemId}`);
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(
      resp.data.pem.public_key,
      'Should have public key in the response'
    ).equal(authDetails.jwe.public);
    expect(
      resp.data.pem.private_key,
      'Should have private key in the response'
    ).equal(authDetails.jwe.private);
    assertRespDetails(resp);
  });

  it('should get the jwk keys by id', async function () {
    const resp = await axios(`${url}/${keysJwkId}`);
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.jwk, 'Should have jwk in the response').equal(
      authDetails.jwe.jwk
    );
    assertRespDetails(resp);
  });

  it('should get the keys by id', async function () {
    const resp = await axios(`${url}/${nullKeysPemId}`);
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(
      resp.data.pem.public_key,
      'Should have public key in the response'
    ).equal(authDetails.jwe.public);
    expect(
      resp.data.pem.private_key,
      'Should have private key in the response'
    ).equal(authDetails.jwe.private);
    assertRespDetails(resp);
  });

  it('should patch the pem keys', async function () {
    const resp = await axios({
      method: 'patch',
      url: `${url}/${keysPayload.name}`,
      data: {
        tags: [tag1],
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.tags, 'Array Size should equal 1').length(1);
    expect(resp.data.tags[0], 'Single tag should be jwe-tag').to.equal(tag1);
  });

  it('should patch the jwk keys', async function () {
    const resp = await axios({
      method: 'patch',
      url: `${url}/${keysJwkName}`,
      data: {
        tags: [tag1],
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.tags, 'Array Size should equal 1').length(1);
    expect(resp.data.tags[0], 'Single tag should be jwe-tag').to.equal(tag1);
  });

  it('should not get the keys by wrong name', async function () {
    const resp = await getNegative(`${url}/wrong`);
    logResponse(resp);

    expect(resp.status, 'Should have correct error code').to.equal(404);
    expect(resp.data.message, 'Should have correct error message').to.equal(
      'Not found'
    );
  });

  it('should not get the keys by wrong id', async function () {
    const resp = await getNegative(
      `${url}/650d4122-3928-45a1-909d-73921163bb13`
    );
    logResponse(resp);

    expect(resp.status, 'Should respond with error').to.equal(404);
    expect(resp.data.message, 'Should have correct error message').to.equal(
      'Not found'
    );
  });

  it('should delete the jwk key set by name', async function () {
    const resp = await axios({
      method: 'delete',
      url: `${keySets}/${jwkKeySetsName}`,
    });
    logResponse(resp);
    expect(resp.status, 'Status should be 204').to.equal(204);
  });

  it('should delete the pem key set by name', async function () {
    const resp = await axios({
      method: 'delete',
      url: `${keySets}/${pemKeySetsName}`,
    });
    logResponse(resp);
    expect(resp.status, 'Status should be 204').to.equal(204);
  });

  it('should delete the pem keys by name', async function () {
    const resp = await axios({
      method: 'delete',
      url: `${url}/${keysName}`,
    });
    logResponse(resp);
    expect(resp.status, 'Status should be 204').to.equal(204);
  });

  it('should delete the null keys by id', async function () {
    const resp = await axios({
      method: 'delete',
      url: `${url}/${nullKeysPemId}`,
    });
    logResponse(resp);
    expect(resp.status, 'Status should be 204').to.equal(204);
  });

  it('should delete the jwk keys by name', async function () {
    const resp = await axios({
      method: 'delete',
      url: `${url}/${keysJwkName}`,
    });
    logResponse(resp);
    expect(resp.status, 'Status should be 204').to.equal(204);
  });
});
