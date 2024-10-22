import axios from 'axios';
import {
  expect,
  Environment,
  getBasePath,
  postNegative,
  createGatewayService,
  createRouteForService,
  createConsumer,
  createConsumerGroup,
  clearAllKongResources,
  randomString,
  logResponse,
  checkFileExistsInDockerContainer,
  deleteFileFromDockerContainer,
  copyFileFromDockerContainer,
  createFileInDockerContainer,
  deleteTargetFile,
  getTargetFileContent,
  getKongContainerName,
  isGateway,
  isGwHybrid,
  wait,
  waitForConfigRebuild,
  checkLogPropertyAndValue,
  isKongOSS,
} from '@support';

describe('@oss: Gateway Plugins: file-log', function () {
  const gwContainerName = isGwHybrid() ? 'kong-dp1' : getKongContainerName();
  const logFolder = `tmp/`;
  const fixLogFileName = `file-log.log`;
  const fixLogPath = `/${logFolder}${fixLogFileName}`;
  const consumerName = 'fileLogConsumer';
  const consumerGroupName = 'fileLogConsumerGroup';
  const waitTime = 3000;

  const custom_fields_by_lua_set = {
    "testRandomString": "return (function() local chars = \"abcdefghijklmnopqrstuvwxyz0123456789\"; return (string.gsub('yxxx-xxxxx', '[xy]', function() return chars:sub(math.random(1, #chars), math.random(1, #chars)) end)) end)()",
    "route.name": "return nil"
  }
  const pluginUrl = `${getBasePath({
    environment: isGateway() ? Environment.gateway.admin : undefined,
  })}/plugins`;
  const proxyUrl = getBasePath({
    environment: isGateway() ? Environment.gateway.proxy : undefined,
  });
  const path = `/${randomString()}`;
  const urlProxy = `${proxyUrl}${path}`;

  let serviceId: string;
  let routeId: string;
  let consumerId: string;
  let consumerGroupId: string;
  let pluginId: string;
  let basePayload: any;
  let postRequestId: string;
  let getRequestId: string;
  let randomLogFileName: string;
  let randomLogPath: string;


  const proxyGetRequest = {
    url: urlProxy,
    headers: { test: '' },
  };

  const proxyPostRequest = {
    method: 'post',
    data: {
      testProperty: 'testValue'
    },
    url: urlProxy,
    headers: { test: '' },
  };

  function setRandomLogFilePath() {
    randomLogFileName = `file-${randomString()}-log.log`;
    randomLogPath = `/${logFolder}${randomLogFileName}`;
    console.log(`Set file log path as ${randomLogPath}`);
  }

  async function sendGetProxyReqRenewReqId() {
    proxyGetRequest.headers.test = randomString();
    const getResp = await axios(proxyGetRequest);
    logResponse(getResp);
    getRequestId = getResp.headers['x-kong-request-id'];
    expect(getResp.status, 'Status should be 200').to.equal(200);
  }

  async function sendPostProxyReqRenewReqId() {
    proxyPostRequest.headers.test = randomString();
    const postResp = await axios(proxyPostRequest);
    logResponse(postResp);
    postRequestId = postResp.headers['x-kong-request-id']
    expect(postResp.status, 'Status should be 200').to.equal(200);
  }

  async function updatePluginConfig() {
    const resp = await axios({
      method: 'patch',
      url: `${pluginUrl}/${pluginId}`,
      data: basePayload,
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    await waitForConfigRebuild();
  }

  before(async function () {
    const service = await createGatewayService(randomString());
    serviceId = service.id;
    const route = await createRouteForService(serviceId, [path]);
    routeId = route.id;
    const consumer = await createConsumer(consumerName);
    consumerId = consumer.id;

    if(!isKongOSS()) {
      const consumerGroup = await createConsumerGroup(consumerGroupName);
      consumerGroupId = consumerGroup.id
    }

    await waitForConfigRebuild();
    basePayload = {
      name: 'file-log',
      service: {
        id: serviceId,
      },
      route: {
        id: routeId,
      },
      config: {
        reopen: false,
        path: '',
      }
    };
  });

  const fileNameValidation = ['/tmp/file-*.log','/tmp/file&test.log','/tmp/file%test.txt','/tmp/`file-test.json',''];

  fileNameValidation.forEach((filePath) => {
    it(`should not allow create plugin with log file name with ${filePath} in path or having empty path`, async function () {
      basePayload.config.path = filePath;
      const resp = await postNegative(pluginUrl, basePayload);
      logResponse(resp);

      expect(resp.status, 'Status should be 400').to.equal(400);
      expect(resp.data.message, 'Should have correct error message').to.contain(`not a valid filename`);
    });
  });

  it('should create file-log plugin with correct log file path successfully', async function () {
    setRandomLogFilePath();

    basePayload.config.path = randomLogPath;
    const resp = await axios({
      method: 'post',
      url: pluginUrl,
      data: basePayload,
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 201').to.equal(201);
    pluginId = resp.data.id;
    await waitForConfigRebuild();
  });

  it('should auto generate file log', async function () {
    await sendGetProxyReqRenewReqId();
    await sendPostProxyReqRenewReqId();

    await checkFileExistsInDockerContainer(gwContainerName, randomLogPath);
  });

  it('should contain request id and header inside the newly generated file log', async function () {
    copyFileFromDockerContainer(gwContainerName, `${logFolder}${randomLogFileName}`);
    const logContent: any = getTargetFileContent(randomLogFileName);

    const validations = [
      { testKey: 'request.headers.test', shouldExist: true, expectedTestValue: proxyGetRequest.headers.test },
      { testKey: 'response.headers.x-kong-request-id', shouldExist: true, expectedTestValue: getRequestId },
      { testKey: 'request.headers.test', shouldExist: true, expectedTestValue: proxyPostRequest.headers.test },
      { testKey: 'response.headers.x-kong-request-id', shouldExist: true, expectedTestValue: postRequestId},
      { testKey: 'client_ip', shouldExist: true},
    ];
    checkLogPropertyAndValue(logContent, validations);

    await deleteFileFromDockerContainer(gwContainerName, randomLogPath);
    deleteTargetFile(randomLogFileName);
  });

  it('should patch the file-log plugin allow custom fields and renew log file path', async function () {
    setRandomLogFilePath();

    basePayload.config.path = randomLogPath;
    basePayload.config.custom_fields_by_lua = custom_fields_by_lua_set;

    await updatePluginConfig();
  });

  it('should generate file log in new path', async function () {
    await sendGetProxyReqRenewReqId();
    await sendPostProxyReqRenewReqId();

    await checkFileExistsInDockerContainer(gwContainerName, randomLogPath);
  });

  it('should contain request id and test header and custom fields inside the file log ', async function () {
    copyFileFromDockerContainer(gwContainerName, `${logFolder}${randomLogFileName}`);
    const logContent: any = getTargetFileContent(randomLogFileName);

    const validations = [
      { testKey: 'request.headers.test', shouldExist: true, expectedTestValue: proxyGetRequest.headers.test },
      { testKey: 'response.headers.x-kong-request-id', shouldExist: true, expectedTestValue: getRequestId },
      { testKey: 'request.headers.test', shouldExist: true, expectedTestValue: proxyPostRequest.headers.test },
      { testKey: 'response.headers.x-kong-request-id', shouldExist: true, expectedTestValue: postRequestId},
      { testKey: 'client_ip', shouldExist: true},
      { testKey: 'testRandomString', shouldExist: true},
      { testKey: 'route.name', shouldExist: false},
    ];
    checkLogPropertyAndValue(logContent, validations);

    await deleteFileFromDockerContainer(gwContainerName, randomLogPath);
    deleteTargetFile(randomLogFileName);
  });

  it('should patch the plugin to allow reopen and add new fixed log path', async function () {
    basePayload.config.path = fixLogPath;
    basePayload.config.reopen = true;

    await updatePluginConfig();
  });

  it('should generate file log in fixed path', async function () {
    await sendGetProxyReqRenewReqId();
    await checkFileExistsInDockerContainer(gwContainerName, fixLogPath);
  });

  it('should re-generate file log in fixed path after log file deleted when reopen is enabled', async function () {
    await deleteFileFromDockerContainer(gwContainerName, fixLogPath);
    await checkFileExistsInDockerContainer(gwContainerName, fixLogPath, false);

    await sendGetProxyReqRenewReqId();

    await checkFileExistsInDockerContainer(gwContainerName, fixLogPath);
  });

  it('should contain request id and test header and custom fields inside the fixed file log', async function () {
    copyFileFromDockerContainer(gwContainerName, `${logFolder}${fixLogFileName}`);
    const logContent: any = getTargetFileContent(fixLogFileName);

    const validations = [
      { testKey: 'request.headers.test', shouldExist: true, expectedTestValue: proxyGetRequest.headers.test },
      { testKey: 'response.headers.x-kong-request-id', shouldExist: true, expectedTestValue: getRequestId },
      { testKey: 'client_ip', shouldExist: true},
      { testKey: 'testRandomString', shouldExist: true},
      { testKey: 'route.name', shouldExist: false},
    ];
    checkLogPropertyAndValue(logContent, validations);

    await deleteFileFromDockerContainer(gwContainerName, fixLogPath);
    deleteTargetFile(fixLogFileName);
  });

  it('should append file log in fixed path file log when log file is already created', async function () {
    await deleteFileFromDockerContainer(gwContainerName, fixLogPath);
    await checkFileExistsInDockerContainer(gwContainerName, fixLogPath, false);

    await createFileInDockerContainer(gwContainerName, fixLogPath);

    await sendGetProxyReqRenewReqId();

    await checkFileExistsInDockerContainer(gwContainerName, fixLogPath);
    copyFileFromDockerContainer(gwContainerName, `${logFolder}${fixLogFileName}`);
    const logContent: any = getTargetFileContent(fixLogFileName);

    const validations = [
      { testKey: 'request.headers.test', shouldExist: true, expectedTestValue: proxyGetRequest.headers.test },
      { testKey: 'response.headers.x-kong-request-id', shouldExist: true, expectedTestValue: getRequestId },
      { testKey: 'client_ip', shouldExist: true},
      { testKey: 'testRandomString', shouldExist: true},
      { testKey: 'route.name', shouldExist: false},
    ];
    checkLogPropertyAndValue(logContent, validations);

    await deleteFileFromDockerContainer(gwContainerName, fixLogPath);
    deleteTargetFile(fixLogFileName);
  });

  it('should include each request in same file log in fixed path when enable reopen', async function () {
    await checkFileExistsInDockerContainer(gwContainerName, fixLogPath, false);

    await sendGetProxyReqRenewReqId();

    await checkFileExistsInDockerContainer(gwContainerName, fixLogPath);
    copyFileFromDockerContainer(gwContainerName, `${logFolder}${fixLogFileName}`);
    const contentGet: any = getTargetFileContent(fixLogFileName);

    const validationsGet = [
      { testKey: 'request.headers.test', shouldExist: true, expectedTestValue: proxyGetRequest.headers.test },
      { testKey: 'response.headers.x-kong-request-id', shouldExist: true, expectedTestValue: getRequestId },
    ];
    checkLogPropertyAndValue(contentGet, validationsGet);

    deleteTargetFile(fixLogFileName);
    
    await sendPostProxyReqRenewReqId();
    await wait(waitTime); // eslint-disable-line no-restricted-syntax
    await checkFileExistsInDockerContainer(gwContainerName, fixLogPath);
    copyFileFromDockerContainer(gwContainerName, `${logFolder}${fixLogFileName}`);
    const contentAll: any = getTargetFileContent(fixLogFileName);

    const validationsAll = [
      { testKey: 'request.headers.test', shouldExist: true, expectedTestValue: proxyGetRequest.headers.test },
      { testKey: 'response.headers.x-kong-request-id', shouldExist: true, expectedTestValue: getRequestId },
      { testKey: 'request.headers.test', shouldExist: true, expectedTestValue: proxyPostRequest.headers.test },
      { testKey: 'response.headers.x-kong-request-id', shouldExist: true, expectedTestValue: postRequestId},
      { testKey: 'client_ip', shouldExist: true},
      { testKey: 'testRandomString', shouldExist: true},
      { testKey: 'route.name', shouldExist: false},
    ];
    checkLogPropertyAndValue(contentAll, validationsAll);

    await deleteFileFromDockerContainer(gwContainerName, fixLogPath);
    deleteTargetFile(fixLogFileName);
  });

  it('should be able to enable file-log plugin in consumer + route + service level', async function () {
    basePayload.config.path = fixLogPath;
    basePayload.consumer = { id: consumerId };
    const resp = await axios({
      method: 'post',
      url: pluginUrl,
      data: basePayload,
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 201').to.equal(201);
    pluginId = resp.data.id;
  });

  if (!isKongOSS()) {
    it('should not be able to enable file-log plugin in consumer group level', async function () {
      basePayload.consumer_group = { id: consumerGroupId };
      const resp = await postNegative(pluginUrl, basePayload);
      logResponse(resp);
  
      expect(resp.status, 'Status should be 400').to.equal(400);
      expect(resp.data.message, 'Should have correct error message').to.contain('consumer_group: value must be null');
    });
  }

  after(async function () {
    await clearAllKongResources();
    await deleteFileFromDockerContainer(gwContainerName, fixLogPath);
  });

});