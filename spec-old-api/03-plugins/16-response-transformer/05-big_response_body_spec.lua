local helpers = require "spec.helpers"

local function create_big_data(size)
  return {
    mock_json = {
      big_field = string.rep("*", size),
    },
  }
end

describe("Plugin: response-transformer", function()
  local client

  lazy_setup(function()
    local _, db, dao = helpers.get_db_utils()

    local api = assert(dao.apis:insert {
      name         = "tests-response-transformer",
      hosts        = { "response.com" },
      upstream_url = helpers.mock_upstream_url,
    })
    assert(db.plugins:insert {
      api = { id = api.id },
      name   = "response-transformer",
      config = {
        add    = {
          json = {"p1:v1"},
        },
        remove = {
          json = {"params"},
        }
      },
    })

    assert(helpers.start_kong({
        nginx_conf = "spec/fixtures/custom_nginx.template",
    }))
  end)


  lazy_teardown(function()
    helpers.stop_kong()
  end)

  before_each(function()
    client = helpers.proxy_client()
  end)

  after_each(function()
    if client then client:close() end
  end)

  it("add new parameters on large POST", function()
    local r = assert(client:send {
      method = "POST",
      path = "/post",
      body = create_big_data(1024 * 1024),
      headers = {
        host = "response.com",
        ["content-type"] = "application/json",
      }
    })
    assert.response(r).has.status(200)
    local json = assert.response(r).has.jsonbody()
    assert.equal("v1", json.p1)
  end)
  it("remove parameters on large POST", function()
    local r = assert(client:send {
      method = "POST",
      path = "/post",
      body = create_big_data(1024 * 1024),
      headers = {
        host = "response.com",
        ["content-type"] = "application/json",
      }
    })
    assert.response(r).has.status(200)
    local json = assert.response(r).has.jsonbody()
    assert.is_nil(json.params)
  end)
end)
