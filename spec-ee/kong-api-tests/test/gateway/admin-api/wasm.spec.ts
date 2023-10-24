import {
  Environment,
  createFilterChainForRoute,
  createFilterChainForService,
  createGatewayService,
  createRouteForService,
  deleteFilterChain,
  deleteGatewayRoute,
  deleteGatewayService,
  expect,
  getBasePath,
  getNegative,
  logResponse,
  postNegative,
  randomString,
  waitForConfigRebuild
} from '@support';
import axios from 'axios';

describe('WASM filter admin API', function () {

  this.timeout(30000);
  const adminUrl = `${getBasePath({
    environment: Environment.gateway.admin,
  })}`;

  const proxyUrl = `${getBasePath({
    environment: Environment.gateway.proxy,
  })}`;

  const routePath = '/wasm/httpbin';
  const serviceName = randomString();
  const filterChainName = randomString();

  let serviceDetails: any;
  let routeId: string;

  before(async function () {
    const serviceReq = await createGatewayService(serviceName);
    serviceDetails = {
      id: serviceReq.id,
      name: serviceReq.name,
    };

    const routeReq = await createRouteForService(serviceDetails.id, [routePath]);
    routeId = routeReq.id;
  });


  describe('Create filter', function () {

    it('should return empty result when there are no filter_chains', async function () {

      const resp = await axios({
        method: 'get',
        url: `${adminUrl}/filter-chains`,
      });

      logResponse(resp);

      expect(resp.data.data).to.be.an('array').that.is.empty;

    });

    it('should fail to create filter_chain with JSON schema errors', async function () {

      const resp = await postNegative(
        `${adminUrl}/services/${serviceName}/filter-chains`,
        {
          name: filterChainName,
          enabled: true,
          filters: [
            {
              config: {
                add: {
                  headers: [
                    "hello:world",
                    "foo:bar"
                  ]
                },
                invalid: "baz"
              },
              enabled: true,
              name: "response_transformer"
            }
          ]
        });

      logResponse(resp);
      expect(resp.status, 'Status should be 400').to.be.equal(400);
      expect(resp.data.name, 'Name should be "schema violation"').to.be.equal('schema violation');
      expect(resp.data.fields.filters[0].config, 'config should display schema error"').to.be.equal("additional properties forbidden, found invalid");


    });

    it('should succeed to create filter-chain with valid schema', async function () {

      const data = {
        name: filterChainName,
        enabled: true,
        filters: [
          {
            config: {
              add: {
                headers: [
                  'hello:world',
                  'foo:bar'
                ]
              }
            },
            enabled: true,
            name: 'response_transformer'
          }
        ]
      }

      const resp = await axios({
        method: 'post',
        url: `${adminUrl}/services/${serviceName}/filter-chains`,
        data: data
      });

      logResponse(resp);
      expect(resp.status, "Status should be 201").to.be.equal(201);

      await deleteFilterChain(filterChainName);
      await waitForConfigRebuild();
    });
  });

  describe('filter', function () {

    beforeEach(async function () {
      const data = {
        name: filterChainName,
        enabled: true,
        filters: [
          {
            config: {
              add: {
                headers: [
                  'hello:world',
                  'foo:bar'
                ]
              }
            },
            enabled: true,
            name: 'response_transformer'
          }
        ]
      };

      await createFilterChainForService(data, serviceName);
      await waitForConfigRebuild();
    });

    it('should add response header', async function () {

      const resp = await axios({
        method: 'post',
        url: `${proxyUrl}${routePath}`,
        data: {
          foo: "bar"
        }
      });

      logResponse(resp);
      expect(resp.status, 'Status should be 200').to.be.equal(200);
      expect(resp.headers['hello'], "hello header should be set").is.equal("world");
      expect(resp.headers['foo'], "foo header should be set").is.equal("bar");
    });

    it('should return the created filter chain', async function () {

      const resp = await axios({
        method: 'get',
        url: `${adminUrl}/filter-chains`,
      });

      logResponse(resp);

      expect(resp.data.data).to.be.an('array').that.is.not.empty;
      expect(resp.data.data[0].name).to.be.equal(filterChainName);

    });

    it('should patch filter-chains', async function () {

      const data = {
        name: filterChainName,
        enabled: true,
        filters: [
          {
            config: {
              add: {
                headers: [
                  'this:isatest'
                ]
              }
            },
            enabled: true,
            name: 'response_transformer'
          }
        ]
      }

      let resp = await axios({
        method: 'patch',
        url: `${adminUrl}/filter-chains/${filterChainName}`,
        data: data
      });

      logResponse(resp);
      expect(resp.data.filters[0].config.add.headers[0]).to.be.equal('this:isatest');

      await waitForConfigRebuild();

      resp = await axios({
        method: 'post',
        url: `${proxyUrl}${routePath}`,
        data: {
          foo: "bar"
        }
      });

      logResponse(resp);
      expect(resp.status, 'Status should be 200').to.be.equal(200);
      expect(resp.headers['hello'], "hello header should not be set").to.be.undefined;
      expect(resp.headers['foo'], "foo header should not be set").to.be.undefined;
      expect(resp.headers['this'], "this header should be set").is.equal("isatest");

    });


    it('should get filter chain by name', async function () {

      const resp = await axios.get(`${adminUrl}/filter-chains/${filterChainName}`);
      logResponse(resp);
      expect(resp.status, 'Status should be 200').to.be.equal(200);
      expect(resp.data.name).to.be.equal(filterChainName);

    });

    it('should not get a filter chain with non-existant chain name', async function () {
      const resp = await getNegative(`${adminUrl}/filter-chains/thiswontmatch`);
      logResponse(resp);
      expect(resp.status, 'Status should be 404').to.be.equal(404);
    });

    it('should get service by chain name', async function () {

      const resp = await axios.get(`${adminUrl}/filter-chains/${filterChainName}/service`);
      logResponse(resp);
      expect(resp.status, 'Status should be 200').to.be.equal(200);
      expect(resp.data.name).to.be.equal(serviceName);
    });

    it('should not get service with non-existant chain name', async function () {
      const resp = await getNegative(`${adminUrl}/filter-chains/thiswontmatch/service`);
      logResponse(resp);
      expect(resp.status, 'Status should be 404').to.be.equal(404);
    });

    it('should get chains by service name', async function () {

      const resp = await axios.get(`${adminUrl}/services/${serviceName}/filter-chains`);
      logResponse(resp);
      expect(resp.status, 'Status should be 200').to.be.equal(200);
      expect(resp.data.data).to.be.an('array').that.is.not.empty;
      expect(resp.data.data[0].name).to.be.equal(filterChainName);
    });

    it('should not get filter chains with non-existant service name', async function () {
      const resp = await getNegative(`${adminUrl}/services/thiswontmatch/filter-chains`);
      logResponse(resp);
      expect(resp.status, 'Status should be 404').to.be.equal(404);
    });

    it('should get chain by service name', async function () {

      const resp = await axios.get(`${adminUrl}/services/${serviceName}/filter-chains/${filterChainName}`);
      logResponse(resp);
      expect(resp.status, 'Status should be 200').to.be.equal(200);
      expect(resp.data.name).to.be.equal(filterChainName);
    });

    it('should not get a filter chain with non-existant service name', async function () {
      const resp = await getNegative(`${adminUrl}/services/thiswontmatch/filter-chains/${filterChainName}`);
      logResponse(resp);
      expect(resp.status, 'Status should be 404').to.be.equal(404);
    });

    it('should delete the created filter chain', async function () {

      let resp = await axios({
        method: 'delete',
        url: `${adminUrl}/filter-chains/${filterChainName}`,
      });

      logResponse(resp);

      expect(resp.status, 'Status should be 204').to.be.equal(204);

      await waitForConfigRebuild();

      resp = await axios({
        method: 'post',
        url: `${proxyUrl}${routePath}`,
        data: {
          foo: "bar"
        }
      });

      logResponse(resp);
      expect(resp.status, 'Status should be 200').to.be.equal(200);
      expect(resp.headers['this'], "this header should not be set").to.be.undefined;
    });

    afterEach(async function () {
      await deleteFilterChain(filterChainName);
    });

  });

    describe('filters on routes', function () {

      beforeEach(async function () {
        const data = {
          name: filterChainName,
          enabled: true,
          filters: [
            {
              config: {
                add: {
                  headers: [
                    'hello:world',
                    'foo:bar'
                  ]
                }
              },
              enabled: true,
              name: 'response_transformer'
            }
          ]
        };
  
        await createFilterChainForRoute(data, routeId);
        await waitForConfigRebuild();
      });

      it('should get route by chain name', async function () {

        const resp = await axios.get(`${adminUrl}/filter-chains/${filterChainName}/route`);
        logResponse(resp);
        expect(resp.status, 'Status should be 200').to.be.equal(200);
        expect(resp.data.id).to.be.equal(routeId);
      });

      it('should not get a route with non-existant chain name', async function () {
        const resp = await getNegative(`${adminUrl}/filter-chains/thiswontmatch/route`);
        logResponse(resp);
        expect(resp.status, 'Status should be 404').to.be.equal(404);
      });

      it('should get chains by route id', async function () {

        const resp = await axios.get(`${adminUrl}/routes/${routeId}/filter-chains`);
        logResponse(resp);
        expect(resp.status, 'Status should be 200').to.be.equal(200);
        expect(resp.data.data).to.be.an('array').that.is.not.empty;
        expect(resp.data.data[0].name).to.be.equal(filterChainName);
      });

      it('should not get chains by non-existant route id', async function () {
        const resp = await getNegative(`${adminUrl}/routes/thiswontmatch/filter-chains`);
        logResponse(resp);
        expect(resp.status, 'Status should be 404').to.be.equal(404);
      });
  
      it('should get chain by route id', async function () {
        const resp = await axios.get(`${adminUrl}/routes/${routeId}/filter-chains/${filterChainName}`);
        logResponse(resp);
        expect(resp.status, 'Status should be 200').to.be.equal(200);
        expect(resp.data.name).to.be.equal(filterChainName);
      });

      it('should not get chain by non-existant route id', async function () {
        const resp = await getNegative(`${adminUrl}/routes/thiswontmatch/filter-chains/${filterChainName}`);
        logResponse(resp);
        expect(resp.status, 'Status should be 404').to.be.equal(404);
      });

      afterEach(async function () {
        await deleteFilterChain(filterChainName);
      });

    });

    describe('enabling / disabling of filters', function () {
      beforeEach(async function () {
        const serviceChain = {
          name: 'servicechain',
          enabled: true,
          filters: [
            {
              config: {
                add: {
                  headers: [
                    'first:service'
                  ]
                }
              },
              enabled: true,
              name: 'response_transformer'
            },
            {
              config: {
                add: {
                  headers: [
                    'second:service'
                  ]
                }
              },
              enabled: false,
              name: 'response_transformer'
            },
            {
              config: {
                add: {
                  headers: [
                    'third:service'
                  ]
                }
              },
              enabled: true,
              name: 'response_transformer'
            }
          ]
        };
        const routeChain = {
          name: 'routechain',
          enabled: true,
          filters: [
            {
              config: {
                add: {
                  headers: [
                    'fourth:route'
                  ]
                }
              },
              enabled: false,
              name: 'response_transformer'
            },
            {
              config: {
                add: {
                  headers: [
                    'fifth:route'
                  ]
                }
              },
              enabled: true,
              name: 'response_transformer'
            },
            {
              config: {
                add: {
                  headers: [
                    'sixth:route'
                  ]
                }
              },
              enabled: true,
              name: 'response_transformer'
            }
          ]
        };

        await createFilterChainForService(serviceChain, serviceName);
        await createFilterChainForRoute(routeChain, routeId);
        await waitForConfigRebuild();
      });

      it('should get enabled filters only', async function () {
        const resp = await axios.get(`${adminUrl}/routes/${routeId}/filters/enabled`);
        logResponse(resp);
        expect(resp.status, 'Status should be 200').to.be.equal(200);
        expect(resp.data.filters, 'Should be an array of size 4').to.be.an("array").ofSize(4);
        expect(resp.data.filters[0].config.add.headers[0], 'first service-attached filter should be enabled').to.equal("first:service");
        expect(resp.data.filters[1].config.add.headers[0], 'third service-attached filter should be enabled').to.equal("third:service");
        expect(resp.data.filters[2].config.add.headers[0], 'fifth route-attached filter should be enabled').to.equal("fifth:route");
        expect(resp.data.filters[3].config.add.headers[0], 'sixth route-attached filter should be enabled').to.equal("sixth:route");
      });

      it('should only execute enabled filters', async function () {

        const resp = await axios({
          method: 'post',
          url: `${proxyUrl}${routePath}`,
          data: {
            foo: "bar"
          }
        });
  
        logResponse(resp);
        expect(resp.status, 'Status should be 200').to.be.equal(200);
        expect(resp.headers['first'], "first header should be set").is.equal("service");
        expect(resp.headers['third'], "third header should be set").is.equal("service");
        expect(resp.headers['fifth'], "fifth header should be set").is.equal("route");
        expect(resp.headers['sixth'], "sixth header should be set").is.equal("route");

        expect(resp.headers['second'], "second header should not be set").to.be.undefined;
        expect(resp.headers['fourth'], "fourth header should not be set").to.be.undefined;

      });

      it('should get disabled filters only', async function () {
        const resp = await axios.get(`${adminUrl}/routes/${routeId}/filters/disabled`);
        logResponse(resp);
        expect(resp.status, 'Status should be 200').to.be.equal(200);
        expect(resp.data.filters, 'Should be an array of size 2').to.be.an("array").ofSize(2);
        expect(resp.data.filters[0].config.add.headers[0], 'second service-attached filter should be disabled').to.equal("second:service");
        expect(resp.data.filters[1].config.add.headers[0], 'fourth route-attached filter should be disabled').to.equal("fourth:route");
      });

      it('should get all filters on the route', async function () {
        const resp = await axios.get(`${adminUrl}/routes/${routeId}/filters/all`);
        logResponse(resp);
        expect(resp.status, 'Status should be 200').to.be.equal(200);
        expect(resp.data.filters, 'Should be an array of size 6').to.be.an("array").ofSize(6);
        expect(resp.data.filters[0].config.add.headers[0], 'first service-attached filter should be enabled').to.equal("first:service");
        expect(resp.data.filters[1].config.add.headers[0], 'second service-attached filter should be disabled').to.equal("second:service");
        expect(resp.data.filters[2].config.add.headers[0], 'third service-attached filter should be enabled').to.equal("third:service");
        expect(resp.data.filters[3].config.add.headers[0], 'fourth route-attached filter should be disabled').to.equal("fourth:route");
        expect(resp.data.filters[4].config.add.headers[0], 'fifth route-attached filter should be enabled').to.equal("fifth:route");
        expect(resp.data.filters[5].config.add.headers[0], 'sixth route-attached filter should be enabled').to.equal("sixth:route");
      });

      afterEach(async function () {
        await deleteFilterChain("servicechain");
        await deleteFilterChain("routechain");
      });
    });

  after(async function () {
    await deleteGatewayRoute(routeId);
    await deleteGatewayService(serviceName);
  });

});