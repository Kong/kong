local helpers = require "spec.helpers"
local cjson = require "cjson"
local rand = require "kong.tools.rand"
local uuid = require "kong.tools.uuid"

local FILTER_HEADER = "X-Wasm-Filter-Plugin"
local PLUGIN_HEADER = "X-Lua-Plugin"
local FILTER_CHAIN_HEADER = "X-Wasm-Filter-Chain"

local FILTER_PATH = assert(helpers.test_conf.wasm_filters_path)

local function json_request(data)
  return {
    headers = {
      ["Content-Type"] = "application/json",
    },
    body = cjson.encode(data),
  }
end

local function rt_config(header, value)
  value = value or rand.random_string()
  return {
      append = {
        headers = {
          header .. ":" .. value,
        },
      },
    }
end

local function new_filter(value)
  return {
    name = "response_transformer",
    config = cjson.encode(rt_config(FILTER_HEADER, value)),
  }
end

local function new_plugin(value)
  return {
    name = "response-transformer",
    config = rt_config(PLUGIN_HEADER, value),
  }
end

local function new_filter_chain(value)
  return {
    filters = {
      {
        name = "response_transformer",
        config = cjson.encode(rt_config(FILTER_CHAIN_HEADER, value)),
      },
    },
  }
end

for _, strategy in helpers.each_strategy({ "postgres" }) do

describe("#wasm filters as plugins (#" .. strategy .. ")", function()
  local bp, db
  local admin, proxy
  local service, route

  local function assert_bad_response(res)
    assert.response(res).has.status(400)
    return assert.response(res).has.jsonbody()
  end

  local function check_response(header_name, header_value, context)
    helpers.wait_for_all_config_update()

    local res, err = proxy:send({ path = "/status/200" })
    assert(res and err == nil, tostring(err) .. ": " .. context)

    assert.response(res).has.status(200)
    local got = assert.response(res).has.header(header_name)
    assert.equals(header_value, got, context)
  end

  local function check_filter_response(header_value, context)
    return check_response(FILTER_HEADER, header_value, context)
  end

  local function admin_request(method, path, data)
    local params = (data ~= nil and json_request(data)) or {}
    params.method = method
    params.path = path

    local res, err = admin:send(params)
    assert.is_nil(err)
    return res
  end

  local function create_plugin(plugin)
    local res = admin:post("/plugins", json_request(plugin))
    assert.response(res).has.status(201)
    return assert.response(res).has.jsonbody()
  end

  local function update_plugin(id, plugin)
    local res = admin:patch("/plugins/" .. id, json_request(plugin))
    assert.response(res).has.status(200)
    return assert.response(res).has.jsonbody()
  end

  local function get_plugin(endpoint, id)
    local res = admin:get("/plugins/" .. id)
    assert.response(res).has.status(200)
    return assert.response(res).has.jsonbody()
  end

  local function create_filter_chain(fc)
    local res = admin:post("/filter-chains", json_request(fc))
    assert.response(res).has.status(201)
    return assert.response(res).has.jsonbody()
  end


  lazy_setup(function()
    require("kong.runloop.wasm").enable({
      { name = "response_transformer",
        path = FILTER_PATH .. "/response_transformer.wasm",
      },
    })

    bp, db = helpers.get_db_utils(strategy, {
      "routes",
      "services",
      "filter_chains",
      "plugins",
    })

    helpers.start_kong({
      database = strategy,
      nginx_conf = "spec/fixtures/custom_nginx.template",
      nginx_main_worker_processes = "2",
      wasm = true,
      wasm_filters = "response_transformer",
      plugins = "response-transformer",
    })

    admin = helpers.admin_client()
    proxy = helpers.proxy_client()
    proxy.reopen = true
  end)

  lazy_teardown(function()
    if admin then
      admin:close()
    end

    if proxy then
      proxy:close()
    end

    helpers.stop_kong()
  end)

  before_each(function()
    -- create a scratch service/route to use
    service = assert(bp.services:insert({}))
    route = assert(bp.routes:insert({
      paths = { "/" },
      service = service,
    }))
  end)

  after_each(function()
    bp.filter_chains:truncate()
    bp.plugins:truncate()

    db.routes:delete(route)
    db.services:delete(service)
  end)

  describe("/plugins", function()
    describe("POST", function()
      it("creates a plugin instance from a filter", function()
        local value = rand.random_string()
        local filter = new_filter(value)
        filter.route = { id = route.id }
        create_plugin(filter)
        check_filter_response(value, "POST /plugins")
      end)

      it("validates foreign references", function()
        local filter = new_filter()

        filter.route = { id = uuid.uuid() }
        local res = admin_request("POST", "/plugins", filter)
        local err = assert_bad_response(res)
        assert.equals("foreign key violation", err.name)
        assert.same({ route = filter.route }, err.fields)

        filter.route = nil
        filter.service = { id = uuid.uuid() }
        local res = admin_request("POST", "/plugins", filter)
        local err = assert_bad_response(res)
        assert.equals("foreign key violation", err.name)
        assert.same({ service = filter.service }, err.fields)
      end)
    end)
  end)

  describe("/plugins/:id", function()
    local plugin
    local path

    before_each(function()
      local value = rand.random_string()
      local filter = new_filter(value)
      filter.route = { id = route.id }
      plugin = create_plugin(filter)
      path = "/plugins/" .. plugin.id
      check_filter_response(value, "POST /plugins")
    end)

    after_each(function()
      db.plugins:delete(plugin)
    end)

    describe("GET", function()
      it("retrieves a wasm filter plugin instance", function()
        local got = get_plugin("/plugins", plugin.id)
        assert.same(plugin, got)
      end)
    end)

    describe("PATCH", function()
      it("updates a wasm filter plugin instance", function()
        local value = rand.random_string()
        local updated = update_plugin(plugin.id, {
          config = cjson.encode(rt_config(FILTER_HEADER, value)),
        })

        assert.not_same(plugin, updated)
        check_filter_response(value, "PATCH /plugins/:id")
      end)
    end)

    describe("DELETE", function()
      it("removes a wasm filter plugin instance", function()
        local res = admin:delete(path)
        assert.response(res).has.status(204)

        res = admin:get(path)
        assert.response(res).status(404)
      end)
    end)
  end)

  describe("filter plugins and lua plugins", function()
    it("can coexist", function()
      local filter_value = rand.random_string()
      local filter = new_filter(filter_value)
      filter.route = { id = route.id }

      local plugin_value = rand.random_string()
      local plugin = new_plugin(plugin_value)
      plugin.route = { id = route.id }

      create_plugin(filter)
      create_plugin(plugin)

      helpers.wait_for_all_config_update()

      local res = proxy:get("/status/200")
      assert.response(res).has.status(200)

      assert.equals(filter_value, assert.response(res).has.header(FILTER_HEADER))
      assert.equals(plugin_value, assert.response(res).has.header(PLUGIN_HEADER))
    end)
  end)

  describe("filter plugins and filter chains", function()
    it("can coexist", function()
      local filter_value = rand.random_string()
      local filter = new_filter(filter_value)
      filter.route = { id = route.id }

      local fc_value = rand.random_string()
      local fc = new_filter_chain(fc_value)
      fc.route = { id = route.id }

      create_plugin(filter)
      create_filter_chain(fc)

      helpers.wait_for_all_config_update()

      local res = proxy:get("/status/200")
      assert.response(res).has.status(200)

      assert.equals(filter_value, assert.response(res).has.header(FILTER_HEADER))
      assert.equals(fc_value, assert.response(res).has.header(FILTER_CHAIN_HEADER))
    end)
  end)
end)

end -- each strategy
