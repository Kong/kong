import axios from 'axios';
import { openApiSchemas } from '@fixtures';
import {
  expect,
  Environment,
  getBasePath,
  createGatewayService,
  deleteGatewayService,
  createRouteForService,
  deleteGatewayRoute,
  wait,
  logResponse,
  postNegative,
  randomString,
  waitForConfigRebuild,
  eventually,
} from '@support';

describe('Gateway Plugins: oas-validation', function () {
  const apiSpecUrl = 'http://swagger:8080/api/v3/';
  const resourcePet = 'pet';
  const path = '/oas-validation';
  const serviceName = randomString();
  const apiSpec = JSON.stringify(openApiSchemas);
  const hybridWaitTime = 7000;
  let serviceId: string;
  let routeId: string;

  const url = `${getBasePath({
    environment: Environment.gateway.admin,
  })}/plugins`;
  const proxyUrl = `${getBasePath({
    environment: Environment.gateway.proxy,
  })}`;

  let basePayload: any;
  let missingNamePayload: any;
  let missingPhotoUrlsPayload: any;
  let petPayload: any;
  let pluginId: string;
  let petId: string;

  before(async function () {
    const service = await createGatewayService(serviceName, {
      url: `${apiSpecUrl}`,
    });
    serviceId = service.id;

    const route = await createRouteForService(serviceId, [path]);
    routeId = route.id;

    await wait(hybridWaitTime); // eslint-disable-line no-restricted-syntax

    petPayload = {
      id: 1,
      category: {
        id: 1,
        name: 'Reptiles',
      },
      name: 'Velociraptor',
      photoUrls: ['http://kongrules'],
      status: 'available',
    };

    missingNamePayload = {
      id: 1,
      category: {
        id: 1,
        name: 'Reptiles',
      },
      photoUrls: ['http://localhost:8080/callback'],
      status: 'available',
    };

    missingPhotoUrlsPayload = {
      id: 1,
      category: {
        id: 1,
        name: 'Reptiles',
      },
      name: 'Velociraptor',
      status: 'available',
    };

    basePayload = {
      name: 'oas-validation',
      service: {
        id: serviceId,
      },
      route: {
        id: routeId,
      },
    };
  });

  it('should not create oas-validation plugin without an api spec', async function () {
    const pluginPayload = {
      ...basePayload,
      config: {
        validate_response_body: true,
        verbose_response: true,
      },
    };
    const resp = await postNegative(url, pluginPayload);
    logResponse(resp);

    expect(resp.status, 'Status should be 400').to.equal(400);
    expect(resp.data.name, 'Should be schema violation').to.equal(
      'schema violation'
    );
    expect(
      resp.data.fields.config.api_spec,
      'Should indicate the api spec field is missing'
    ).to.equal('required field missing');
  });

  it('should not create oas-validation plugin when api spec format is incorrect', async function () {
    const pluginPayload = {
      ...basePayload,
      config: {
        api_spec: openApiSchemas,
        validate_response_body: true,
        verbose_response: true,
      },
    };
    const resp = await postNegative(url, pluginPayload);
    logResponse(resp);

    expect(resp.status, 'Status should be 400').to.equal(400);
    expect(resp.data.name, 'Should be schema violation').to.equal(
      'schema violation'
    );
    expect(
      resp.data.fields.config.api_spec,
      'Should indicate the api spec requires a string'
    ).to.equal('expected a string');
  });

  it('should create oas-validation plugin with validation enabled', async function () {
    const pluginPayload = {
      ...basePayload,
      config: {
        api_spec: apiSpec,
        validate_response_body: true,
        verbose_response: true,
      },
    };
    const resp = await axios({ method: 'post', url, data: pluginPayload });
    logResponse(resp);

    expect(resp.status, 'Status should be 201').to.equal(201);
    pluginId = resp.data.id;

    expect(resp.data.config.api_spec, 'Should have correct api spec').to.eq(
      apiSpec
    );
    expect(
      resp.data.config.validate_response_body,
      'Should have correct response body validation'
    ).to.be.true;
    expect(
      resp.data.config.verbose_response,
      'Should have correct response body validation'
    ).to.be.true;

    await waitForConfigRebuild();
  });

  it('should not POST new item when required name field is missing when request validation is enforced', async function () {
    await eventually(async () => {
      const resp = await postNegative(
        `${proxyUrl}${path}/${resourcePet}`,
        missingNamePayload
      );
      logResponse(resp);
  
      expect(resp.status, 'Status should be 400').to.equal(400);
      expect(resp.data.message, 'Should have correct validation message').to.eq(
        "request body validation failed with error: 'property name is required'"
      );
    });
  });

  it('should not POST new item when required photoURLS field is missing when request validation is enforced', async function () {
    const resp = await postNegative(
      `${proxyUrl}${path}/${resourcePet}`,
      missingPhotoUrlsPayload
    );
    logResponse(resp);

    expect(resp.status, 'Status should be 400').to.equal(400);
    expect(resp.data.message, 'Should have correct validation message').to.eq(
      "request body validation failed with error: 'property photoUrls is required'"
    );
  });

  it('should POST new item with all required fields', async function () {
    const resp = await axios({
      url: `${proxyUrl}${path}/${resourcePet}`,
      method: 'post',
      data: petPayload,
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.category.name, 'Should have correct category name').to.eq(
      'Reptiles'
    );
    petId = resp.data.id;
  });

  it('should GET item with item ID', async function () {
    const resp = await axios({
      method: 'get',
      url: `${proxyUrl}${path}/${resourcePet}/${petId}`,
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.category.name, 'Should have correct category name').to.eq(
      'Reptiles'
    );
    expect(resp.data.status, 'Should have correct status').to.eq('available');
  });

  it('should update item using PUT with required fields', async function () {
    const resp = await axios({
      url: `${proxyUrl}${path}/${resourcePet}`,
      method: 'put',
      data: {
        id: petId,
        category: {
          id: 1,
          name: 'Reptiles',
        },
        name: 'Velociraptor',
        photoUrls: ['url1'],
        status: 'sold',
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.category.name, 'Should have correct category name').to.eq(
      'Reptiles'
    );
    expect(resp.data.status, 'Should have correct status').to.eq('sold');
    petId = resp.data.id;
  });

  it('should retrieve updated item using GET with item ID', async function () {
    const resp = await axios({
      method: 'get',
      url: `${proxyUrl}${path}/${resourcePet}/${petId}`,
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.category.name, 'Should have correct category name').to.eq(
      'Reptiles'
    );
    expect(resp.data.status, 'Should have correct status').to.eq('sold');
  });

  it('should PATCH oas-validation plugin to skip request validation and enforce response validation', async function () {
    const resp = await axios({
      method: 'patch',
      url: `${url}/${pluginId}`,
      data: {
        config: {
          validate_response_body: true,
          validate_request_body: false,
          notify_only_request_validation_failure: false,
          notify_only_response_body_validation_failure: false,
          verbose_response: true,
        },
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(
      resp.data.config.validate_request_body,
      'Should have correct response body validation'
    ).to.be.false;
    expect(
      resp.data.config.validate_response_body,
      'Should have correct response body validation'
    ).to.be.true;
    expect(
      resp.data.config.verbose_response,
      'Should have correct response body validation'
    ).to.be.true;

    await waitForConfigRebuild();
  });

  it('should enforce response validation when parameter enabled', async function () {
    const resp = await postNegative(
      `${proxyUrl}${path}/${resourcePet}`,
      missingNamePayload
    );
    logResponse(resp);

    expect(resp.status, 'Status should be 406').to.equal(406);
    expect(
      resp.data.message,
      'Should indicate response validation failed'
    ).to.eq(
      'response body validation failed with error: property name is required'
    );
  });

  it('should PATCH oas-validation plugin to skip validation', async function () {
    const resp = await axios({
      method: 'patch',
      url: `${url}/${pluginId}`,
      data: {
        config: {
          validate_response_body: true,
          validate_request_body: false,
          notify_only_request_validation_failure: false,
          notify_only_response_body_validation_failure: true,
          verbose_response: true,
        },
      },
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(
      resp.data.config.validate_request_body,
      'Should have correct response body validation'
    ).to.be.false;
    expect(
      resp.data.config.validate_response_body,
      'Should have correct response body validation'
    ).to.be.true;
    expect(
      resp.data.config.verbose_response,
      'Should have correct response body validation'
    ).to.be.true;

    await waitForConfigRebuild();
  });

  it('should POST new item without required name field when validation is skipped', async function () {
    const resp = await postNegative(
      `${proxyUrl}${path}/${resourcePet}`,
      missingNamePayload
    );
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.category.name, 'Should have correct category name').to.eq(
      'Reptiles'
    );
  });

  it('should POST new item without required photoURLS field when validation is skipped', async function () {
    const resp = await postNegative(
      `${proxyUrl}${path}/${resourcePet}`,
      missingPhotoUrlsPayload
    );
    logResponse(resp);

    expect(resp.status, 'Status should be 200').to.equal(200);
    expect(resp.data.category.name, 'Should have correct category name').to.eq(
      'Reptiles'
    );
  });

  it('should delete the oas-validation plugin', async function () {
    const resp = await axios({
      method: 'delete',
      url: `${url}/${pluginId}`,
    });
    logResponse(resp);

    expect(resp.status, 'Status should be 204').to.equal(204);
  });

  after(async function () {
    await deleteGatewayRoute(routeId);
    await deleteGatewayService(serviceId);
  });
});
