local helpers = require "spec.helpers"
local cjson = require "cjson"
local nkeys = require "table.nkeys"

local HEADER = "X-Proxy-Wasm"
local TIMEOUT = 20
local STEP = 0.1
local FILTER_PATH = assert(helpers.test_conf.wasm_filters_path)


local json = cjson.encode
local fmt = string.format

local function make_config(src)
  return json {
    append = {
      headers = {
        HEADER .. ":" .. src,
      },
    },
  }
end


-- we must use more than one worker to ensure adequate test coverage
local WORKER_COUNT = 4
local WORKER_ID_HEADER = "X-Worker-Id"

for _, strategy in helpers.each_strategy({ "postgres", "off" }) do

for _, consistency in ipairs({ "eventual", "strict" }) do

local mode_suffix = fmt("(strategy: #%s) (#%s consistency)",
                        strategy, consistency)

describe("#wasm filter chain cache " .. mode_suffix, function()
  local bp

  local hosts = {
    filter     = "filter.test",
    filter_alt = "filter-alt.test",
    no_filter  = "no-filter.test",
  }

  local services = {}
  local routes = {}


  local function assert_no_filter(host, suffix)
    local msg = fmt("response header %q should be absent for all workers",
                    HEADER)
    if suffix then
      msg = msg .. " " .. suffix
    end

    local workers_seen = {}

    helpers.pwait_until(function()
      local client = helpers.proxy_client()
      local res = client:get("/", {
        headers = { host = host },
      })

      assert.response(res).has.status(200)
      client:close()

      assert.response(res).has.no_header(HEADER)

      -- ensure that we've received the correct response from each
      -- worker at least once
      local worker_id = assert.response(res).has.header(WORKER_ID_HEADER)
      workers_seen[worker_id] = true
      assert.same(WORKER_COUNT, nkeys(workers_seen), msg)
    end, TIMEOUT, STEP)
  end


  local function assert_filters(host, exp, suffix)
    local msg = fmt("response header %q should be equal to %q for all workers",
                    HEADER, table.concat(exp, ","))

    if suffix then
      msg = msg .. " " .. suffix
    end

    local workers_seen = {}

    helpers.pwait_until(function()
      local client = helpers.proxy_client()

      local res = client:get("/", {
        headers = { host = host },
      })

      assert.response(res).has.status(200)
      client:close()

      local header = res.headers[HEADER]
      assert.not_nil(header, msg)

      if type(header) == "string" then
        header = { header }
      end

      if type(exp) == "string" then
        exp = { exp }
      end

      assert.same(exp, header, msg)

      -- ensure that we've received the correct response from each
      -- worker at least once
      local worker_id = assert.response(res).has.header(WORKER_ID_HEADER)
      workers_seen[worker_id] = true
      assert.same(WORKER_COUNT, nkeys(workers_seen), msg)
    end, TIMEOUT, STEP)
  end


  lazy_setup(function()
    require("kong.runloop.wasm").enable({
      { name = "tests",
        path = FILTER_PATH .. "/tests.wasm",
      },
      { name = "response_transformer",
        path = FILTER_PATH .. "/response_transformer.wasm",
      },
    })

    helpers.get_db_utils(strategy, {
      "services",
      "routes",
      "filter_chains",
    })

    assert(helpers.start_kong({
      database = strategy,
      declarative_config_string = strategy == "off"
                                  and cjson.encode({ _format_version = "3.0" })
                                  or nil,

      nginx_conf = "spec/fixtures/custom_nginx.template",
      wasm = true,

      nginx_main_worker_processes = WORKER_COUNT,

      worker_consistency = consistency,
      worker_state_update_frequency = 0.25,

      proxy_listen = fmt("%s:%s reuseport",
                         helpers.get_proxy_ip(),
                         helpers.get_proxy_port()),
    }))

    if strategy == "off" then
      bp = require("spec.fixtures.dc_blueprints").admin_api(helpers.db)
    else
      bp = require("spec.fixtures.admin_api")
    end

    services.filter = bp.services:insert({ name = hosts.filter })
    services.no_filter = bp.services:insert({ name = hosts.no_filter })

    routes.filter = bp.routes:insert({
      name = hosts.filter,
      service = services.filter,
      hosts = { hosts.filter },
      paths = { "/" },
    })

    routes.filter_alt = bp.routes:insert({
      name = hosts.filter_alt,
      service = services.filter,
      hosts = { hosts.filter_alt },
      paths = { "/" },
    })

    routes.no_filter = bp.routes:insert({
      name = hosts.no_filter,
      service = services.no_filter,
      hosts = { hosts.no_filter },
      paths = { "/" },
    })

    assert(bp.plugins:insert({
      name = "pre-function",
      config = {
        rewrite = {[[
          kong.response.set_header(
            "]] .. WORKER_ID_HEADER .. [[",
            ngx.worker.id() or -1
          )
        ]]}
      }
    }))



  end)


  lazy_teardown(function()
    helpers.stop_kong()
  end)


  before_each(function()
    helpers.clean_logfile()
    assert(bp.filter_chains:truncate())

    -- sanity
    assert_no_filter(hosts.no_filter, "(test setup)")
  end)


  it("is invalidated on filter creation and removal", function()
    assert_no_filter(hosts.filter, "(initial test)")

    local service_chain = bp.filter_chains:insert({
      service = services.filter,
      filters = {
        { name = "response_transformer",
          config = make_config("service")
        },
      }
    })

    assert_filters(hosts.filter, { "service" },
                   "after adding a service filter chain")

    local route_chain = bp.filter_chains:insert({
      route = routes.filter,
      filters = {
        { name = "response_transformer",
          config = make_config("route")
        },
      }
    })

    assert_filters(hosts.filter, { "service", "route" },
                   "after adding a route filter chain")

    bp.filter_chains:remove({ id = route_chain.id })
    assert_filters(hosts.filter, { "service" },
                   "after removing the route filter chain")

    bp.filter_chains:remove({ id = service_chain.id })

    assert_no_filter(hosts.filter,
                     "after removing all relevant filter chains")
  end)

  it("is invalidated on update when a filter chain is enabled/disabled", function()
    assert_no_filter(hosts.filter, "(initial test)")

    local service_chain = bp.filter_chains:insert({
      enabled = false,
      service = services.filter,
      filters = {
        { name = "response_transformer",
          config = make_config("service")
        },
      }
    })

    local route_chain = bp.filter_chains:insert({
      enabled = false,
      route = routes.filter,
      filters = {
        { name = "response_transformer",
          config = make_config("route")
        },
      }
    })

    -- sanity
    assert_no_filter(hosts.filter, "after adding disabled filter chains")

    assert(bp.filter_chains:update(service_chain.id, { enabled = true }))

    assert_filters(hosts.filter, { "service" },
                   "after enabling the service filter chain")


    assert(bp.filter_chains:update(route_chain.id, { enabled = true }))

    assert_filters(hosts.filter, { "service", "route" },
                   "after enabling the route filter chain")


    assert(bp.filter_chains:update(route_chain.id, { enabled = false }))

    assert_filters(hosts.filter, { "service" },
                   "after disabling the route filter chain")


    assert(bp.filter_chains:update(service_chain.id, { enabled = false }))

    assert_no_filter(hosts.filter, "after disabling all filter chains")
  end)

  it("is invalidated on update when filters are added/removed", function()
    local service_chain = bp.filter_chains:insert({
      service = services.filter,
      filters = {
        { name = "response_transformer",
          config = make_config("service")
        },
      }
    })

    assert_filters(hosts.filter, { "service" },
                   "after enabling a service filter chain")

    assert(bp.filter_chains:update(service_chain.id, {
      filters = {
        { name = "response_transformer",
          config = make_config("service")
        },

        { name = "response_transformer",
          config = make_config("new")
        },
      }
    }))

    assert_filters(hosts.filter, { "service", "new" },
                   "after adding a filter to the service filter chain")

    assert(bp.filter_chains:update(service_chain.id, {
      filters = {
        { name = "response_transformer",
          config = make_config("new")
        },
      }
    }))

    assert_filters(hosts.filter, { "new" },
                   "after removing a filter from the service filter chain")
  end)

  it("is invalidated when filters are enabled/disabled", function()
    local service_chain = bp.filter_chains:insert({
      service = services.filter,
      filters = {
        { name = "response_transformer",
          config = make_config("service"),
          enabled = true,
        },

        { name = "response_transformer",
          config = make_config("other"),
          enabled = true,
        },
      }
    })

    assert_filters(hosts.filter, { "service", "other" },
                   "after enabling a service filter chain")

    service_chain.filters[1].enabled = false
    assert(bp.filter_chains:update(service_chain.id, service_chain))

    assert_filters(hosts.filter, { "other" },
                   "after disabling a filter in the chain")

    service_chain.filters[1].enabled = true
    service_chain.filters[2].enabled = false
    assert(bp.filter_chains:update(service_chain.id, service_chain))
    assert_filters(hosts.filter, { "service" },
                   "after changing the enabled filters in the chain")

    service_chain.filters[1].enabled = false
    service_chain.filters[2].enabled = false
    assert(bp.filter_chains:update(service_chain.id, service_chain))

    assert_no_filter(hosts.filter, "after disabling all filters in the chain")
  end)

  it("is invalidated when filters are re-ordered", function()
    local service_chain = bp.filter_chains:insert({
      service = services.filter,
      filters = {
        { name = "response_transformer",
          config = make_config("first"),
          enabled = true,
        },

        { name = "response_transformer",
          config = make_config("middle"),
          enabled = true,
        },

        { name = "response_transformer",
          config = make_config("last"),
          enabled = true,
        },
      }
    })

    assert_filters(hosts.filter, { "first", "middle", "last" },
                   "after enabling a service filter chain")

    service_chain.filters[1], service_chain.filters[3]
      = service_chain.filters[3], service_chain.filters[1]

    assert(bp.filter_chains:update(service_chain.id, service_chain))

    assert_filters(hosts.filter, { "last", "middle", "first" },
                   "after re-ordering the filter chain items")
  end)


  it("is invalidated when filter configuration is changed", function()
    local service_chain = bp.filter_chains:insert({
      service = services.filter,
      filters = {
        { name = "response_transformer",
          config = make_config("before"),
          enabled = true,
        },
      }
    })

    assert_filters(hosts.filter, { "before" },
                   "after enabling a service filter chain")

    service_chain.filters[1].config = make_config("after")
    assert(bp.filter_chains:update(service_chain.id, service_chain))

    assert_filters(hosts.filter, { "after" },
                   "after enabling a service filter chain")
  end)
end)


end -- each consistency

end -- each strategy
