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
  local admin_client, proxy_client

  lazy_setup(function()
    assert(helpers.start_kong({
      database   = "off",
    }))

    admin_client = assert(helpers.admin_client())
    proxy_client = assert(helpers.proxy_client())
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

describe("lmdb limits key size to less than 511 chars #off", function()
  local admin_client, proxy_client

  lazy_setup(function()
    assert(helpers.start_kong({
      database   = "off",
    }))

    admin_client = assert(helpers.admin_client())
    proxy_client = assert(helpers.proxy_client())
  end)

  lazy_teardown(function()
    admin_client:close()
    proxy_client:close()
    helpers.stop_kong(nil, true)
  end)

  it("(generate cachekey - issue 10219)", function()
    local yaml_file = helpers.make_yaml_file([[
      _format_version: '3.0'
      services:
      - name: my-service
        url: https://127.0.0.1:15556
        plugins:
        - name: key-auth
        routes:
        - name: my-route
          paths:
          - /
      consumers:
      - username: credential-bigger-than-512-chars
        keyauth_credentials:
        - key: 6y8fivuu6jj822b77hcuxp6z33pxgie3t5ypx8mwuxne59gp3yvgt62m2vazuu8b3ahyjhzdmri8bk768qpdp745ijt362f3z5nnwgn785iakpwia5pegwpxki4k8xjzrac2nbg2ff3adrbbgmw7ihj8mj4itwmjaxkkrany5qnb7za46imhc9vwqmg4vpqf5vkza5dfgkr8fphpfrk6bcgz2mxuqgvcvadjb974jpjuctfjptw4j5izb68pywg9a7h85wfdddxh7j7j9yd2cxtvyk7n4cggibec9qtjhci8rdhuwcf2ixtfk4vm6hzj5j6ece9xwuxicdtrizwgm6mrx99av4ukw4c9qp7yr23ij9tutph8gek698765ydjrmgkm88pyzuq7jabpeqe7ae9j8qiew2d9rjdmmd27nmtkdgajrg78347dmrbgvxzjw3f4ewakckxnia3izv7itqa9bufnjn7rd9mwkvzfmuba4hrwk49f2ktzw9npw94
    ]])

    assert(helpers.start_kong({
      database = "off",
      declarative_config = yaml_file,
      nginx_worker_processes = 1,
      nginx_conf = "spec/fixtures/custom_nginx.template",
    }))

    assert.logfile().has.no.line("[crit]", true)
    assert.logfile().has.no.line("MDB_BAD_VALSIZE", true)

    proxy_client = helpers.proxy_client()
    local res = assert(proxy_client:send {
      method  = "GET",
      path    = "/",
      headers = {
        ["apikey"] = "6y8fivuu6jj822b77hcuxp6z33pxgie3t5ypx8mwuxne59gp3yvgt62m2vazuu8b3ahyjhzdmri8bk768qpdp745ijt362f3z5nnwgn785iakpwia5pegwpxki4k8xjzrac2nbg2ff3adrbbgmw7ihj8mj4itwmjaxkkrany5qnb7za46imhc9vwqmg4vpqf5vkza5dfgkr8fphpfrk6bcgz2mxuqgvcvadjb974jpjuctfjptw4j5izb68pywg9a7h85wfdddxh7j7j9yd2cxtvyk7n4cggibec9qtjhci8rdhuwcf2ixtfk4vm6hzj5j6ece9xwuxicdtrizwgm6mrx99av4ukw4c9qp7yr23ij9tutph8gek698765ydjrmgkm88pyzuq7jabpeqe7ae9j8qiew2d9rjdmmd27nmtkdgajrg78347dmrbgvxzjw3f4ewakckxnia3izv7itqa9bufnjn7rd9mwkvzfmuba4hrwk49f2ktzw9npw94"
      }
    })

    assert.res_status(200, res)
  end)
end)
