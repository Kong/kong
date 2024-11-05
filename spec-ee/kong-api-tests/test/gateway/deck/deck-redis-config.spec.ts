import axios from 'axios';
import {
  Environment,
  expect,
  getBasePath,
  logResponse,
  executeDeckCommand,
  getNegative,
  backupJsonFile,
  restoreJsonFile,
  findRegex,
  modifyDeckConfig,
  getGatewayContainerLogs,
  isGateway,
  waitForConfigRebuild,
  getKongContainerName,
  eventually,
} from '@support';


describe('@oss: decK: validate redis legacy and new field deck sync with rate-limiting plugin', function () {

  let backupFilePath: string;
  let currentLogs: any;
  let pluginId: any;

  const kongContainerName = getKongContainerName();
  const deckFileName = 'support/data/deck/redisConfigTest.json';

  const proxyUrl = getBasePath({ environment: isGateway() ? Environment.gateway.proxy : undefined });
  const pluginUrl = `${getBasePath({
    environment: isGateway() ? Environment.gateway.admin : undefined,
  })}/plugins`;

  const redisObject = {
    database: 0,
    host: 'redis',
    password: 'redispassword',
    port: 6379,
    server_name: null,
    ssl: false,
    ssl_verify: false,
    timeout: 2000,
    username: 'redisuser'
  };

  function getIdByName(response: any, pluginName: string): string | null {
    if (response && Array.isArray(response.data)) {
      for (const plugin of response.data) {
        if (plugin.name === pluginName) {
          return plugin.id;
        }
      }
    }
    return null;
  }

  before(async function () {
    backupFilePath = backupJsonFile(`./${deckFileName}`);
  });

  it('should deck sync redis setting with matched legacy and new field successfully', async function () {
    const result = executeDeckCommand(`sync ./${deckFileName}`);
    expect(result.stderr, 'deck sync error').to.be.undefined;
    await waitForConfigRebuild();
  });

  it('should limit request with correct redis setting with matched legacy and new field', async function () {
    for (let i = 0; i < 2; i++) {
      const resp: any = await getNegative(`${proxyUrl}/redisDeckMock`,{'X-Limit-Hit': 'mockPath0'});
      logResponse(resp);

      if (i === 1) {
        expect(resp.status, 'Status should be 429').to.equal(429);
      } else {
        expect(resp.status, 'Status should be 200').to.equal(200);
      }
    }
  });

  it('should deck sync config with only legacy redis fields with wrong redis port successfully', async function () {
    modifyDeckConfig(deckFileName, 'plugins[0].config.redis'); //remove new redis config
    modifyDeckConfig(deckFileName, 'plugins[0].config.redis_port', 6378); //change legacy redis port to wrong
    const result = executeDeckCommand(`sync ./${deckFileName}`);
    expect(result.stderr, 'deck sync error').to.be.undefined;
  });

  it('should see logs warning legacy redis configuration will be deprecated', async function () {
    await eventually(async () => {
      currentLogs = getGatewayContainerLogs(
        kongContainerName, 200
      );

      const isLogFound = findRegex('config.redis_port is deprecated', currentLogs);
      expect(
        isLogFound,
        'Should see redis legacy field deprecated warning log'
      ).to.be.true;
    });
  });

  it('should check with admin api both legacy and new redis fields are correctly set', async function () {
    const resp = await axios({
      method: 'GET',
      url: `${pluginUrl}`,
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    pluginId = getIdByName(resp.data, 'rate-limiting');

    const checkResponse = await axios({
      url: `${pluginUrl}/${pluginId}`,
    });
    expect(checkResponse.data.config.redis.port, 'Should have correct redis port in the API response').to.equal(6378);
    expect(checkResponse.data.config.redis.username, 'Should have matched value for redis.username and redis_username').to.equal(checkResponse.data.config.redis_username);
    expect(checkResponse.data.config.redis.port, 'Should have matched value for redis.port and redis_port').to.equal(checkResponse.data.config.redis_port);
    expect(checkResponse.data.config.redis.ssl, 'Should have matched value for redis.ssl and redis_ssl').to.equal(checkResponse.data.config.redis_ssl);
  });

  it('should not limit request with wrong redis port', async function () {
    await waitForConfigRebuild();
    for (let i = 0; i < 2; i++) {
      const resp = await axios({method: 'get', url: `${proxyUrl}/redisDeckMock`,headers: {'X-Limit-Hit': 'mockPath1'} });
      logResponse(resp);
      expect(resp.status, 'Status should be 200').to.equal(200);
    }
  });

  it('should deck sync config with only new redis fields with correct redis port', async function () {
    const pathsToRemove = [
      'plugins[0].config.redis_database',
      'plugins[0].config.redis_host',
      'plugins[0].config.redis_password',
      'plugins[0].config.redis_port',
      'plugins[0].config.redis_server_name',
      'plugins[0].config.redis_ssl',
      'plugins[0].config.redis_ssl_verify',
      'plugins[0].config.redis_timeout',
      'plugins[0].config.redis_username'
    ];
    modifyDeckConfig(deckFileName, pathsToRemove); //remove legacy redis config
    modifyDeckConfig(deckFileName, 'plugins[0].config.redis', redisObject); //add new redis config

    const result = executeDeckCommand(`sync ./${deckFileName}`);
    expect(result.stderr, 'deck sync error').to.be.undefined;
    await waitForConfigRebuild();
  });

  it('should check with admin api both legacy and new redis fields are correctly set', async function () {
    const checkResponse = await axios({
      url: `${pluginUrl}/${pluginId}`,
    });
    expect(checkResponse.data.config.redis.username).to.equal(checkResponse.data.config.redis_username);
    expect(checkResponse.data.config.redis.port).to.equal(checkResponse.data.config.redis_port);
    expect(checkResponse.data.config.redis.ssl).to.equal(checkResponse.data.config.redis_ssl);
  });

  it('should limit request after change to correct redis port', async function () {
    for (let i = 0; i < 2; i++) {
      const resp: any = await getNegative(`${proxyUrl}/redisDeckMock`, { 'X-Limit-Hit': 'mockPath2' });
      logResponse(resp);

      if (i === 1) {
        expect(resp.status, 'Status should be 429').to.equal(429);
      } else {
        expect(resp.status, 'Status should be 200').to.equal(200);
      }
    }
  });

  it('should not allow mismatched legacy and new redis field setting deck sync', async function () {
    modifyDeckConfig(deckFileName, 'plugins[0].config.redis_username', 'redisWrongUser');//add legacy redis config
    const result = executeDeckCommand(`sync ./${deckFileName}`);
    expect(result.stderr, 'Should see correct error message').to.include(
      'redis_username: both deprecated and new field are used but their values mismatch'
    );
  });

  after(async function () {
    // after test run use deck reset to remove all of the created entities from kong and remove deck file
    executeDeckCommand('reset --force');
    restoreJsonFile(`./${deckFileName}`, backupFilePath);
  });
});
