local helpers = require "spec.helpers"
local cjson = require "cjson"
local wasm_fixtures = require "spec.fixtures.wasm"
local admin = require "spec.fixtures.admin_api"

local DATABASE = "postgres"
local HEADER = "X-Proxy-Wasm"
local TIMEOUT = 10
local STEP = 0.25


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

local function same(exp, got, no_sort)
  if type(exp) ~= "table" then exp = { exp } end
  if type(got) ~= "table" then got = { got } end

  if not no_sort then
    table.sort(exp)
    table.sort(got)
  end

  exp = table.concat(exp, ",")
  got = table.concat(got, ",")

  if exp ~= got then
    return false, { expected = exp, got = got }
  end

  return true
end

local WORKER_PROFILES = {
  single = 1,
  multi = 4,
}

for NAME, WORKER_COUNT in pairs(WORKER_PROFILES) do


describe("#wasm filter chain cache (" .. NAME .. " worker)", function()
  local client
  local db
  local api = admin.wasm_filter_chains

  local hosts = {
    filter     = "filter.test",
    filter_alt = "filter-alt.test",
    no_filter  = "no-filter.test",
  }

  local services = {}
  local routes = {}


  local function assert_no_filter(host, suffix)
    local condition = fmt("response header %q is absent", HEADER)
    if suffix then
      condition = condition .. " " .. suffix
    end

    helpers.wait_until(function()
      local res = client:get("/", {
        headers = { host = host },
      })

      assert.response(res).has.status(200)
      local headers = assert.is_table(res.headers)

      return same({}, headers[HEADER])
    end, TIMEOUT, STEP, condition)
  end


  local function assert_filters(host, filters, suffix, no_sort)
    if not no_sort then
      table.sort(filters)
    end

    local condition = fmt("response header %q is equal to %q",
                          HEADER, table.concat(filters, ","))

    if suffix then
      condition = condition .. " " .. suffix
    end

    helpers.wait_until(function()
      local res = client:get("/", {
        headers = { host = host },
      })

      assert.response(res).has.status(200)
      local headers = assert.is_table(res.headers)
      local header = headers[HEADER]

      return same(filters, header, no_sort)
    end, TIMEOUT, STEP, condition)
  end


  lazy_setup(function()
    local bp
    bp, db = helpers.get_db_utils(DATABASE, {
      "services",
      "routes",
      "wasm_filter_chains",
    })

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

    wasm_fixtures.build()

    assert(helpers.start_kong({
      database = DATABASE,
      nginx_conf = "spec/fixtures/custom_nginx.template",
      wasm = true,
      wasm_filters_path = wasm_fixtures.TARGET_PATH,

      nginx_main_worker_processes = WORKER_COUNT,
    }))

    client = helpers.proxy_client()
  end)


  lazy_teardown(function()
    if client then client:close() end
    helpers.stop_kong(nil, true)
  end)


  before_each(function()
    helpers.clean_logfile()
    db.wasm_filter_chains:truncate()

    -- sanity
    assert_no_filter(hosts.no_filter, "(test setup)")
  end)


  it("is invalidated on global filter creation and removal", function()
    assert_no_filter(hosts.filter, "(initial test)")

    local global_chain = api:insert({
      filters = {
        { name = "response_transformer",
          config = make_config("global")
        },
      }
    })

    assert_filters(hosts.filter, { "global" },
                   "after adding a global filter chain")

    local service_chain = api:insert({
      service = services.filter,
      filters = {
        { name = "response_transformer",
          config = make_config("service")
        },
      }
    })

    assert_filters(hosts.filter, { "service" },
                   "after adding a service filter chain")

    local route_chain = api:insert({
      route = routes.filter,
      filters = {
        { name = "response_transformer",
          config = make_config("route")
        },
      }
    })

    assert_filters(hosts.filter, { "route" },
                   "after adding a route filter chain")

    api:remove({ id = route_chain.id })
    assert_filters(hosts.filter, { "service" },
                   "after removing the route filter chain")

    api:remove({ id = service_chain.id })
    assert_filters(hosts.filter, { "global" },
                   "after removing the service filter chain")

    api:remove({ id = global_chain.id })
    assert_no_filter(hosts.filter,
                     "after removing all relevant filter chains")
  end)

  it("is invalidated on update when a filter chain is enabled/disabled", function()
    assert_no_filter(hosts.filter, "(initial test)")

    local global_chain = api:insert({
      enabled = false,
      filters = {
        { name = "response_transformer",
          config = make_config("global")
        },
      }
    })

    local service_chain = api:insert({
      enabled = false,
      service = services.filter,
      filters = {
        { name = "response_transformer",
          config = make_config("service")
        },
      }
    })

    local route_chain = api:insert({
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


    assert(api:update(global_chain.id, { enabled = true }))

    assert_filters(hosts.filter, { "global" },
                   "after enabling the global filter chain")


    assert(api:update(service_chain.id, { enabled = true }))

    assert_filters(hosts.filter, { "service" },
                   "after enabling the service filter chain")


    assert(api:update(route_chain.id, { enabled = true }))

    assert_filters(hosts.filter, { "route" },
                   "after enabling the route filter chain")


    assert(api:update(route_chain.id, { enabled = false }))

    assert_filters(hosts.filter, { "service" },
                   "after disabling the route filter chain")


    assert(api:update(service_chain.id, { enabled = false }))

    assert_filters(hosts.filter, { "global" },
                   "after disabling the service filter chain")


    assert(api:update(global_chain.id, { enabled = false }))

    assert_no_filter(hosts.filter, "after disabling all filter chains")
  end)

  it("is invalidated on update when filters are added/removed", function()
    local service_chain = api:insert({
      service = services.filter,
      filters = {
        { name = "response_transformer",
          config = make_config("service")
        },
      }
    })

    assert_filters(hosts.filter, { "service" },
                   "after enabling a service filter chain")

    assert(api:update(service_chain.id, {
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

    assert(api:update(service_chain.id, {
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
    local service_chain = api:insert({
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
    assert(api:update(service_chain.id, service_chain))

    assert_filters(hosts.filter, { "other" },
                   "after disabling a filter in the chain")

    service_chain.filters[1].enabled = true
    service_chain.filters[2].enabled = false
    assert(api:update(service_chain.id, service_chain))
    assert_filters(hosts.filter, { "service" },
                   "after changing the enabled filters in the chain")

    service_chain.filters[1].enabled = false
    service_chain.filters[2].enabled = false
    assert(api:update(service_chain.id, service_chain))

    assert_no_filter(hosts.filter, "after disabling all filters in the chain")
  end)

  it("is invalidated when filters are re-ordered", function()
    local service_chain = api:insert({
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
                   "after enabling a service filter chain", true)

    service_chain.filters[1], service_chain.filters[3]
      = service_chain.filters[3], service_chain.filters[1]

    assert(api:update(service_chain.id, service_chain))

    assert_filters(hosts.filter, { "last", "middle", "first" },
                   "after re-ordering the filter chain items", true)
  end)


  it("is invalidated when filter configuration is changed", function()
    local service_chain = api:insert({
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
    assert(api:update(service_chain.id, service_chain))

    assert_filters(hosts.filter, { "after" },
                   "after enabling a service filter chain")
  end)
end)

end -- for each WORKER_PROFILE
