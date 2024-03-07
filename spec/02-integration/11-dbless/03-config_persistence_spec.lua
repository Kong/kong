local helpers = require "spec.helpers"

local fmt = string.format

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

describe("dbless persistence #off", function()
  lazy_setup(function()
    assert(helpers.start_kong({
      database = "off",
    }))
  end)

  lazy_teardown(function()
    helpers.stop_kong()
  end)

  it("loads the lmdb config on restarts", function()
    local buffer = {"_format_version: '3.0'", "services:"}
    for i = 1, 1001 do
      buffer[#buffer + 1] = fmt(SERVICE_YML, i, i, i, i)
    end
    local config = table.concat(buffer, "\n")

    local admin_client = assert(helpers.admin_client())
    local res = admin_client:post("/config",{
      body = { config = config },
      headers = {
        ["Content-Type"] = "application/json",
      }
    })
    assert.res_status(201, res)
    admin_client:close()

    assert(helpers.restart_kong({
        database = "off",
    }))

    local proxy_client = assert(helpers.proxy_client())

    res = assert(proxy_client:get("/1", { headers = { host = "example1.dev" } }))
    assert.res_status(401, res)
    res = assert(proxy_client:get("/1000", { headers = { host = "example1.dev" } }))
    assert.res_status(401, res)
    proxy_client:close()

    assert.logfile().has.line("found persisted lmdb config")
  end)
end)

describe("dbless persistence with a declarative config #off", function()
  local yaml_file

  lazy_setup(function()
    yaml_file = helpers.make_yaml_file([[
      _format_version: "3.0"
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
        database = "off",
        declarative_config = yaml_file,
    }))
    local admin_client = assert(helpers.admin_client())
    local proxy_client = assert(helpers.proxy_client())

    local res = assert(proxy_client:get("/test", { headers = { host = "example1.dev" } }))
    assert.res_status(401, res)
    proxy_client:close()

    local buffer = {"_format_version: '3.0'", "services:"}
    local i = 500
    buffer[#buffer + 1] = fmt(SERVICE_YML, i, i, i, i)
    local config = table.concat(buffer, "\n")
    local res = admin_client:post("/config", {
      body = { config = config },
      headers = {
        ["Content-Type"] = "application/json",
      }
    })
    assert.res_status(201, res)
    admin_client:close()

    assert
      .with_timeout(5)
      .eventually(function()
        proxy_client = assert(helpers.proxy_client())
        res = proxy_client:get("/500", { headers = { host = "example1.dev" } })
        res:read_body()
        proxy_client:close()
        return res and res.status == 401
      end)
      .is_truthy()
  end)

  after_each(function()
    helpers.stop_kong()
  end)
  lazy_teardown(function()
    os.remove(yaml_file)
  end)

  it("doesn't load the persisted lmdb config if a declarative config is set on restart", function()
    assert(helpers.restart_kong({
        database = "off",
        declarative_config = yaml_file,
    }))

    assert
      .with_timeout(15)
      .eventually(function ()
        local proxy_client = helpers.proxy_client()
        local res = proxy_client:get("/test", { headers = { host = "example1.dev" } })
        assert.res_status(401, res) -- 401, should load the declarative config

        res = proxy_client:get("/500", { headers = { host = "example1.dev" } })
        assert.res_status(404, res) -- 404, should not load the persisted lmdb config

        proxy_client:close()
      end)
      .has_no_error()
  end)

  it("doesn't load the persisted lmdb config if a declarative config is set on reload", function()
    assert(helpers.reload_kong("off", "reload --prefix " .. helpers.test_conf.prefix, {
      database = "off",
      declarative_config = yaml_file,
    }))

    assert
      .with_timeout(15)
      .eventually(function ()
        local proxy_client = helpers.proxy_client()
        local res = proxy_client:get("/test", { headers = { host = "example1.dev" } })
        assert.res_status(401, res) -- 401, should load the declarative config

        res = proxy_client:get("/500", { headers = { host = "example1.dev" } })
        assert.res_status(404, res) -- 404, should not load the persisted lmdb config

        proxy_client:close()
      end)
      .has_no_error()
  end)
end)
