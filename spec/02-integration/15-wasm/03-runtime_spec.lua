local helpers = require "spec.helpers"
local cjson = require "cjson"
local wasm_fixtures = require "spec.fixtures.wasm"

local DATABASE = "postgres"
local ERROR_OR_CRIT = "\\[(error|crit)\\]"
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


describe("#wasm filter execution", function()
  lazy_setup(function()
    local bp, db = helpers.get_db_utils(DATABASE, {
      "routes",
      "services",
      "wasm_filter_chains",
    })


    db.wasm_filter_chains:load_filters({
      { name = "tests" },
      { name = "response_transformer" },
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
      return assert(db.wasm_filter_chains:insert(entity))
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


    wasm_fixtures.build()

    assert(helpers.start_kong({
      database = DATABASE,
      nginx_conf = "spec/fixtures/custom_nginx.template",
      wasm = true,
      wasm_filters_path = wasm_fixtures.TARGET_PATH,
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
    assert.logfile().has.no.line(ERROR_OR_CRIT)

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
end)
