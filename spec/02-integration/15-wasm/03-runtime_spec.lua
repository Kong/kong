local helpers = require "spec.helpers"
local cjson = require "cjson"
local wasm_fixtures = require "spec.fixtures.wasm"

local DATABASE = "postgres"
local ERROR_OR_CRIT = "\\[(error|crit)\\]"
local HEADER = "X-Proxy-Wasm"

local json = cjson.encode

local function make_config(src)
  return json {
    append = {
      headers = {
        HEADER .. ":" .. src,
      },
    },
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

    do
      local name = "service-attach.test"
      local service = assert(bp.services:insert {
        name = name,
        url = helpers.mock_upstream_url,
      })

      assert(bp.routes:insert {
        name = name,
        service = service,
        strip_path = true,
        paths = { "/" },
        hosts = { name },
      })

      assert(db.wasm_filter_chains:insert {
        name = name,
        service = { id = service.id },
        filters = {
          { name = "response_transformer",
            config = make_config("service"),
          },
        },
      })
    end

    do
      local name = "route-attach.test"
      local service = assert(bp.services:insert {
        name = name,
        url = helpers.mock_upstream_url,
      })

      local route = assert(bp.routes:insert {
        name = name,
        service = service,
        strip_path = true,
        paths = { "/" },
        hosts = { name },
      })

      assert(db.wasm_filter_chains:insert {
        name = name,
        route = { id = route.id },
        filters = {
          { name = "response_transformer",
            config = make_config("route"),
          },
        },
      })
    end

    do
      local name = "route-service-attach.test"
      local service = assert(bp.services:insert {
        name = name,
        url = helpers.mock_upstream_url,
      })

      local route = assert(bp.routes:insert {
        name = name,
        service = service,
        strip_path = true,
        paths = { "/" },
        hosts = { name },
      })

      assert(db.wasm_filter_chains:insert {
        name = name,
        route = { id = route.id },
        service = { id = service.id },
        filters = {
          { name = "response_transformer",
            config = make_config("route+service"),
          },
        },
      })
    end

    do
      local name = "global-attach.test"
      local service = assert(bp.services:insert {
        name = name,
        url = helpers.mock_upstream_url,
      })

      assert(bp.routes:insert {
        name = name,
        service = service,
        strip_path = true,
        paths = { "/" },
        hosts = { name },
      })

      assert(db.wasm_filter_chains:insert {
        name = name,
        filters = {
          { name = "response_transformer",
            config = make_config("global"),
          },
        },
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

  local function test_it(host, expect_header)
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

      -- the order of filter execution doesn't seem to be stable, so
      -- we need to sort the headers
      table.sort(expect_header)
      table.sort(header)

      assert.same(expect_header, header)
  end

  describe("runs a filter chain", function()
    it("attached to a service", function()
      test_it("service-attach.test", { "service", "global" })
    end)

    it("attached to a route", function()
      test_it("route-attach.test", { "route", "global" })
    end)

    it("attached to a service and a route", function()
      test_it("route-service-attach.test", { "route+service", "global" })
    end)

    it("attached globally", function()
      test_it("global-attach.test", { "global" })
    end)
  end)
end)
