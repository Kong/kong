local helpers = require "spec.helpers"
local cjson = require "cjson"
local nkeys = require "table.nkeys"

local HEADER = "X-Proxy-Wasm"
local TIMEOUT = 20
local STEP = 0.1


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


local function update_yaml_config()
  local fname = helpers.make_yaml_file()
  local yaml = assert(helpers.file.read(fname))

  local client = helpers.admin_client()

  local res = client:post("/config", {
    headers = { ["Content-Type"] = "text/yaml" },
    body = yaml,
  })

  assert.response(res).has.status(201)

  client:close()
end


local function declarative_api_functions(db)
  local dao = db.filter_chains

  local insert = function(entity)
    local res = assert(dao:insert(entity))
    update_yaml_config()
    return res
  end

  local update = function(id, updates)
    if type(id) == "string" then
      id = { id = id }
    end
    local res = assert(dao:update(id, updates))
    update_yaml_config()
    return res
  end

  local delete = function(id)
    if type(id) == "string" then
      id = { id = id }
    end
    local res = assert(dao:delete(id))
    update_yaml_config()
    return res
  end

  return insert, update, delete
end


local function db_api_functions()
  local api = require("spec.fixtures.admin_api").filter_chains

  local insert = function(entity)
    return assert(api:insert(entity))
  end

  local update = function(id, updates)
    return assert(api:update(id, updates))
  end

  local delete = function(id)
    local _, err = api:remove(id)
    assert(not err, err)
  end

  return insert, update, delete
end


local function make_api(strategy, db)
  if strategy == "off" then
    return declarative_api_functions(db)
  end

  return db_api_functions()
end


-- we must use more than one worker to ensure adequate test coverage
local WORKER_COUNT = 4
local WORKER_ID_HEADER = "X-Worker-Id"

for _, strategy in ipairs({ "postgres", "off"}) do

for _, consistency in ipairs({ "eventual", "strict" }) do

local mode_suffix = fmt("(strategy: #%s) (#%s consistency)",
                   strategy, consistency)

describe("#wasm filter chain cache " .. mode_suffix, function()
  local db

  local insert, update, delete

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
      { name = "tests" },
      { name = "response_transformer" },
    })

    local bp
    bp, db = helpers.get_db_utils("postgres", {
      "services",
      "routes",
      "filter_chains",
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

    assert(bp.plugins:insert({
      name = "pre-function",
      config = {
        rewrite = {[[
          kong.response.set_header(
            "]] .. WORKER_ID_HEADER .. [[",
            ngx.worker.id()
          )
        ]]}
      }
    }))


    insert, update, delete = make_api(strategy, db)


    assert(helpers.start_kong({
      database = strategy,
      declarative_config = strategy == "off"
                       and helpers.make_yaml_file()
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
  end)


  lazy_teardown(function()
    helpers.stop_kong(nil, true)
  end)


  before_each(function()
    helpers.clean_logfile()
    db.filter_chains:truncate()

    -- sanity
    assert_no_filter(hosts.no_filter, "(test setup)")
  end)


  it("is invalidated on filter creation and removal", function()
    assert_no_filter(hosts.filter, "(initial test)")

    local service_chain = insert({
      service = services.filter,
      filters = {
        { name = "response_transformer",
          config = make_config("service")
        },
      }
    })

    assert_filters(hosts.filter, { "service" },
                   "after adding a service filter chain")

    local route_chain = insert({
      route = routes.filter,
      filters = {
        { name = "response_transformer",
          config = make_config("route")
        },
      }
    })

    assert_filters(hosts.filter, { "service", "route" },
                   "after adding a route filter chain")

    delete({ id = route_chain.id })
    assert_filters(hosts.filter, { "service" },
                   "after removing the route filter chain")

    delete({ id = service_chain.id })

    assert_no_filter(hosts.filter,
                     "after removing all relevant filter chains")
  end)

  it("is invalidated on update when a filter chain is enabled/disabled", function()
    assert_no_filter(hosts.filter, "(initial test)")

    local service_chain = insert({
      enabled = false,
      service = services.filter,
      filters = {
        { name = "response_transformer",
          config = make_config("service")
        },
      }
    })

    local route_chain = insert({
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

    assert(update(service_chain.id, { enabled = true }))

    assert_filters(hosts.filter, { "service" },
                   "after enabling the service filter chain")


    assert(update(route_chain.id, { enabled = true }))

    assert_filters(hosts.filter, { "service", "route" },
                   "after enabling the route filter chain")


    assert(update(route_chain.id, { enabled = false }))

    assert_filters(hosts.filter, { "service" },
                   "after disabling the route filter chain")


    assert(update(service_chain.id, { enabled = false }))

    assert_no_filter(hosts.filter, "after disabling all filter chains")
  end)

  it("is invalidated on update when filters are added/removed", function()
    local service_chain = insert({
      service = services.filter,
      filters = {
        { name = "response_transformer",
          config = make_config("service")
        },
      }
    })

    assert_filters(hosts.filter, { "service" },
                   "after enabling a service filter chain")

    assert(update(service_chain.id, {
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

    assert(update(service_chain.id, {
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
    local service_chain = insert({
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
    assert(update(service_chain.id, service_chain))

    assert_filters(hosts.filter, { "other" },
                   "after disabling a filter in the chain")

    service_chain.filters[1].enabled = true
    service_chain.filters[2].enabled = false
    assert(update(service_chain.id, service_chain))
    assert_filters(hosts.filter, { "service" },
                   "after changing the enabled filters in the chain")

    service_chain.filters[1].enabled = false
    service_chain.filters[2].enabled = false
    assert(update(service_chain.id, service_chain))

    assert_no_filter(hosts.filter, "after disabling all filters in the chain")
  end)

  it("is invalidated when filters are re-ordered", function()
    local service_chain = insert({
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

    assert(update(service_chain.id, service_chain))

    assert_filters(hosts.filter, { "last", "middle", "first" },
                   "after re-ordering the filter chain items")
  end)


  it("is invalidated when filter configuration is changed", function()
    local service_chain = insert({
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
    assert(update(service_chain.id, service_chain))

    assert_filters(hosts.filter, { "after" },
                   "after enabling a service filter chain")
  end)
end)


end -- each consistency

end -- each strategy
