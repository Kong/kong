local helpers = require "spec.helpers"

local function create_big_data(size)
  return string.format([[
    {"mock_json":{"big_field":"%s"}}
  ]], string.rep("*", size))
end

describe("Plugin: response transformer", function()

  local client

  setup(function()
    helpers.dao:truncate_tables()
    helpers.execute "pkill nginx; pkill serf"
    assert(helpers.prepare_prefix())

    local api = assert(helpers.dao.apis:insert {
      name = "tests-response-transformer",
      request_host = "response.com",
      upstream_url = "http://httpbin.org",
    })

    assert(helpers.dao.plugins:insert {
      api_id = api.id,
      name = "response-transformer",
      config = {
        add = {
          json = {"p1:v1"},
        },
        remove = {
          json = {"json"},
        }
      }
    })

    assert(helpers.start_kong())
  end)

  teardown(function()
    helpers.stop_kong()
  end)

  before_each(function()
    client = assert(helpers.proxy_client())
  end)

  after_each(function()
    if client then client:close() end
  end)

  it("add new parameters on large POST", function()
    local r = assert(client:send {
      method = "POST",
      path = "/post",
      body = {create_big_data(1 * 1024 * 1024)},
      headers = {
        host = "response.com",
        ["content-type"] = "application/json",
      }
    })
    assert.response(r).has.status(200)
    local json = assert.response(r).has.jsonbody()
    assert.equals("v1", json.p1)
  end)
  it("remove parameters on large POST", function()
    local r = assert(client:send {
      method = "POST",
      path = "/post",
      body = {create_big_data(1 * 1024 * 1024)},
      headers = {
        host = "response.com",
        ["content-type"] = "application/json",
      }
    })
    assert.response(r).has.status(200)
    local json = assert.response(r).has.jsonbody()
    assert.is_nil(json.json)
  end)
end)
