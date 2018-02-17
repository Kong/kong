local cjson   = require "cjson"
local helpers = require "spec.helpers"


for _, strategy in helpers.each_strategy() do

  describe("Mock proxy [#" .. strategy .. "]", function()
    local mock_proxy_client
    local bp

    local consumer, service1, route1, key_auth1, rate_limiting1,
          service2, route2, rate_limiting2, rate_limiting3,
          service3, route3, rate_limiting4, credential

    local router_matches1 = { host = "route1.com" }
    local router_matches2 = { host = "route2.com" }
    local router_matches3 = { host = "route3.com" }

    setup(function()
      bp = helpers.get_db_utils(strategy)

      consumer = bp.consumers:insert {
        username = "consumer"
      }

      credential = {
        consumer_id = consumer.id
      }

      -- Global Configuration
      service1 = bp.services:insert {
        name = "service-1",
      }

      route1 = bp.routes:insert {
        hosts     = { "route1.com" },
        protocols = { "http" },
        service   = service1,
      }

      key_auth1 = bp.plugins:insert {
        name   = "key-auth",
        config = {},
      }

      rate_limiting1 = bp.plugins:insert {
        name   = "rate-limiting",
        config = {
          hour = 1,
        },
      }

      -- Route Specific Configuration
      service2 = bp.services:insert {
        name = "service-2",
      }

      route2 = bp.routes:insert {
        hosts     = { "route2.com" },
        protocols = { "http" },
        service   = service2,
      }

      rate_limiting2 = bp.plugins:insert {
        name       = "rate-limiting",
        route_id   = route2.id,
        service_id = service2.id,
        config     = {
          hour     = 2,
        },
      }

      rate_limiting2.config.service_id   = rate_limiting2.service_id
      rate_limiting2.config.route_id   = rate_limiting2.route_id

      -- Consumer Specific Configuration
      rate_limiting3 = bp.plugins:insert {
        name        = "rate-limiting",
        consumer_id = consumer.id,
        config      = {
          hour      = 3,
        },
      }

      rate_limiting3.config.consumer_id = rate_limiting3.consumer_id

      -- Route and Consumer Configuration
      service3 = bp.services:insert {
        name = "service-3",
      }

      route3 = bp.routes:insert {
        hosts     = { "route3.com" },
        protocols = { "http" },
        service   = service3,
      }

      rate_limiting4 = bp.plugins:insert {
        name        = "rate-limiting",
        route_id    = route3.id,
        consumer_id = consumer.id,
        config      = {
          hour      = 4,
        },
      }

      rate_limiting4.config.route_id    = rate_limiting4.route_id
      rate_limiting4.config.consumer_id = rate_limiting4.consumer_id

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))

      mock_proxy_client = helpers.proxy_client(nil, true)
    end)

    teardown(function()
      if mock_proxy_client then
        mock_proxy_client:close()
      end

      helpers.stop_kong()
    end)

    it("returns results with global plugins", function()
      local res = assert(mock_proxy_client:send {
        method  = "GET",
        path    = "/",
        headers = { Host = "route1.com" }
      })

      local body = assert.res_status(200, res)
      local json = cjson.decode(body)

      assert.equal(cjson.null,           json.api)
      assert.equal(cjson.null,           json.authenticated_consumer)
      assert.equal(cjson.null,           json.authenticated_credential)
      assert.same(service1,              json.service)
      assert.same(route1,                json.route)
      assert.same(router_matches1,       json.router_matches)
      assert.equal(2,                    #json.plugins)
      assert.equal(key_auth1.name,       json.plugins[1].name)
      assert.same(key_auth1.config,      json.plugins[1].config)
      assert.same(rate_limiting1.name,   json.plugins[2].name)
      assert.same(rate_limiting1.config, json.plugins[2].config)
      assert.equal(60000,                json.balancer_data.connect_timeout)
      assert.equal(60000,                json.balancer_data.read_timeout)
      assert.equal(60000,                json.balancer_data.send_timeout)
      assert.equal(5,                    json.balancer_data.retries)
      assert.equal(1,                    json.balancer_data.try_count)
      assert.equal(15555,                json.balancer_data.port)
      assert.equal("ipv4",               json.balancer_data.type)
      assert.equal("127.0.0.1",          json.balancer_data.host)
      assert.equal("127.0.0.1",          json.balancer_data.hostname)
      assert.equal("127.0.0.1",          json.balancer_data.ip)
      assert.same({{
        balancer_latency = 0,
        ip               = "127.0.0.1",
        port             = 15555,
        balancer_start   = json.balancer_data.tries[1].balancer_start,
      }}, json.balancer_data.tries)
    end)

    it("returns results with global plugins with consumer specified", function()
      local query_args =  {
        consumer = consumer.id,
      }

      local res = assert(mock_proxy_client:send {
        method  = "GET",
        path    = "/",
        headers = { Host = "route1.com" },
        query    = query_args
      })

      local body = assert.res_status(200, res)
      local json = cjson.decode(body)

      assert.equal(cjson.null,           json.api)
      assert.same(consumer,              json.authenticated_consumer)
      assert.same(credential,            json.authenticated_credential)
      assert.same(service1,              json.service)
      assert.same(route1,                json.route)
      assert.same(router_matches1,       json.router_matches)
      assert.equal(2,                    #json.plugins)
      assert.equal(key_auth1.name,       json.plugins[1].name)
      assert.same(key_auth1.config,      json.plugins[1].config)
      assert.same(rate_limiting3.name,   json.plugins[2].name)
      assert.same(rate_limiting3.config, json.plugins[2].config)
      assert.equal(60000,                json.balancer_data.connect_timeout)
      assert.equal(60000,                json.balancer_data.read_timeout)
      assert.equal(60000,                json.balancer_data.send_timeout)
      assert.equal(5,                    json.balancer_data.retries)
      assert.equal(1,                    json.balancer_data.try_count)
      assert.equal(15555,                json.balancer_data.port)
      assert.equal("ipv4",               json.balancer_data.type)
      assert.equal("127.0.0.1",          json.balancer_data.host)
      assert.equal("127.0.0.1",          json.balancer_data.hostname)
      assert.equal("127.0.0.1",          json.balancer_data.ip)
      assert.same({{
        balancer_latency = 0,
        ip               = "127.0.0.1",
        port             = 15555,
        balancer_start   = json.balancer_data.tries[1].balancer_start,
      }}, json.balancer_data.tries)
    end)

    it("returns results with route specific plugins", function()
      local res = assert(mock_proxy_client:send {
        method  = "GET",
        path    = "/",
        headers = { Host = "route2.com" }
      })

      local body = assert.res_status(200, res)
      local json = cjson.decode(body)

      assert.equal(cjson.null,           json.api)
      assert.equal(cjson.null,           json.authenticated_consumer)
      assert.equal(cjson.null,           json.authenticated_credential)
      assert.same(service2,              json.service)
      assert.same(route2,                json.route)
      assert.same(router_matches2,       json.router_matches)
      assert.equal(2,                    #json.plugins)
      assert.equal(key_auth1.name,       json.plugins[1].name)
      assert.same(key_auth1.config,      json.plugins[1].config)
      assert.same(rate_limiting2.name,   json.plugins[2].name)
      assert.same(rate_limiting2.config, json.plugins[2].config)
      assert.equal(60000,                json.balancer_data.connect_timeout)
      assert.equal(60000,                json.balancer_data.read_timeout)
      assert.equal(60000,                json.balancer_data.send_timeout)
      assert.equal(5,                    json.balancer_data.retries)
      assert.equal(1,                    json.balancer_data.try_count)
      assert.equal(15555,                json.balancer_data.port)
      assert.equal("ipv4",               json.balancer_data.type)
      assert.equal("127.0.0.1",          json.balancer_data.host)
      assert.equal("127.0.0.1",          json.balancer_data.hostname)
      assert.equal("127.0.0.1",          json.balancer_data.ip)
      assert.same({{
        balancer_latency = 0,
        ip               = "127.0.0.1",
        port             = 15555,
        balancer_start   = json.balancer_data.tries[1].balancer_start,
      }}, json.balancer_data.tries)
    end)

    it("returns results with service and route specific plugins with consumer specified", function()
      local post_args =  {
        consumer = consumer.id,
      }

      local res = assert(mock_proxy_client:send {
        method  = "POST",
        path    = "/",
        headers = {
          Host = "route2.com",
          ["Content-Type"] = "application/x-www-form-urlencoded",
        },
        body    = ngx.encode_args(post_args)
      })

      local body = assert.res_status(200, res)
      local json = cjson.decode(body)

      assert.equal(cjson.null,           json.api)
      assert.same(consumer,              json.authenticated_consumer)
      assert.same(credential,            json.authenticated_credential)
      assert.same(service2,              json.service)
      assert.same(route2,                json.route)
      assert.same(router_matches2,       json.router_matches)
      assert.equal(2,                    #json.plugins)
      assert.equal(key_auth1.name,       json.plugins[1].name)
      assert.same(key_auth1.config,      json.plugins[1].config)
      assert.same(rate_limiting2.name,   json.plugins[2].name)
      assert.same(rate_limiting2.config, json.plugins[2].config)
      assert.equal(60000,                json.balancer_data.connect_timeout)
      assert.equal(60000,                json.balancer_data.read_timeout)
      assert.equal(60000,                json.balancer_data.send_timeout)
      assert.equal(5,                    json.balancer_data.retries)
      assert.equal(1,                    json.balancer_data.try_count)
      assert.equal(15555,                json.balancer_data.port)
      assert.equal("ipv4",               json.balancer_data.type)
      assert.equal("127.0.0.1",          json.balancer_data.host)
      assert.equal("127.0.0.1",          json.balancer_data.hostname)
      assert.equal("127.0.0.1",          json.balancer_data.ip)
      assert.same({{
        balancer_latency = 0,
        ip               = "127.0.0.1",
        port             = 15555,
        balancer_start   = json.balancer_data.tries[1].balancer_start,
      }}, json.balancer_data.tries)
    end)

    it("returns results with route and consumer specific plugins", function()
      local res = assert(mock_proxy_client:send {
        method  = "GET",
        path    = "/",
        headers = { Host = "route3.com" }
      })

      local body = assert.res_status(200, res)
      local json = cjson.decode(body)

      assert.equal(cjson.null,           json.api)
      assert.equal(cjson.null,           json.authenticated_consumer)
      assert.equal(cjson.null,           json.authenticated_credential)
      assert.same(service3,              json.service)
      assert.same(route3,                json.route)
      assert.same(router_matches3,       json.router_matches)
      assert.equal(2,                    #json.plugins)
      assert.equal(key_auth1.name,       json.plugins[1].name)
      assert.same(key_auth1.config,      json.plugins[1].config)
      assert.same(rate_limiting1.name,   json.plugins[2].name)
      assert.same(rate_limiting1.config, json.plugins[2].config)
      assert.equal(60000,                json.balancer_data.connect_timeout)
      assert.equal(60000,                json.balancer_data.read_timeout)
      assert.equal(60000,                json.balancer_data.send_timeout)
      assert.equal(5,                    json.balancer_data.retries)
      assert.equal(1,                    json.balancer_data.try_count)
      assert.equal(15555,                json.balancer_data.port)
      assert.equal("ipv4",               json.balancer_data.type)
      assert.equal("127.0.0.1",          json.balancer_data.host)
      assert.equal("127.0.0.1",          json.balancer_data.hostname)
      assert.equal("127.0.0.1",          json.balancer_data.ip)
      assert.same({{
        balancer_latency = 0,
        ip               = "127.0.0.1",
        port             = 15555,
        balancer_start   = json.balancer_data.tries[1].balancer_start,
      }}, json.balancer_data.tries)
    end)

    it("returns results with route and consumer specific plugins with consumer specified", function()
      local post_args =  {
        consumer = consumer.id,
      }

      local res = assert(mock_proxy_client:send {
        method  = "POST",
        path    = "/",
        headers = {
          Host = "route3.com",
          ["Content-Type"] = "application/x-www-form-urlencoded",
        },
        body    = ngx.encode_args(post_args)
      })

      local body = assert.res_status(200, res)
      local json = cjson.decode(body)

      assert.equal(cjson.null,           json.api)
      assert.same(consumer,              json.authenticated_consumer)
      assert.same(credential,            json.authenticated_credential)
      assert.same(service3,              json.service)
      assert.same(route3,                json.route)
      assert.same(router_matches3,       json.router_matches)
      assert.equal(2,                    #json.plugins)
      assert.equal(key_auth1.name,       json.plugins[1].name)
      assert.same(key_auth1.config,      json.plugins[1].config)
      assert.same(rate_limiting4.name,   json.plugins[2].name)
      assert.same(rate_limiting4.config, json.plugins[2].config)
      assert.equal(60000,                json.balancer_data.connect_timeout)
      assert.equal(60000,                json.balancer_data.read_timeout)
      assert.equal(60000,                json.balancer_data.send_timeout)
      assert.equal(5,                    json.balancer_data.retries)
      assert.equal(1,                    json.balancer_data.try_count)
      assert.equal(15555,                json.balancer_data.port)
      assert.equal("ipv4",               json.balancer_data.type)
      assert.equal("127.0.0.1",          json.balancer_data.host)
      assert.equal("127.0.0.1",          json.balancer_data.hostname)
      assert.equal("127.0.0.1",          json.balancer_data.ip)
      assert.same({{
        balancer_latency = 0,
        ip               = "127.0.0.1",
        port             = 15555,
        balancer_start   = json.balancer_data.tries[1].balancer_start,
      }}, json.balancer_data.tries)
    end)

    it("returns 404 on route not found", function()
      local res = assert(mock_proxy_client:send {
        method  = "GET",
        path    = "/",
        headers = { Host = "route-not-found.com" },
      })

      assert.res_status(404, res)
    end)

  end)

end
