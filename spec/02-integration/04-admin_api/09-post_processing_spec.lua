local helpers = require "spec.helpers"
local cjson   = require "cjson"


local function it_content_types(title, fn)
  local test_form_encoded = fn("application/x-www-form-urlencoded")
  local test_json = fn("application/json")
  it(title .. " with application/www-form-urlencoded", test_form_encoded)
  it(title .. " with application/json", test_json)
end


describe("Admin API post-processing", function()
  local client

  setup(function()
    assert(helpers.dao:run_migrations())
    assert(helpers.start_kong {
      custom_plugins = "admin-api-post-process"
    })

    client = assert(helpers.admin_client())
  end)

  teardown(function()
    if client then
      client:close()
    end

    helpers.stop_kong()
  end)

  before_each(function()
    helpers.dao:truncate_tables()

    helpers.register_consumer_relations(helpers.dao)

    assert(helpers.dao.consumers:insert({
      username = "michael",
      custom_id = "landon",
    }))
  end)

  it_content_types("post-processes paginated sets", function(content_type)
    return function()
      local res = assert(client:send {
        method = "GET",
        path = "/consumers/post_processed",
        headers = { ["Content-Type"] = content_type }
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body).data[1]
      assert.equal("MICHAEL", json.username)
      assert.equal("LANDON", json.custom_id)
    end
  end)

  it_content_types("post-processes crud.post", function(content_type)
    return function()
      local res = assert(client:send {
        method = "POST",
        path = "/consumers/post_processed",
        body = {
          username = "devon",
          custom_id = "miles",
        },
        headers = { ["Content-Type"] = content_type }
      })
      local body = assert.res_status(201, res)
      local json = cjson.decode(body)
      assert.equal("DEVON", json.username)
      assert.equal("MILES", json.custom_id)
    end
  end)

  it_content_types("post-processes crud.get", function(content_type)
    return function()
      local res = assert(client:send {
        method = "GET",
        path = "/consumers/michael/post_processed",
        headers = { ["Content-Type"] = content_type }
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.equal("MICHAEL", json.username)
      assert.equal("LANDON", json.custom_id)
    end
  end)

  it_content_types("post-processes crud.patch", function(content_type)
    return function()
      local res = assert(client:send {
        method = "PATCH",
        path = "/consumers/michael/post_processed",
        body = {
          custom_id = "knight",
        },
        headers = { ["Content-Type"] = content_type }
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.equal("MICHAEL", json.username)
      assert.equal("KNIGHT", json.custom_id)
    end
  end)

  it_content_types("post-processes crud.put", function(content_type)
    return function()
      local res = assert(client:send {
        method = "PUT",
        path = "/consumers/michael/post_processed",
        body = {
          username = "garthe",
          custom_id = "knight",
        },
        headers = { ["Content-Type"] = content_type }
      })
      local body = assert.res_status(201, res)
      local json = cjson.decode(body)
      assert.equal("GARTHE", json.username)
      assert.equal("KNIGHT", json.custom_id)
    end
  end)
end)
