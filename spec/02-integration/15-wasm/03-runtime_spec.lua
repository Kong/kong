local helpers = require "spec.helpers"

local WASM_FIXTURES_ROOT = "spec/fixtures/proxy_wasm_filters"
local WASM_FIXTURES_TARGET = WASM_FIXTURES_ROOT .. "/target/wasm32-wasi/debug"

local CARGO_BUILD = table.concat({
    "cargo", "build",
      "--manifest-path", WASM_FIXTURES_ROOT .. "/Cargo.toml",
      "--lib ",
      "--target wasm32-wasi"
  }, " ")

local PREFIX = assert(helpers.test_conf.prefix)
local WASM_FILTERS_PATH = PREFIX .. "/proxy_wasm_filters"
local DATABASE = "postgres"
local ERROR_OR_CRIT = "\\[(error|crit)\\]"
local HEADER = "X-PW-Resp-Header-From-Config"

describe("#wasm filter execution", function()
  lazy_setup(function()
    helpers.clean_prefix(PREFIX)
    assert(helpers.dir.makepath(WASM_FILTERS_PATH))

    local env = {
      prefix = PREFIX,
      database = DATABASE,
      nginx_conf = "spec/fixtures/custom_nginx.template",
      wasm = true,
      wasm_filters_path = WASM_FILTERS_PATH,
    }

    assert(helpers.kong_exec("prepare", env))

    assert(helpers.execute(CARGO_BUILD))
    assert(helpers.dir.makepath(WASM_FILTERS_PATH))
    assert(helpers.dir.copyfile(WASM_FIXTURES_TARGET .. "/tests.wasm",
                                WASM_FILTERS_PATH .. "/tests.wasm",
                                true))

    local bp, db = helpers.get_db_utils(DATABASE, {
      "routes",
      "services",
      "wasm_filter_chains",
    })

    db.wasm_filter_chains:load_filters({ { name = "tests" } })

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
          { name = "tests", config = "add_resp_header=service" },
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
          { name = "tests", config = "add_resp_header=route" },
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
          { name = "tests", config = "add_resp_header=route+service" },
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
          { name = "tests", config = "add_resp_header=global" },
        },
      })
    end


    assert(helpers.start_kong(env, nil, true))
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
