local helpers = require "spec.helpers"
local conf_loader = require "kong.conf_loader"
local insert = table.insert
local factories = require "spec.fixtures.factories.plugins"

local PluginFactory = factories.PluginFactory
local EntitiesFactory = factories.EntitiesFactory

for _, strategy in helpers.each_strategy() do
  describe("Plugins Iterator - Triple Scoping - #Consumer #Route #Service on #" .. strategy, function()
    local proxy_client, expected_header, must_not_have_headers

    lazy_teardown(function()
      helpers.stop_kong()
      helpers.kill_all()
      assert(conf_loader(nil, {}))
    end)

    lazy_setup(function()
      proxy_client = helpers.proxy_client
      helpers.stop_kong()
      helpers.kill_all()
      assert(conf_loader(nil, {}))

      local ef = EntitiesFactory:setup(strategy)
      local pf = PluginFactory:setup(ef)

      -- to authenticate as `alice`
      -- scoped to consumer, route, and service
      expected_header = pf:consumer_route_service()

      -- adding header-names of plugins that should _not_ be executed
      -- this assits with tracking if a plugin was executed or not
      must_not_have_headers = {}

      -- scoped to Consumer, Route
      insert(must_not_have_headers, (pf:consumer_route()))
      -- scoped to Consumer, Service
      insert(must_not_have_headers, (pf:consumer_service()))
      -- scoped to Route, Service
      insert(must_not_have_headers, (pf:route_service()))

      -- scoped to route
      insert(must_not_have_headers, (pf:route()))
      -- scoped to serive
      insert(must_not_have_headers, (pf:service()))
      -- scoped to consumer
      insert(must_not_have_headers, (pf:consumer()))
      -- scoped to global
      insert(must_not_have_headers, (pf:global()))

      assert.is_equal(#must_not_have_headers, 7)

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))
    end)

    it("verify precedence", function()
      local r = proxy_client():get("/anything", {
        headers = {
          host = "route.test",
          -- authenticate as `alice`
          apikey = "alice",
        },
      })
      assert.response(r).has.status(200)
      -- verify that the expected plugin was executed
      assert.request(r).has_header(expected_header)
      -- verify that no other plugin was executed that had lesser scopes configured
      for _, header in pairs(must_not_have_headers) do
        assert.request(r).has_no_header(header)
      end
    end)
  end)

  describe("Plugins Iterator - Dual Scoping - #Consumer #Route on #" .. strategy, function()
    local proxy_client, expected_header, must_not_have_headers

    lazy_teardown(function()
      helpers.stop_kong()
      helpers.kill_all()
      assert(conf_loader(nil, {}))
    end)

    lazy_setup(function()
      proxy_client = helpers.proxy_client
      helpers.stop_kong()
      helpers.kill_all()
      assert(conf_loader(nil, {}))

      local ef = EntitiesFactory:setup(strategy)
      local pf = PluginFactory:setup(ef)

      expected_header = pf:consumer_route()
      -- adding header-names of plugins that should _not_ be executed
      -- this assits with tracking if a plugin was executed or not
      must_not_have_headers = {}

      -- scoped to Consumer, Service
      insert(must_not_have_headers, (pf:consumer_service()))
      -- scoped to Route, Service
      insert(must_not_have_headers, (pf:route_service()))

      -- scoped to route
      insert(must_not_have_headers, (pf:route()))
      -- scoped to serive
      insert(must_not_have_headers, (pf:service()))
      -- scoped to consumer
      insert(must_not_have_headers, (pf:consumer()))
      -- scoped to global
      insert(must_not_have_headers, (pf:global()))

      assert.is_equal(#must_not_have_headers, 6)

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))
    end)

    it("verify precedence", function()
      local r = proxy_client():get("/anything", {
        headers = {
          host = "route.test",
          -- authenticate as `alice`
          apikey = "alice",
        },
      })
      assert.response(r).has.status(200)
      -- verify that the expected plugin was executed
      assert.request(r).has_header(expected_header)
      -- verify that no other plugin was executed that had lesser scopes configured
      for _, header in pairs(must_not_have_headers) do
        assert.request(r).has_no_header(header)
      end
    end)
  end)

  describe("Plugins Iterator - Dual Scoping - #Consumer #Service on #" .. strategy, function()
    local proxy_client, expected_header, must_not_have_headers

    lazy_teardown(function()
      helpers.stop_kong()
      helpers.kill_all()
      assert(conf_loader(nil, {}))
    end)

    lazy_setup(function()
      proxy_client = helpers.proxy_client
      helpers.stop_kong()
      helpers.kill_all()
      assert(conf_loader(nil, {}))

      local ef = EntitiesFactory:setup(strategy)
      local pf = PluginFactory:setup(ef)

      expected_header = pf:consumer_service()
      -- adding header-names of plugins that should _not_ be executed
      -- this assits with tracking if a plugin was executed or not
      must_not_have_headers = {}

      -- scoped to Route, Service
      insert(must_not_have_headers, (pf:route_service()))

      -- scoped to route
      insert(must_not_have_headers, (pf:route()))
      -- scoped to serive
      insert(must_not_have_headers, (pf:service()))
      -- scoped to consumer
      insert(must_not_have_headers, (pf:consumer()))
      -- scoped to global
      insert(must_not_have_headers, (pf:global()))

      assert.is_equal(#must_not_have_headers, 5)

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))
    end)

    it("verify precedence", function()
      local r = proxy_client():get("/anything", {
        headers = {
          host = "route.test",
          -- authenticate as `alice`
          apikey = "alice",
        },
      })
      assert.response(r).has.status(200)
      -- verify that the expected plugin was executed
      assert.request(r).has_header(expected_header)
      -- verify that no other plugin was executed that had lesser scopes configured
      for _, header in pairs(must_not_have_headers) do
        assert.request(r).has_no_header(header)
      end
    end)
  end)

  describe("Plugins Iterator - Dual Scoping - #Route #Service on #" .. strategy, function()
    local proxy_client, expected_header, must_not_have_headers

    lazy_teardown(function()
      helpers.stop_kong()
      helpers.kill_all()
      assert(conf_loader(nil, {}))
    end)

    lazy_setup(function()
      proxy_client = helpers.proxy_client
      helpers.stop_kong()
      helpers.kill_all()
      assert(conf_loader(nil, {}))

      local ef = EntitiesFactory:setup(strategy)
      local pf = PluginFactory:setup(ef)

      expected_header = pf:route_service()
      -- adding header-names of plugins that should _not_ be executed
      -- this assits with tracking if a plugin was executed or not
      must_not_have_headers = {}

      -- scoped to route
      insert(must_not_have_headers, (pf:route()))
      -- scoped to serive
      insert(must_not_have_headers, (pf:service()))
      -- scoped to consumer
      insert(must_not_have_headers, (pf:consumer()))
      -- scoped to global
      insert(must_not_have_headers, (pf:global()))

      assert.is_equal(#must_not_have_headers, 4)

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))
    end)

    it("verify precedence", function()
      local r = proxy_client():get("/anything", {
        headers = {
          host = "route.test",
          -- authenticate as `alice`
          apikey = "alice",
        },
      })
      assert.response(r).has.status(200)
      -- verify that the expected plugin was executed
      assert.request(r).has_header(expected_header)
      -- verify that no other plugin was executed that had lesser scopes configured
      for _, header in pairs(must_not_have_headers) do
        assert.request(r).has_no_header(header)
      end
    end)
  end)

  describe("Plugins Iterator - Single coping - #Consumer on #" .. strategy, function()
    local proxy_client, expected_header, must_not_have_headers

    lazy_teardown(function()
      helpers.stop_kong()
      helpers.kill_all()
      assert(conf_loader(nil, {}))
    end)

    lazy_setup(function()
      proxy_client = helpers.proxy_client
      helpers.stop_kong()
      helpers.kill_all()
      assert(conf_loader(nil, {}))

      local ef = EntitiesFactory:setup(strategy)
      local pf = PluginFactory:setup(ef)

      expected_header = pf:consumer()
      -- adding header-names of plugins that should _not_ be executed
      -- this assits with tracking if a plugin was executed or not
      must_not_have_headers = {}

      -- scoped to route
      insert(must_not_have_headers, (pf:route()))
      -- scoped to serive
      insert(must_not_have_headers, (pf:service()))
      -- scoped to global
      insert(must_not_have_headers, (pf:global()))

      assert.is_equal(#must_not_have_headers, 3)

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))
    end)

    it("verify precedence", function()
      local r = proxy_client():get("/anything", {
        headers = {
          host = "route.test",
          -- authenticate as `alice`
          apikey = "alice",
        },
      })
      assert.response(r).has.status(200)
      -- verify that the expected plugin was executed
      assert.request(r).has_header(expected_header)
      -- verify that no other plugin was executed that had lesser scopes configured
      for _, header in pairs(must_not_have_headers) do
        assert.request(r).has_no_header(header)
      end
    end)
  end)

  describe("Plugins Iterator - Single coping - #Route on #" .. strategy, function()
    local proxy_client, expected_header, must_not_have_headers

    lazy_teardown(function()
      helpers.stop_kong()
      helpers.kill_all()
      assert(conf_loader(nil, {}))
    end)

    lazy_setup(function()
      proxy_client = helpers.proxy_client
      helpers.stop_kong()
      helpers.kill_all()
      assert(conf_loader(nil, {}))

      local ef = EntitiesFactory:setup(strategy)
      local pf = PluginFactory:setup(ef)

      expected_header = pf:route()
      -- adding header-names of plugins that should _not_ be executed
      -- this assits with tracking if a plugin was executed or not
      must_not_have_headers = {}

      -- scoped to serive
      insert(must_not_have_headers, (pf:service()))
      -- scoped to global
      insert(must_not_have_headers, (pf:global()))

      assert.is_equal(#must_not_have_headers, 2)

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))
    end)

    it("verify precedence", function()
      local r = proxy_client():get("/anything", {
        headers = {
          host = "route.test",
          -- authenticate as `alice`
          apikey = "alice",
        },
      })
      assert.response(r).has.status(200)
      -- verify that the expected plugin was executed
      assert.request(r).has_header(expected_header)
      -- verify that no other plugin was executed that had lesser scopes configured
      for _, header in pairs(must_not_have_headers) do
        assert.request(r).has_no_header(header)
      end
    end)
  end)

  describe("Plugins Iterator - Single scoping - #single #Service on #" .. strategy, function()
    local proxy_client, expected_header, must_not_have_headers

    lazy_teardown(function()
      helpers.stop_kong()
      helpers.kill_all()
      assert(conf_loader(nil, {}))
    end)

    lazy_setup(function()
      proxy_client = helpers.proxy_client
      helpers.stop_kong()
      helpers.kill_all()
      assert(conf_loader(nil, {}))

      local ef = EntitiesFactory:setup(strategy)
      local pf = PluginFactory:setup(ef)

      expected_header = pf:service()
      -- adding header-names of plugins that should _not_ be executed
      -- this assits with tracking if a plugin was executed or not
      must_not_have_headers = {}

      -- scoped to global
      insert(must_not_have_headers, (pf:global()))

      assert.is_equal(#must_not_have_headers, 1)

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))
    end)

    it("verify precedence", function()
      local r = proxy_client():get("/anything", {
        headers = {
          host = "route.test",
          -- authenticate as `alice`
          apikey = "alice",
        },
      })
      assert.response(r).has.status(200)
      -- verify that the expected plugin was executed
      assert.request(r).has_header(expected_header)
      -- verify that no other plugin was executed that had lesser scopes configured
      for _, header in pairs(must_not_have_headers) do
        assert.request(r).has_no_header(header)
      end
    end)
  end)

  describe("Plugins Iterator - Global scoping on #" .. strategy, function()
    local proxy_client, expected_header, must_not_have_headers

    lazy_teardown(function()
      helpers.stop_kong()
      helpers.kill_all()
      assert(conf_loader(nil, {}))
    end)

    lazy_setup(function()
      proxy_client = helpers.proxy_client
      helpers.stop_kong()
      helpers.kill_all()
      assert(conf_loader(nil, {}))

      local ef = EntitiesFactory:setup(strategy)
      local pf = PluginFactory:setup(ef)

      expected_header = pf:global()
      -- adding header-names of plugins that should _not_ be executed
      -- this assits with tracking if a plugin was executed or not
      must_not_have_headers = {}

      assert.is_equal(#must_not_have_headers, 0)

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))
    end)

    it("verify precedence", function()
      local r = proxy_client():get("/anything", {
        headers = {
          host = "route.test",
          -- authenticate as `alice`
          apikey = "alice",
        },
      })
      assert.response(r).has.status(200)
      -- verify that the expected plugin was executed
      assert.request(r).has_header(expected_header)
      -- verify that no other plugin was executed that had lesser scopes configured
      for _, header in pairs(must_not_have_headers) do
        assert.request(r).has_no_header(header)
      end
    end)
  end)
end
