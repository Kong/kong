local helpers = require "spec.helpers"

local fmt = string.format

local KONG_VERSION = require("kong.meta").version

local SERVICE_YML = [[
- name: my-service-%d
  url: https://example%d.dev
  plugins:
  - name: key-auth
  routes:
  - name: my-route-%d
    paths:
    - /%d
]]

local verify_lmdb_kong_version
local set_lmdb_kong_version
do
  local TEST_CONF = helpers.test_conf
  local LMDB_KONG_VERSION_KEY = require("kong.constants").LMDB_KONG_VERSION_KEY

  verify_lmdb_kong_version = function()
    local cmd = string.format(
      [[resty --main-conf "lmdb_environment_path %s/%s;" spec/fixtures/dump_lmdb_key.lua %q]],
      TEST_CONF.prefix, TEST_CONF.lmdb_environment_path, LMDB_KONG_VERSION_KEY)

    local handle = io.popen(cmd)
    local result = handle:read("*a")
    handle:close()

    assert.equals(KONG_VERSION, result)
  end

  set_lmdb_kong_version = function(value)
    local cmd = string.format(
      [[resty --main-conf "lmdb_environment_path %s/%s;" -e '
          local lmdb = require("resty.lmdb")
          ngx.print(lmdb.set(%q, %q))
        ']],
      TEST_CONF.prefix, TEST_CONF.lmdb_environment_path,
      LMDB_KONG_VERSION_KEY, value)

    local handle = io.popen(cmd)
    local result = handle:read("*a")
    handle:close()

    assert.equals("true", result)
  end
end

describe("dbless persistence #off", function()
  local admin_client, proxy_client

  lazy_setup(function()
    -- set a old verion into lmdb
    set_lmdb_kong_version("1.0")

    assert(helpers.start_kong({
      database   = "off",
    }))

    admin_client = assert(helpers.admin_client())
    proxy_client = assert(helpers.proxy_client())

    assert.logfile().has.line("current Kong v" .. KONG_VERSION .. " mismatches cache v1.0")
  end)

  lazy_teardown(function()
    admin_client:close()
    proxy_client:close()
    helpers.stop_kong(nil, true)
  end)

  it("loads the lmdb config on restarts", function()
    local buffer = {"_format_version: '1.1'", "services:"}
    for i = 1, 1001 do
      buffer[#buffer + 1] = fmt(SERVICE_YML, i, i, i, i)
    end
    local config = table.concat(buffer, "\n")

    local res = admin_client:post("/config",{
      body = { config = config },
      headers = {
        ["Content-Type"] = "application/json"
      }
    })
    assert.res_status(201, res)

    assert(helpers.restart_kong({
        database   = "off",
    }))

    proxy_client:close()
    proxy_client = assert(helpers.proxy_client())

    res = assert(proxy_client:get("/1", { headers = { host = "example1.dev" } }))
    assert.res_status(401, res)
    res = assert(proxy_client:get("/1000", { headers = { host = "example1.dev" } }))
    assert.res_status(401, res)

    assert.logfile().has.line("found persisted lmdb config")

    verify_lmdb_kong_version()
  end)
end)

describe("dbless persistence with a declarative config #off", function()
  local admin_client, proxy_client, yaml_file

  lazy_setup(function()
    yaml_file = helpers.make_yaml_file([[
      _format_version: "1.1"
      services:
      - name: my-service
        url: https://example1.dev
        plugins:
        - name: key-auth
        routes:
        - name: my-route
          paths:
          - /test
    ]])
  end)

  before_each(function()
    assert(helpers.start_kong({
        database   = "off",
        declarative_config = yaml_file,
    }))
    admin_client = assert(helpers.admin_client())
    proxy_client = assert(helpers.proxy_client())

    local res = assert(proxy_client:get("/test", { headers = { host = "example1.dev" } }))
    assert.res_status(401, res)

    local buffer = {"_format_version: '1.1'", "services:"}
    local i = 500
    buffer[#buffer + 1] = fmt(SERVICE_YML, i, i, i, i)
    local config = table.concat(buffer, "\n")
    local res = admin_client:post("/config",{
      body = { config = config },
      headers = {
        ["Content-Type"] = "application/json"
      }
    })
    assert.res_status(201, res)
    res = assert(proxy_client:get("/500", { headers = { host = "example1.dev" } }))
    assert.res_status(401, res)

    proxy_client:close()

    verify_lmdb_kong_version()
  end)

  after_each(function()
    if admin_client then
      admin_client:close()
    end
    if proxy_client then
      proxy_client:close()
    end
    helpers.stop_kong(nil, true)
  end)
  lazy_teardown(function()
    os.remove(yaml_file)
  end)

  it("doesn't load the persisted lmdb config if a declarative config is set on restart", function()
    assert(helpers.restart_kong({
        database   = "off",
        declarative_config = yaml_file,
    }))
    proxy_client = assert(helpers.proxy_client())
    local res = assert(proxy_client:get("/test", { headers = { host = "example1.dev" } }))
    assert.res_status(401, res)

    res = assert(proxy_client:get("/500", { headers = { host = "example1.dev" } }))
    assert.res_status(404, res) -- 404, only the declarative config is loaded
  end)

  it("doesn't load the persisted lmdb config if a declarative config is set on reload", function()
    assert(helpers.reload_kong("off", "reload --prefix " .. helpers.test_conf.prefix, {
      database   = "off",
      declarative_config = yaml_file,
    }))
    local res
    helpers.wait_until(function()
      proxy_client = assert(helpers.proxy_client())
      res = assert(proxy_client:get("/test", { headers = { host = "example1.dev" } }))
      proxy_client:close()
      return res.status == 401
    end)

    proxy_client = assert(helpers.proxy_client())
    res = assert(proxy_client:get("/500", { headers = { host = "example1.dev" } }))
    assert.res_status(404, res) -- 404, only the declarative config is loaded
  end)
end)
