describe("ee proxies", function()
  local singletons = require "kong.singletons"
  local ee_proxies

  local mock_plugins_dao = {
    plugins = {
      model_mt = function(plugin_config)
        setmetatable(plugin_config, {
          __index = {
            validate = function ()
              return true
            end
          }
        })
        return plugin_config, nil
      end
    }
  }

  setup(function()
    singletons.configuration = {}
    singletons.dao = mock_plugins_dao

    ee_proxies = require "kong.enterprise_edition.proxies"
  end)

  after_each(function()
    singletons.configuration = {}
    singletons.dao = mock_plugins_dao
  end)

  teardown(function()
    singletons = nil -- luacheck: ignore
  end)

  describe("new()", function()
    it("should properly start with no configuration", function()
      local proxies = ee_proxies.new()

      assert.truthy(proxies)
      assert.truthy(proxies.config)
      assert.equal(#proxies.config.services, 0)
    end)

    it("should configure zero services with empty config", function()
      local proxies = ee_proxies.new()

      assert.equal(#proxies.config.services, 0)
    end)

    it("should accept custom config as an option", function()
      local proxies = ee_proxies.new({
        services = {
          {
            id = "0000",
            name = "one",
          }
        },

        routes = {
          {
            paths = { "/two" },
            service = "one",
          }
        },

        plugins = {
          {
            name = "three",
            service = "one",
          }
        }
      })

      assert.equal(proxies.config.services["0000"].name, "one")
      assert.equal(proxies.config.services.one.name, "one")


      assert.is_true(#proxies.config.routes > 0)
      local route_verified = false
      for _, route in ipairs(proxies.config.routes) do
        if route.service.id == "0000" then
          assert.same({ "/two" }, route.paths)
          route_verified = true
        end
      end

      assert.is_true(route_verified)

      local plugin_verified = false
      for _, plugin in ipairs(proxies.config.plugins) do
        if plugin.name == "three" then
          assert.same("0000", plugin.service_id)
          plugin_verified = true
        end
      end

      assert.is_true(plugin_verified)
    end)
  end)

  describe("add_service()", function()
    it("should error with no config", function()
      local proxies = ee_proxies.new()

      assert.has.errors(function()
        proxies:add_service()
      end)
    end)

    it("should error with invalid config", function()
      local proxies = ee_proxies.new()

      assert.has.errors(function()
        proxies:add_service({
          port = 8001
        })
      end)
    end)

    it("should add a service with valid config", function()
      local proxies = ee_proxies.new()

      proxies:add_service({
        id = "0000",
        name = "internal_service",
        port = 8001
      })

      assert.truthy(proxies.config.services.internal_service)
      assert.truthy(proxies.config.services["0000"])
      assert.equal(proxies.config.services.internal_service.port, 8001)
    end)

    it("should properly parse passed url field", function()
      local proxies = ee_proxies.new()

      proxies:add_service({
        id = "0000",
        name = "internal_service",
        url = "http://local.dev:8000"
      })

      assert.truthy(proxies.config.services.internal_service)
      assert.equal(proxies.config.services.internal_service.protocol, "http")
      assert.equal(proxies.config.services.internal_service.host, "local.dev")
      assert.equal(proxies.config.services.internal_service.port, 8000)
    end)
  end)

  describe("has_service()", function()
    it("should lookup an existing service", function()
      local proxies = ee_proxies.new()

      proxies:add_service({
        id = "0000",
        name = "internal_service",
        url = "http://local.dev:8000"
      })

      assert.truthy(proxies:has_service("0000"))
    end)
  end)

  describe("add_route()", function()
    it("should add a route", function()
      local proxies = ee_proxies.new()

      proxies:add_route({
        paths = { "/hello" },
        id = "1111",
      })

      assert.is_true(#proxies.config.routes > 0)
      local route_verified = false
      for _, route in ipairs(proxies.config.routes) do
        if route.id == "1111" then
          assert.same({ "/hello" }, route.paths)
          route_verified = true
        end
      end

      assert.is_true(route_verified)
    end)
  end)

  describe("filter_plugins()", function()
    it("should filter global plugins when service_id is internal", function()
      local proxies = ee_proxies.new()

      proxies:add_service({
        id = "0000",
        name = "internal_service",
        url = "http://local.dev:8000"
      })

      local request_plugins = proxies:filter_plugins("0000", {
        {
          name = "global_plugin"
        }
      })

      assert.equal(#request_plugins, 0)
    end)

    it("should not filter global plugins when service_id is external", function()
      local proxies = ee_proxies.new()

      proxies:add_service({
        id = "0000",
        name = "internal_service",
        url = "http://local.dev:8000"
      })

      local request_plugins = proxies:filter_plugins("0001", {
        {
          name = "global_plugin"
        }
      })

      assert.equal(#request_plugins, 1)
    end)

    it("should not filter internal plugins when service_id is internal", function()
      local proxies = ee_proxies.new()

      proxies:add_service({
        id = "0000",
        name = "internal_service",
        url = "http://local.dev:8000"
      })

      local request_plugins = proxies:filter_plugins("0000", {
        {
          name = "internal_plugin",
          service_id = "0000"
        }
      })

      assert.equal(#request_plugins, 1)
    end)
  end)

  describe("setup_portal()", function()
    it("should not generate portal config when disabled", function()
      local proxies = ee_proxies.new()

      proxies:setup_portal()

      -- only configured service is admin
      assert.is_nil(proxies.config.services.__kong_portal_api)

      local route_exists = false
      assert.is_true(#proxies.config.routes > 0)
      for _, route in ipairs(proxies.config.routes) do
        if route.id == "00000000-0000-0000-0002-000000000000" then
          route_exists = true
        end
      end
      assert.is_false(route_exists)

      local plugin_exists = false
      for _, plugin in ipairs(proxies.config.plugins) do
        if plugin.service_id == "00000000-0000-0000-0000-000000000001" then
          plugin_exists = true
        end
      end
      assert.is_false(plugin_exists)
    end)

    it("should generate config when enabled", function()
      local proxies = ee_proxies.new()

      singletons.configuration = {
        portal = true
      }

      proxies:setup_portal()

      assert.truthy(proxies.config.services["00000000-0000-0000-0000-000000000001"])
      assert.truthy(proxies.config.services.__kong_portal_api)
      assert.equal(proxies.config.services.__kong_portal_api.id,
        "00000000-0000-0000-0000-000000000001")

      local route_verified = false
      assert.is_true(#proxies.config.routes > 0)
      for _, route in ipairs(proxies.config.routes) do
        if route.id == "00000000-0000-0000-0002-000000000000" then
          assert.same({ "/_kong/portal" }, route.paths)
          assert.same("00000000-0000-0000-0000-000000000001", route.service.id)
          route_verified = true
        end
      end
      assert.is_true(route_verified)

      local plugin_verified = false
      for _, plugin in ipairs(proxies.config.plugins) do
        if plugin.service_id == "00000000-0000-0000-0000-000000000001" then
          assert.same("cors", plugin.name)
          plugin_verified = true
        end
      end
      assert.is_true(plugin_verified)
    end)
  end)

  describe("setup_admin()", function()
    it("should generate config", function()
      local proxies = ee_proxies.new()

      assert.is_not_nil(proxies.config.services["00000000-0000-0000-0000-000000000005"])
      assert.is_not_nil(proxies.config.services.__kong_admin_api)
      assert.same("00000000-0000-0000-0000-000000000005",
                  proxies.config.services.__kong_admin_api.id)

      assert.is_true(#proxies.config.routes > 0)

      local route_verified = false
      for _, route in ipairs(proxies.config.routes) do
        if route.service.id == "00000000-0000-0000-0000-000000000005" then
          assert.same({ "/_kong/admin" }, route.paths)
          route_verified = true
        end
      end
      assert.is_true(route_verified)

      local plugin_verified = false
      for _, plugin in ipairs(proxies.config.plugins) do
        if plugin.service_id == "00000000-0000-0000-0000-000000000005" then
          assert.same("cors", plugin.name)
          plugin_verified = true
        end
      end
      assert.is_true(plugin_verified)
    end)
  end)

  describe("add_internal_plugins()", function()
    it("should not add plugins when none exist", function()
      local proxies = ee_proxies.new()
      local plugins = {}

      proxies:add_internal_plugins(plugins)

      assert.equal(#plugins, 0)
    end)

    it("should add plugins when they exist", function()
      local proxies = ee_proxies.new()
      local plugins = {}

      singletons.dao = mock_plugins_dao
      singletons.configuration = {
        proxy_listen = true
      }

      proxies:add_service({
        id = "0000",
        name = "internal_service",
        port = 8004
      })

      proxies:add_plugin({
        service = "internal_service",
        name = "internal_plugin"
      })

      local expected = #proxies.config.plugins

      proxies:add_internal_plugins(plugins, {})

      assert.equal(expected, #plugins)
    end)

    it("should not add plugins when already exist in map", function()
      local proxies = ee_proxies.new()
      local plugins = {}

      singletons.dao = mock_plugins_dao
      singletons.configuration = {
        proxy_listen = true
      }

      proxies:add_service({
        id = "0000",
        name = "internal_service",
        port = 8004
      })

      proxies:add_plugin({
        service = "internal_service",
        name = "internal_plugin"
      })

      local expected = #proxies.config.plugins

      proxies:add_internal_plugins(plugins, {
        "internal_plugin"
      })

      assert.equal(expected, #plugins)
    end)
  end)
end)
