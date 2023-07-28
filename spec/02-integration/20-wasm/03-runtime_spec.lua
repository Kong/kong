local helpers = require "spec.helpers"
local cjson = require "cjson"

local HEADER = "X-Proxy-Wasm"

local json = cjson.encode

local function response_transformer(value, disabled)
  return {
    name = "response_transformer",
    enabled = not disabled,
    config = json {
      append = {
        headers = {
          HEADER .. ":" .. value,
        },
      },
    }
  }
end

for _, strategy in helpers.each_strategy({ "postgres", "off" }) do


describe("#wasm filter execution (#" .. strategy .. ")", function()
  lazy_setup(function()
    require("kong.runloop.wasm").enable({
      { name = "tests" },
      { name = "response_transformer" },
    })

    local bp = helpers.get_db_utils("postgres", {
      "routes",
      "services",
      "filter_chains",
    })

    local function service_and_route(name)
      local service = assert(bp.services:insert({
        name = name,
        url = helpers.mock_upstream_url,
      }))

      local route = assert(bp.routes:insert {
        name = name,
        service = { id = service.id },
        paths = { "/" },
        hosts = { name },
      })

      return service, route
    end

    local function create_filter_chain(entity)
      return assert(bp.filter_chains:insert(entity))
    end


    do
      -- a filter chain attached to a service
      local name = "service.test"
      local service = service_and_route(name)
      create_filter_chain({
        service = { id = service.id },
        filters = {
          response_transformer(name),
        }
      })
    end

    do
      -- a filter chain attached to a route
      local name = "route.test"
      local _, route = service_and_route(name)
      create_filter_chain({
        route = { id = route.id },
        filters = {
          response_transformer(name),
        }
      })
    end

    do
      -- service and route each have a filter chain
      local name = "service-and-route.test"
      local service, route = service_and_route(name)

      create_filter_chain({
        service = { id = service.id },
        filters = {
          response_transformer("service"),
        }
      })

      create_filter_chain({
        route = { id = route.id },
        filters = {
          response_transformer("route"),
        }
      })
    end

    do
      -- a disabled filter chain attached to a service
      local name = "service-disabled.test"
      local service = service_and_route(name)
      create_filter_chain({
        enabled = false,
        service = { id = service.id },
        filters = {
          response_transformer(name),
        }
      })
    end

    do
      -- a disabled filter chain attached to a route
      local name = "route-disabled.test"
      local _, route = service_and_route(name)
      create_filter_chain({
        enabled = false,
        route = { id = route.id },
        filters = {
          response_transformer(name),
        }
      })
    end

    do
      -- service filter chain is disabled
      -- route filter chain is enabled
      local name = "service-disabled.route-enabled.test"
      local service, route = service_and_route(name)

      create_filter_chain({
        enabled = false,
        service = { id = service.id },
        filters = {
          response_transformer("service"),
        }
      })

      create_filter_chain({
        enabled = true,
        route = { id = route.id },
        filters = {
          response_transformer("route"),
        }
      })
    end

    do
      -- service filter chain is enabled
      -- route filter chain is disabled
      local name = "service-enabled.route-disabled.test"
      local service, route = service_and_route(name)

      create_filter_chain({
        enabled = true,
        service = { id = service.id },
        filters = {
          response_transformer("service"),
        }
      })

      create_filter_chain({
        enabled = false,
        route = { id = route.id },
        filters = {
          response_transformer("route"),
        }
      })
    end

    do
      -- service and route filter chains both disabled
      local name = "service-disabled.route-disabled.test"
      local service, route = service_and_route(name)

      create_filter_chain({
        enabled = false,
        service = { id = service.id },
        filters = {
          response_transformer("service"),
        }
      })

      create_filter_chain({
        enabled = false,
        route = { id = route.id },
        filters = {
          response_transformer("route"),
        }
      })
    end

    do
      -- service filter chain with one enabled filter and one disabled filter
      local name = "service-partial-disabled.test"
      local service = service_and_route(name)

      create_filter_chain({
        enabled = true,
        service = { id = service.id },
        filters = {
          response_transformer("disabled", true),
          response_transformer("enabled"),
        }
      })
    end

    do
      -- route filter chain with one enabled filter and one disabled filter
      local name = "route-partial-disabled.test"
      local _, route = service_and_route(name)

      create_filter_chain({
        enabled = true,
        route   = { id = route.id },
        filters = {
          response_transformer("disabled", true),
          response_transformer("enabled"),
        }
      })
    end

    do
      -- combined service and route filter chains with some disabled filters
      local name = "combined-partial-disabled.test"
      local service, route = service_and_route(name)

      create_filter_chain({
        enabled = true,
        service = { id = service.id },
        filters = {
          response_transformer("service-enabled"),
          response_transformer("service-disabed", true),
        }
      })

      create_filter_chain({
        enabled = true,
        route = { id = route.id },
        filters = {
          response_transformer("route-disabled", true),
          response_transformer("route-enabled"),
        }
      })
    end

    do
      -- service filter chain with no enabled filters
      local name = "service-fully-disabled.test"
      local service = service_and_route(name)

      create_filter_chain({
        enabled = true,
        service = { id = service.id },
        filters = {
          response_transformer("disabled", true),
          response_transformer("also-disabled", true),
        }
      })
    end

    do
      -- route filter chain with no enabled filters
      local name = "route-fully-disabled.test"
      local _, route = service_and_route(name)

      create_filter_chain({
        enabled = true,
        route   = { id = route.id },
        filters = {
          response_transformer("disabled", true),
          response_transformer("also-disabled", true),
        }
      })
    end

    do
      -- combined service and route filter chain with no enabled filters
      local name = "combined-fully-disabled.test"
      local service, route = service_and_route(name)

      create_filter_chain({
        enabled = true,
        service = { id = service.id },
        filters = {
          response_transformer("service-disabled", true),
          response_transformer("service-also-disabled", true),
        }
      })

      create_filter_chain({
        enabled = true,
        route = { id = route.id },
        filters = {
          response_transformer("route-disabled", true),
          response_transformer("route-also-disabled", true),
        }
      })
    end

    do
      -- combined service and route filter chain with all service filters disabled
      local name = "combined-service-filters-disabled.test"
      local service, route = service_and_route(name)

      create_filter_chain({
        enabled = true,
        service = { id = service.id },
        filters = {
          response_transformer("service-disabled", true),
          response_transformer("service-also-disabled", true),
        }
      })

      create_filter_chain({
        enabled = true,
        route = { id = route.id },
        filters = {
          response_transformer("route-enabled"),
          response_transformer("route-disabled", true),
        }
      })
    end

    do
      -- combined service and route filter chain with all route filters disabled
      local name = "combined-route-filters-disabled.test"
      local service, route = service_and_route(name)

      create_filter_chain({
        enabled = true,
        service = { id = service.id },
        filters = {
          response_transformer("service-disabled", true),
          response_transformer("service-enabled"),
        }
      })

      create_filter_chain({
        enabled = true,
        route = { id = route.id },
        filters = {
          response_transformer("route-disabled", true),
          response_transformer("route-also-disabled", true),
        }
      })
    end


    assert(helpers.start_kong({
      database = strategy,
      declarative_config = strategy == "off"
                       and helpers.make_yaml_file()
                        or nil,

      nginx_conf = "spec/fixtures/custom_nginx.template",

      wasm = true,
    }))
  end)


  lazy_teardown(function()
    helpers.stop_kong(nil, true)
  end)


  local client
  before_each(function()
    helpers.clean_logfile()
    client = helpers.proxy_client()
  end)


  after_each(function()
    if client then client:close() end
  end)


  local function assert_filter(host, expect_header)
    local res = client:get("/", {
      headers = { host = host },
    })

    assert.response(res).has.status(200)
    assert.logfile().has.no.line("[error]", true, 0)
    assert.logfile().has.no.line("[crit]",  true, 0)

    local header = assert.response(res).has.header(HEADER)

    if type(expect_header) == "string" then
      expect_header = { expect_header }
    end

    if type(header) == "string" then
      header = { header }
    end

    assert.same(expect_header, header)
  end


  local function assert_no_filter(host)
    local res = client:get("/", {
      headers = { host = host },
    })

    assert.response(res).has.status(200)
    assert.response(res).has.no.header(HEADER)
  end


  describe("single filter chain", function()
    it("attached to a service", function()
      assert_filter("service.test", "service.test")
    end)

    it("attached to a route", function()
      assert_filter("route.test", "route.test")
    end)
  end)

  describe("multiple filter chains", function()
    it("service and route with their own filter chains", function()
      assert_filter("service-and-route.test", { "service", "route" })
    end)
  end)

  describe("disabled filter chains", function()
    it("attached to a service", function()
      assert_no_filter("service-disabled.test")
    end)

    it("attached to a route", function()
      assert_no_filter("route-disabled.test")
    end)

    it("service disabled, route enabled", function()
      assert_filter("service-disabled.route-enabled.test", "route")
    end)

    it("service enabled, route disabled", function()
      assert_filter("service-enabled.route-disabled.test", "service")
    end)

    it("service disabled, route disabled", function()
      assert_no_filter("service-disabled.route-disabled.test")
    end)
  end)

  describe("disabled filters are not executed", function()
    it("(service)", function()
      assert_filter("service-partial-disabled.test", "enabled")
    end)

    it("(route)", function()
      assert_filter("route-partial-disabled.test", "enabled")
    end)

    it("(combined)", function()
      assert_filter("combined-partial-disabled.test",
                    { "service-enabled", "route-enabled" })

      assert_filter("combined-service-filters-disabled.test",
                    { "route-enabled" })

      assert_filter("combined-route-filters-disabled.test",
                    { "service-enabled" })
    end)

    it("and all filters can be disabled", function()
      assert_no_filter("service-fully-disabled.test")
      assert_no_filter("route-fully-disabled.test")
      assert_no_filter("combined-fully-disabled.test")
    end)
  end)
end)


end -- each strategy
