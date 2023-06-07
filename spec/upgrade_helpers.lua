setmetatable(_G, nil)

local say = require "say"
local assert = require "luassert"

local busted = require "busted"

local conf_loader = require "kong.conf_loader"
local DB = require "kong.db"
local helpers = require "spec.helpers"

local conf = conf_loader()

local function database_type()
  return conf['database']
end

local function get_database()
  local db = assert(DB.new(conf))
  assert(db:init_connector())
  return db
end

local function database_has_trigger(state, arguments)
  local trigger_name = arguments[1]
  local db = get_database()
  local res, err
  if database_type() == 'postgres' then
    res, err = db.connector:query(string.format(
        "select true"
        .. " from pg_trigger"
        .. " where tgname = '%s'",
        trigger_name))
  else
    return false
  end
  if err then
    return false
  end
  return not(not(res[1]))
end

say:set("assertion.database_has_trigger.positive", "Expected database to have trigger %s")
say:set("assertion.database_has_trigger.negative", "Expected database not to have trigger %s")
assert:register("assertion", "database_has_trigger", database_has_trigger, "assertion.database_has_trigger.positive", "assertion.database_has_trigger.negative")

local function table_has_column(state, arguments)
  local table = arguments[1]
  local column_name = arguments[2]
  local postgres_type = arguments[3]
  local db = get_database()
  local res, err
  if database_type() == 'postgres' then
    res, err = db.connector:query(string.format(
        "select true"
        .. " from information_schema.columns"
        .. " where table_schema = 'public'"
        .. "   and table_name = '%s'"
        .. "   and column_name = '%s'"
        .. "   and data_type = '%s'",
        table, column_name, postgres_type))
  else
    return false
  end
  if err then
    return false
  end
  return not(not(res[1]))
end

say:set("assertion.table_has_column.positive", "Expected table %s to have column %s with type %s")
say:set("assertion.table_has_column.negative", "Expected table %s not to have column %s with type %s")
assert:register("assertion", "table_has_column", table_has_column, "assertion.table_has_column.positive", "assertion.table_has_column.negative")

local upstream_server_url = "http://" .. helpers.mock_upstream_host .. ":" .. helpers.mock_upstream_port .. "/"

local function create_example_service()
  local admin_client = assert(helpers.admin_client())
  local res = assert(admin_client:send {
      method = "POST",
      path = "/services/",
      body = {
        name = "example-service",
        url = upstream_server_url
      },
      headers = {
        ["Content-Type"] = "application/json"
      }
  })
  assert.res_status(201, res)
  res = assert(admin_client:send {
      method = "POST",
      path = "/services/example-service/routes",
      body = {
        hosts = { "example.com" },
      },
      headers = {
        ["Content-Type"] = "application/json"
      }
  })
  assert.res_status(201, res)
  admin_client:close()
end

local function send_proxy_get_request()
  local proxy_client = assert(helpers.proxy_client())
  local res = assert(proxy_client:send {
      method  = "GET",
      headers = {
        ["Host"] = "example.com",
      },
      path = "/",
  })
  local body = assert.res_status(200, res)
  proxy_client:close()

  return res, body
end

local function start_kong()
  return helpers.start_kong {
    database = database_type(),
    dns_resolver          = "",
    proxy_listen          = "0.0.0.0:9000",
    admin_listen          = "0.0.0.0:9001",
    admin_ssl             = false,
    admin_gui_ssl         = false,
    nginx_conf            = "spec/fixtures/custom_nginx.template",
  }
end

local function it_when(phase, phrase, f)
  return busted.it(phrase .. " #" .. phase, f)
end

local function setup(f)
  return busted.it("setting up kong #setup", f)
end

local function old_after_up(phrase, f)
  return it_when("old_after_up", phrase, f)
end

local function new_after_up(phrase, f)
  return it_when("new_after_up", phrase, f)
end

local function new_after_finish(phrase, f)
  return it_when("new_after_finish", phrase, f)
end

local function all_phases(phrase, f)
  return it_when("all_phases", phrase, f)
end

local latest_kong_require_meta

-- This is a hack to make the latest kong module and helper functions available to the test suite
local function latest_kong_require(module)
  -- backport of `string.buffer` module of LuaJIT
  if module == "string.buffer" then
    module = "latest.spec.string_buffer"
  elseif "kong." == module:sub(1, 5) or "spec." == module:sub(1, 5) then
    module = "latest." .. module
  end

  if package.loaded[module] then
    return package.loaded[module]
  end

  local path = package.searchpath(module, package.path .. ";./?/init.lua")

  -- some buildin modules like ffi don't have a path
  if not path then
    return require(module)
  end

  local module_code = assert(loadfile(path))
  -- recursively load with lastest code
  setfenv(module_code, latest_kong_require_meta)

  package.loaded[module] = assert(module_code())
  
  return package.loaded[module]
end

latest_kong_require_meta = { require = latest_kong_require, __index = _G }
setmetatable(latest_kong_require_meta, latest_kong_require_meta)

local latest_helpers = latest_kong_require "spec.helpers"

return {
  database_type = database_type,
  get_database = get_database,
  create_example_service = create_example_service,
  send_proxy_get_request = send_proxy_get_request,
  start_kong = start_kong,
  stop_kong = helpers.stop_kong,
  admin_client = helpers.admin_client,
  proxy_client = helpers.proxy_client,
  setup = setup,
  old_after_up = old_after_up,
  new_after_up = new_after_up,
  new_after_finish = new_after_finish,
  all_phases = all_phases,
  latest_kong_require = latest_kong_require,
  latest_helpers = latest_helpers,
}
